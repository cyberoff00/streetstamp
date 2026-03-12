import Combine
import SwiftUI
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif
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
    @StateObject private var cityRenderCache: CityRenderCacheStore
    @StateObject private var lifelogStore: LifelogStore
    @StateObject private var trackTileStore: TrackTileStore
    @StateObject private var lifelogRenderCache: LifelogRenderCacheCoordinator
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

    private func restoreFromICloudIfNeeded(userID: String) async {
        let paths = StoragePath(userID: userID)
        let restored = await ICloudSyncService.shared.restoreLatestIfNeeded(
            userID: userID,
            paths: paths
        )
        if restored {
            print("☁️ Restored cloud snapshot for user:", userID)
        }
    }

    private func uploadSnapshotToICloud(userID: String, reason: String) async {
        let paths = StoragePath(userID: userID)
        await ICloudSyncService.shared.uploadSnapshotIfEnabled(
            userID: userID,
            paths: paths,
            reason: reason
        )
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
        #if canImport(FirebaseCore)
        if BackendConfig.firebaseBackupRuntimeEnabled,
           FirebaseApp.app() == nil,
           BackendConfig.firebaseSetupIssue() == nil {
            FirebaseApp.configure()
        }
        #endif
        let session = UserSessionStore()
        UserScopedProfileStateStore.initializeCurrentUser(session.activeLocalProfileID)
        _sessionStore = StateObject(wrappedValue: session)

        let paths = StoragePath(userID: session.activeLocalProfileID)
        let jStore = JourneyStore(paths: paths)
        _journeyStore = StateObject(wrappedValue: jStore)
        _cityCache = StateObject(wrappedValue: CityCache(paths: paths, journeyStore: jStore))
        _cityRenderCache = StateObject(wrappedValue: CityRenderCacheStore(rootDir: paths.thumbnailsDir))
        let llStore = LifelogStore(paths: paths)
        _lifelogStore = StateObject(wrappedValue: llStore)
        _trackTileStore = StateObject(wrappedValue: TrackTileStore(paths: paths))
        _lifelogRenderCache = StateObject(wrappedValue: LifelogRenderCacheCoordinator())
        _socialStore = StateObject(wrappedValue: SocialGraphStore(userID: session.activeLocalProfileID))
        _postcardCenter = StateObject(wrappedValue: PostcardCenter(userID: session.activeLocalProfileID))

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
            .environmentObject(cityRenderCache)
            .environmentObject(lifelogStore)
            .environmentObject(trackTileStore)
            .environmentObject(lifelogRenderCache)
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
                .environmentObject(deepLinkStore)
                .environmentObject(journeyStore)
                .environmentObject(cityCache)
                .environmentObject(socialStore)
                .environmentObject(postcardCenter)
            }
    }

    private var appContentWithLifecycleHandlers: some View {
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
                let startupUserID = sessionStore.activeLocalProfileID
                await sessionStore.bootstrapFileSystemAsync()
                await LifelogMigrationService.migrateLegacyLifelogIfNeededAsync(
                    paths: StoragePath(userID: startupUserID)
                )
                await restoreFromICloudIfNeeded(userID: startupUserID)
                journeyStore.load()
                let journeysSnapshot = journeyStore.journeys
                let cachedCitiesSnapshot = cityCache.cachedCities
                let appearanceRaw = MapAppearanceSettings.current.rawValue
                let renderCache = cityRenderCache
                let cities = await Task.detached(priority: .userInitiated) {
                    CityLibraryVM.buildCities(journeys: journeysSnapshot, cachedCities: cachedCitiesSnapshot)
                }.value
                StartupWarmupService.shared.start(
                    cities: cities,
                    appearanceRaw: appearanceRaw,
                    renderCacheStore: renderCache,
                    limit: 16
                )
                lifelogStore.load()
                lifelogStore.bind(to: locationHub)
                lifelogRenderCache.reset()
                lifelogRenderCache.bind(
                    journeyStore: journeyStore,
                    lifelogStore: lifelogStore,
                    trackTileStore: trackTileStore
                )
                // Wait for lifelog data to finish loading before building
                // tiles, otherwise the rebuild runs with empty points and
                // overwrites good persisted tiles from the previous session.
                await awaitLifelogLoadThenRebuildTiles()
                lifelogRenderCache.scheduleWarmupRecentDays(
                    countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                )

                Task { @MainActor in
                    if sessionStore.currentAccessToken != nil {
                        let count = try? await JourneyCloudMigrationService.downloadAndMerge(
                            sessionStore: sessionStore,
                            journeyStore: journeyStore,
                            cityCache: cityCache
                        )
                        if let count, count > 0 {
                            scheduleTrackTileRebuild(delay: 0.10, force: true)
                        }
                    }
                }

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
            .onChange(of: sessionStore.activeLocalProfileID) { oldUserID, uid in
                Task {
                    UserScopedProfileStateStore.switchActiveUser(from: oldUserID, to: uid)
                    let paths = StoragePath(userID: uid)
                    await sessionStore.bootstrapFileSystemAsync()
                    await LifelogMigrationService.migrateLegacyLifelogIfNeededAsync(paths: paths)
                    guard sessionStore.activeLocalProfileID == uid else { return }
                    await restoreFromICloudIfNeeded(userID: uid)

                    journeyStore.rebind(paths: paths)
                    journeyStore.load()
                    cityCache.rebind(paths: paths)
                    cityRenderCache.rebind(rootDir: paths.thumbnailsDir)
                    let journeysSnapshot = journeyStore.journeys
                    let cachedCitiesSnapshot = cityCache.cachedCities
                    let appearanceRaw = MapAppearanceSettings.current.rawValue
                    let renderCache = cityRenderCache
                    let cities = await Task.detached(priority: .userInitiated) {
                        CityLibraryVM.buildCities(journeys: journeysSnapshot, cachedCities: cachedCitiesSnapshot)
                    }.value
                    StartupWarmupService.shared.start(
                        cities: cities,
                        appearanceRaw: appearanceRaw,
                        renderCacheStore: renderCache,
                        limit: 16
                    )
                    lifelogStore.rebind(paths: paths)
                    lifelogStore.load()
                    lifelogStore.bind(to: locationHub)
                    trackTileStore.rebind(paths: paths)
                    lifelogRenderCache.reset()
                    lifelogRenderCache.bind(
                        journeyStore: journeyStore,
                        lifelogStore: lifelogStore,
                        trackTileStore: trackTileStore
                    )
                    await awaitLifelogLoadThenRebuildTiles()
                    lifelogRenderCache.scheduleWarmupRecentDays(
                        countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                    )
                    ensurePassiveLocationTrackingIfNeeded()
                    socialStore.switchUser(uid)
                    postcardCenter.switchUser(uid)
                }
            }
            .onChange(of: sessionStore.currentAccessToken) { _, token in
                guard let token, !token.isEmpty else { return }
                Task {
                    let count = try? await JourneyCloudMigrationService.downloadAndMerge(
                        sessionStore: sessionStore,
                        journeyStore: journeyStore,
                        cityCache: cityCache
                    )
                    if let count, count > 0 {
                        scheduleTrackTileRebuild(delay: 0.10, force: false)
                    }
                }
            }
            .onChange(of: scenePhase) { phase in
                // Best-effort: reduce data loss when the app is backgrounded or suspended.
                if phase == .background || phase == .inactive {
                    journeyStore.flushPersist()
                    lifelogStore.flushPersistNow()
                    Task {
                        await uploadSnapshotToICloud(
                            userID: sessionStore.activeLocalProfileID,
                            reason: "scene_\(phase == .background ? "background" : "inactive")"
                        )
                    }
                }
                if phase == .active {
                    ensurePassiveLocationTrackingIfNeeded()
                    scheduleTrackTileRebuild(delay: 0.10, force: false)
                }
            }
            .onChange(of: journeyStore.trackTileRevision) { _, _ in
                scheduleTrackTileRebuild(delay: 1.5, force: false)
                lifelogRenderCache.scheduleWarmupRecentDays(
                    countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                )
            }
            .onChange(of: lifelogStore.trackTileRevision) { _, _ in
                scheduleTrackTileRebuild(delay: 1.5, force: false)
                lifelogRenderCache.markTodayDirty(
                    countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                )
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
            .onChange(of: trackTileStore.refreshRevision) { _, _ in
                lifelogRenderCache.noteTrackTileRefresh(
                    countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                )
            }
            .onChange(of: lifelogStore.countryISO2) { _, _ in
                lifelogRenderCache.scheduleWarmupRecentDays(
                    countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                )
            }
            .onChange(of: locationHub.countryISO2) { _, _ in
                lifelogRenderCache.scheduleWarmupRecentDays(
                    countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .lifelogCountryAttributionDidChange)) { notification in
                let countryISO2 = notification.userInfo?["countryISO2"] as? String
                lifelogRenderCache.noteCountryAttributionRefresh(countryISO2: countryISO2)
            }
    }

    private var appContent: some View {
        appContentWithLifecycleHandlers
            .onOpenURL { url in
                guard deepLinkStore.handleIncomingURL(url) else { return }
                if deepLinkStore.pendingPasswordResetToken != nil {
                    showAuthEntry = true
                } else {
                    flow.requestSelectTab(.friends)
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                guard deepLinkStore.handleIncomingURL(url) else { return }
                if deepLinkStore.pendingPasswordResetToken != nil {
                    showAuthEntry = true
                } else {
                    flow.requestSelectTab(.friends)
                }
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

    private func awaitLifelogLoadThenRebuildTiles() async {
        // Suspend cooperatively until lifelogStore finishes its async load,
        // with a 3-second safety timeout.  Uses Combine's AsyncPublisher
        // instead of polling so the main thread stays free for animations.
        if !lifelogStore.hasLoaded {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await loaded in self.lifelogStore.$hasLoaded.values {
                        if loaded { return }
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
                await group.next()
                group.cancelAll()
            }
        }
        await rebuildTrackTilesAsync()
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

    private func rebuildTrackTilesAsync(zoom: Int = TrackRenderAdapter.unifiedRenderZoom) async {
        rebuildTrackTiles(zoom: zoom)
        await trackTileRebuildTask?.value
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
