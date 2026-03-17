import Combine
import SwiftUI
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif

enum FirstProfileSetupPresentation {
    static func shouldPresent(
        requiresProfileSetup: Bool,
        debugOverrideEnabled: Bool
    ) -> Bool {
        requiresProfileSetup || debugOverrideEnabled
    }
}

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
    @StateObject private var flow = AppFlowCoordinator.shared
    @StateObject private var deepLinkStore = AppDeepLinkStore()
    @StateObject private var onboardingGuide = OnboardingGuideStore()
    @State private var showAuthEntry = false
    @State private var showSplash = true
    @State private var scheduledTileRebuild: DispatchWorkItem?
    @State private var trackTileRebuildTask: Task<Void, Never>?
#if DEBUG
    @State private var showDebugFirstProfileSetupPreview = true
#endif

    private var debugFirstProfileSetupOverrideEnabled: Bool {
#if DEBUG
        return showDebugFirstProfileSetupPreview
#else
        return false
#endif
    }

    @ViewBuilder
    private var firstProfileSetupScreen: some View {
#if DEBUG
        FirstProfileSetupView(
            isDebugPreview: showDebugFirstProfileSetupPreview && !sessionStore.requiresProfileSetup,
            onDismissDebugPreview: {
                showDebugFirstProfileSetupPreview = false
            }
        )
#else
        FirstProfileSetupView()
#endif
    }

    private var lifelogBackgroundMode: LifelogBackgroundMode {
        LifelogBackgroundMode(rawValue: lifelogBackgroundModeRaw) ?? .defaultMode
    }

    private func applyIdleLocationPolicy(requestSingleRefreshWhenIdle: Bool) {
        guard !TrackingService.shared.isTracking else { return }

        let action = LocationLifecycleDecision.idleActivationAction(
            isTrackingJourney: false,
            isPassiveEnabled: lifelogStore.isEnabled,
            authorizationStatus: locationHub.authorizationStatus
        )

        switch action {
        case .startPassive:
            locationHub.startPassiveLifelog(mode: lifelogBackgroundMode)
        case .requestSingleRefresh:
            locationHub.stop()
            if requestSingleRefreshWhenIdle {
                locationHub.requestSingleRefresh()
            }
        case .stayIdle:
            locationHub.stop()
        }
    }

    private func syncPendingCloudChanges(userID: String, reason: String) async {
        await CloudKitSyncService.shared.syncCurrentState(
            userID: userID,
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
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
        jStore.syncHooks = JourneyStore.SyncHooks(
            upsertCompletedJourney: { route in
                Task {
                    await CloudKitSyncService.shared.syncJourneyUpsert(route)
                }
            },
            deleteJourney: { journeyID in
                Task {
                    await CloudKitSyncService.shared.syncJourneyDeletion(id: journeyID)
                }
            }
        )
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
            .fullScreenCover(
                isPresented: Binding(
                    get: {
                        FirstProfileSetupPresentation.shouldPresent(
                            requiresProfileSetup: sessionStore.requiresProfileSetup,
                            debugOverrideEnabled: debugFirstProfileSetupOverrideEnabled
                        )
                    },
                    set: { presented in
#if DEBUG
                        if !presented {
                            showDebugFirstProfileSetupPreview = false
                        }
#endif
                    }
                )
            ) {
                firstProfileSetupScreen
                    .environmentObject(sessionStore)
            }
    }

    private var appContentWithLifecycleHandlers: some View {
        appContentWithPresentation
            .task {
                guard showSplash else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
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
                await journeyStore.loadAsync()
                await lifelogStore.loadAsync()
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
                    await Task.yield()
                    VoiceBroadcastService.shared.start()
                    onboardingGuide.startIfNeeded()
                    maybeShowFirstAuthPromptIfNeeded()
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    applyIdleLocationPolicy(requestSingleRefreshWhenIdle: true)
                }
            }
            .onChange(of: hasSeenIntroSlides) { _, seen in
                guard seen else { return }
                maybeShowFirstAuthPromptIfNeeded()
            }
            .onChange(of: sessionStore.activeLocalProfileID) { oldUserID, uid in
                Task {
                    UserScopedProfileStateStore.switchActiveUser(from: oldUserID, to: uid)
                    CityLevelPreferenceStore.shared.setCurrentUserID(uid)
                    let paths = StoragePath(userID: uid)
                    await sessionStore.bootstrapFileSystemAsync()
                    await LifelogMigrationService.migrateLegacyLifelogIfNeededAsync(paths: paths)
                    guard sessionStore.activeLocalProfileID == uid else { return }

                    journeyStore.rebind(paths: paths)
                    journeyStore.syncHooks = JourneyStore.SyncHooks(
                        upsertCompletedJourney: { route in
                            Task {
                                await CloudKitSyncService.shared.syncJourneyUpsert(route)
                            }
                        },
                        deleteJourney: { journeyID in
                            Task {
                                await CloudKitSyncService.shared.syncJourneyDeletion(id: journeyID)
                            }
                        }
                    )
                    await journeyStore.loadAsync()
                    lifelogStore.rebind(paths: paths)
                    await lifelogStore.loadAsync()
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
                    applyIdleLocationPolicy(requestSingleRefreshWhenIdle: true)
                    socialStore.switchUser(uid)
                    postcardCenter.switchUser(uid)
                }
            }
            .onChange(of: sessionStore.reauthenticationPromptVersion) { _, version in
                guard version > 0 else { return }
                showAuthEntry = true
            }
            .onChange(of: scenePhase) { phase in
                // Best-effort: reduce data loss when the app is backgrounded or suspended.
                if phase == .background || phase == .inactive {
                    journeyStore.flushPersist()
                    lifelogStore.flushPersistNow()
                    Task {
                        await syncPendingCloudChanges(
                            userID: sessionStore.accountUserID ?? sessionStore.activeLocalProfileID,
                            reason: "scene_\(phase == .background ? "background" : "inactive")"
                        )
                    }
                }
                if phase == .active {
                    applyIdleLocationPolicy(requestSingleRefreshWhenIdle: true)
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
                applyIdleLocationPolicy(requestSingleRefreshWhenIdle: false)
            }
            .onChange(of: lifelogStore.isEnabled) { _, _ in
                applyIdleLocationPolicy(requestSingleRefreshWhenIdle: false)
            }
            .onChange(of: locationHub.authorizationStatus) { _, _ in
                guard lifelogStore.isEnabled else { return }
                applyIdleLocationPolicy(requestSingleRefreshWhenIdle: false)
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
                handleIncomingAppURL(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                handleIncomingAppURL(url)
            }
            .preferredColorScheme(.light)
    }

    private func handleIncomingAppURL(_ url: URL) {
        if let postcardIntent = AppDeepLinkStore.parsePostcardInbox(from: url) {
            flow.requestOpenPostcardSidebar(postcardIntent)
            return
        }

        guard deepLinkStore.handleIncomingURL(url) else { return }
        if deepLinkStore.pendingPasswordResetToken != nil {
            showAuthEntry = true
        } else {
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
