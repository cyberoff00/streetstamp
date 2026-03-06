import SwiftUI
import UIKit
@main
struct StreetStampsApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("streetstamps.intro_slides_shown.v1") private var hasSeenIntroSlides = false
    @AppStorage(AppSettings.lifelogBackgroundModeKey) private var lifelogBackgroundModeRaw = LifelogBackgroundMode.defaultMode.rawValue
    @StateObject private var locationHub = LocationHub.shared
    @StateObject private var sessionStore: UserSessionStore
    @StateObject private var journeyStore: JourneyStore
    @StateObject private var cityCache: CityCache
    @StateObject private var lifelogStore: LifelogStore
    @StateObject private var trackTileStore: TrackTileStore
    @StateObject private var socialStore: SocialGraphStore
    @StateObject private var postcardCenter: PostcardCenter
    @StateObject private var flow = AppFlowCoordinator()
    @StateObject private var deepLinkStore = AppDeepLinkStore()
    @StateObject private var onboardingGuide = OnboardingGuideStore()
    @State private var showAuthEntry = false
    @State private var showSplash = true
    @State private var scheduledTileRebuild: DispatchWorkItem?
    @State private var trackTileRebuildTask: Task<Void, Never>?

    private var lifelogBackgroundMode: LifelogBackgroundMode {
        LifelogBackgroundMode(rawValue: lifelogBackgroundModeRaw) ?? .defaultMode
    }

    /// Ensure passive location stream is alive for Lifelog when no active journey is running.
    private func ensurePassiveLocationTrackingIfNeeded() {
        if !TrackingService.shared.isTracking {
            locationHub.startPassiveLifelog(mode: lifelogBackgroundMode)
        }
    }

    @MainActor
    private func maybeShowFirstAuthPromptIfNeeded() {
        let firstPromptKey = "streetstamps.auth_entry_shown.v1"
        if hasSeenIntroSlides &&
            !sessionStore.isLoggedIn &&
            !UserDefaults.standard.bool(forKey: firstPromptKey) {
            UserDefaults.standard.set(true, forKey: firstPromptKey)
            showAuthEntry = true
        }
    }

    init() {
        let session = UserSessionStore()
        _sessionStore = StateObject(wrappedValue: session)

        let paths = StoragePath(userID: session.currentUserID)
        let jStore = JourneyStore(paths: paths)
        _journeyStore = StateObject(wrappedValue: jStore)
        _cityCache = StateObject(wrappedValue: CityCache(paths: paths, journeyStore: jStore))
        let llStore = LifelogStore(paths: paths)
        _lifelogStore = StateObject(wrappedValue: llStore)
        _trackTileStore = StateObject(wrappedValue: TrackTileStore(paths: paths))
        _socialStore = StateObject(wrappedValue: SocialGraphStore(userID: session.currentUserID))
        _postcardCenter = StateObject(wrappedValue: PostcardCenter(userID: session.currentUserID))

        configureGlobalTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            appContent
        }
    }

    @ViewBuilder
    private var mainEntryContent: some View {
        if hasSeenIntroSlides {
            MainTabView()
        } else {
            IntroSlidesView {
                hasSeenIntroSlides = true
            }
        }
    }

    private var appContentWithEnvironment: some View {
        mainEntryContent
            .environmentObject(locationHub)
            .environmentObject(sessionStore)
            .environmentObject(journeyStore)
            .environmentObject(cityCache)
            .environmentObject(lifelogStore)
            .environmentObject(trackTileStore)
            .environmentObject(socialStore)
            .environmentObject(postcardCenter)
            .environmentObject(flow)
            .environmentObject(deepLinkStore)
            .environmentObject(onboardingGuide)
    }

    private var appContentWithPresentation: some View {
        appContentWithEnvironment
            .overlay {
                if showSplash {
                    AppSplashView()
                    .transition(.opacity)
                    .zIndex(999)
                }
            }
            .fullScreenCover(isPresented: $showAuthEntry) {
                AuthEntryView(
                    onContinueGuest: { showAuthEntry = false },
                    onAuthenticated: { showAuthEntry = false }
                )
                .environmentObject(sessionStore)
                .environmentObject(journeyStore)
                .environmentObject(cityCache)
                .environmentObject(socialStore)
                .environmentObject(postcardCenter)
            }
    }

    private var appContent: some View {
        appContentWithPresentation
            .task {
                guard showSplash else { return }
                try? await Task.sleep(nanoseconds: 3_350_000_000)
                await MainActor.run {
                    hideSplash()
                }
            }
            .task {
                BackendAPIClient.shared.bindSessionStore(sessionStore)
                let startupUserID = sessionStore.currentUserID
                await sessionStore.bootstrapFileSystemAsync()
                await LifelogMigrationService.migrateLegacyLifelogIfNeededAsync(
                    paths: StoragePath(userID: startupUserID)
                )
                journeyStore.load()
                lifelogStore.load()
                lifelogStore.bind(to: locationHub)
                scheduleTrackTileRebuild(delay: 0.10, force: false)

                Task { @MainActor in
                    await Task.yield()
                    VoiceBroadcastService.shared.start()
                    onboardingGuide.startIfNeeded()
                    maybeShowFirstAuthPromptIfNeeded()
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    locationHub.requestPermissionIfNeeded()
                    ensurePassiveLocationTrackingIfNeeded()
                }
            }
            .onChange(of: hasSeenIntroSlides) { _, seen in
                guard seen else { return }
                maybeShowFirstAuthPromptIfNeeded()
            }
            .onChange(of: sessionStore.currentUserID) { _, uid in
                Task {
                    let paths = StoragePath(userID: uid)
                    await sessionStore.bootstrapFileSystemAsync()
                    await LifelogMigrationService.migrateLegacyLifelogIfNeededAsync(paths: paths)
                    guard sessionStore.currentUserID == uid else { return }

                    journeyStore.rebind(paths: paths)
                    journeyStore.load()
                    cityCache.rebind(paths: paths)
                    lifelogStore.rebind(paths: paths)
                    lifelogStore.load()
                    lifelogStore.bind(to: locationHub)
                    trackTileStore.rebind(paths: paths)
                    scheduleTrackTileRebuild(delay: 0.10, force: false)
                    ensurePassiveLocationTrackingIfNeeded()
                    socialStore.switchUser(uid)
                    postcardCenter.switchUser(uid)
                }
            }
            .onChange(of: scenePhase) { phase in
                // Best-effort: reduce data loss when the app is backgrounded or suspended.
                if phase == .background || phase == .inactive {
                    journeyStore.flushPersist()
                    lifelogStore.flushPersistNow()
                }
                if phase == .active {
                    ensurePassiveLocationTrackingIfNeeded()
                    scheduleTrackTileRebuild(delay: 0.10, force: false)
                }
            }
            .onChange(of: journeyStore.trackTileRevision) { _, _ in
                scheduleTrackTileRebuild(delay: 1.5, force: false)
            }
            .onChange(of: lifelogStore.trackTileRevision) { _, _ in
                scheduleTrackTileRebuild(delay: 1.5, force: false)
            }
            .onChange(of: flow.currentTab) { _, tab in
                if TrackTileRebuildPolicy.shouldRebuild(for: tab) {
                    // Defer heavy rebuild slightly so tab switch interaction stays responsive.
                    scheduleTrackTileRebuild(delay: 0.75, force: false)
                }
            }
            .onChange(of: lifelogBackgroundModeRaw) { _, _ in
                ensurePassiveLocationTrackingIfNeeded()
            }
            .onOpenURL { url in
                guard deepLinkStore.handleIncomingURL(url) else { return }
                flow.requestSelectTab(.friends)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                guard deepLinkStore.handleIncomingURL(url) else { return }
                flow.requestSelectTab(.friends)
            }
    }

    private func scheduleTrackTileRebuild(delay: TimeInterval = 0.25, force: Bool = true) {
        if !force && !TrackTileRebuildPolicy.shouldRebuild(for: flow.currentTab) {
            return
        }
        scheduledTileRebuild?.cancel()
        let work = DispatchWorkItem { rebuildTrackTiles() }
        scheduledTileRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func rebuildTrackTiles(zoom: Int = TrackRenderAdapter.unifiedRenderZoom) {
        let journeyRevision = journeyStore.trackTileRevision
        let passiveRevision = lifelogStore.trackTileRevision
        if let manifest = trackTileStore.currentManifest,
           manifest.zoom == zoom,
           manifest.journeyRevision == journeyRevision,
           manifest.passiveRevision == passiveRevision {
            return
        }

        trackTileRebuildTask?.cancel()
        trackTileRebuildTask = Task(priority: .utility) {
            async let journeyEvents = journeyStore.trackRenderEventsAsync()
            async let passiveEvents = lifelogStore.trackRenderEventsAsync()
            let (resolvedJourneyEvents, resolvedPassiveEvents) = await (journeyEvents, passiveEvents)
            guard !Task.isCancelled else { return }
            do {
                try trackTileStore.refresh(
                    journeyEvents: resolvedJourneyEvents,
                    passiveEvents: resolvedPassiveEvents,
                    journeyRevision: journeyRevision,
                    passiveRevision: passiveRevision,
                    zoom: zoom
                )
            } catch {
                print("⚠️ track tile refresh failed:", error)
            }
        }
    }
}

enum TrackTileRebuildPolicy {
    static func shouldRebuild(for tab: NavigationTab) -> Bool {
        tab == .lifelog
    }
}

private func configureGlobalTabBarAppearance() {
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = .white
    appearance.shadowColor = UIColor.black.withAlphaComponent(0.08)

    UITabBar.appearance().standardAppearance = appearance
    if #available(iOS 15.0, *) {
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

private extension StreetStampsApp {
    func hideSplash() {
        guard showSplash else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            showSplash = false
        }
    }
}
