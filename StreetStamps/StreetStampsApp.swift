import Combine
import SwiftUI
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif

struct JourneyDeletionSyncFailure: Equatable {
    let journeyID: String
    let message: String
}

@MainActor
final class JourneyDeletionSyncFailureStore {
    private var failuresByJourneyID: [String: JourneyDeletionSyncFailure] = [:]

    func failure(for journeyID: String) -> JourneyDeletionSyncFailure? {
        failuresByJourneyID[journeyID]
    }

    func clear(journeyID: String) {
        failuresByJourneyID.removeValue(forKey: journeyID)
    }

    func record(journeyID: String, error: Error) {
        failuresByJourneyID[journeyID] = JourneyDeletionSyncFailure(
            journeyID: journeyID,
            message: String(describing: error)
        )
    }
}

enum JourneyDeletionSyncRunner {
    @MainActor
    static func run(
        journeyID: String,
        failureStore: JourneyDeletionSyncFailureStore,
        cloudDeletion: @escaping () async -> Void,
        migrationDeletion: @escaping () async throws -> Void
    ) async {
        failureStore.clear(journeyID: journeyID)
        await cloudDeletion()

        do {
            try await migrationDeletion()
            failureStore.clear(journeyID: journeyID)
        } catch {
            failureStore.record(journeyID: journeyID, error: error)
        }
    }
}

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
    @StateObject private var publishStore = JourneyPublishStore()
    @StateObject private var notificationStore = SocialNotificationStore()
    @State private var journeyDeletionSyncFailureStore = JourneyDeletionSyncFailureStore()
    @State private var showAuthEntry = false
    @State private var showSplash = true
    @State private var scheduledTileRebuild: DispatchWorkItem?
    @State private var trackTileRebuildTask: Task<Void, Never>?
    @State private var trackTileDirty: Bool = false
    @State private var profileSwitchTask: Task<Void, Never>?
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

    private func syncMotionActivityPolicy() {
        MotionActivityHub.shared.setShouldRun(
            MotionActivityPolicy.shouldRun(
                isTrackingJourney: TrackingService.shared.isTracking,
                isPassiveLifelogEnabled: lifelogStore.isEnabled,
                authorizationStatus: locationHub.authorizationStatus
            )
        )
    }

    private func syncPendingCloudChanges(userID: String, reason: String) async {
        await CloudKitSyncService.shared.syncCurrentState(
            userID: userID,
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
            reason: reason
        )
    }

    private static func makeJourneySyncHooks(
        sessionStore: UserSessionStore,
        cityCache: CityCache,
        failureStore: JourneyDeletionSyncFailureStore
    ) -> JourneyStore.SyncHooks {
        JourneyStore.SyncHooks(
            upsertCompletedJourney: { route in
                Task {
                    let localUserID = await MainActor.run { sessionStore.activeLocalProfileID }
                    await CloudKitSyncService.shared.syncJourneyUpsert(route, localUserID: localUserID)
                }
            },
            deleteJourney: { journeyID in
                Task {
                    await JourneyDeletionSyncRunner.run(
                        journeyID: journeyID,
                        failureStore: failureStore,
                        cloudDeletion: {
                            await CloudKitSyncService.shared.syncJourneyDeletion(id: journeyID)
                        },
                        migrationDeletion: {
                            try await JourneyCloudMigrationService.syncDeletedJourney(
                                journeyID: journeyID,
                                sessionStore: sessionStore,
                                cityCache: cityCache
                            )
                        }
                    )
                }
            }
        )
    }

    @MainActor
    private func setupAutoEndHandler() {
        let store = journeyStore
        let cache = cityCache
        let lStore = lifelogStore
        TrackingService.shared.onAutoEnd = { [weak store, weak cache, weak lStore] in
            Task { @MainActor in
                guard let store, let cache, let lStore else { return }
                guard let ongoing = store.latestOngoing ?? store.journeys.first(where: { $0.endTime == nil }) else { return }
                var ended = ongoing
                ended.endTime = Date()
                ended.isTooShort = true // treat as private/stationary trip
                JourneyFinalizer.finalize(
                    route: ended,
                    journeyStore: store,
                    cityCache: cache,
                    lifelogStore: lStore,
                    source: .resumeDeclined
                ) { updated in
                    TrackingService.shared.setAutoEndedNotice(TrackingService.AutoEndedJourneyNotice(
                        journeyID: updated.id,
                        endedAt: updated.endTime ?? Date()
                    ))
                }
            }
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
        #if DEBUG
        UserDefaults.standard.set(true, forKey: "streetstamps.debug.lifelog.mapDiagnosticsEnabled")
        #endif
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
        let cCache = CityCache(paths: paths, journeyStore: jStore)
        let failureStore = JourneyDeletionSyncFailureStore()
        _journeyDeletionSyncFailureStore = State(initialValue: failureStore)
        jStore.syncHooks = Self.makeJourneySyncHooks(sessionStore: session, cityCache: cCache, failureStore: failureStore)
        _journeyStore = StateObject(wrappedValue: jStore)
        _cityCache = StateObject(wrappedValue: cCache)
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
            .environmentObject(publishStore)
            .environmentObject(notificationStore)
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

    private var appContentWithStartupTasks: some View {
        appContentWithPresentation
            .task {
                guard showSplash else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    hideSplash()
                }
            }
            .task {
                await FeatureFlagStore.shared.fetchFlags()
            }
            .task {
                BackendAPIClient.shared.bindSessionStore(sessionStore)
                let startupUserID = sessionStore.activeLocalProfileID
                await sessionStore.bootstrapFileSystemAsync()

                // Phase 1: All independent loads in parallel.
                // bootstrapFS must finish first (ensures dirs exist), then
                // everything else can run concurrently.
                async let journeyLoad: () = journeyStore.loadAsync()
                async let lifelogMigrationThenLoad: () = {
                    await LifelogMigrationService.migrateLegacyLifelogIfNeededAsync(
                        paths: StoragePath(userID: startupUserID)
                    )
                    await lifelogStore.loadAsync()
                }()
                // CityCache load runs on main thread but executes during
                // await suspension gaps of the parallel loads above, so it
                // does not add serial time.
                cityCache.loadInitialData()

                await journeyLoad
                if !journeyStore.journeys.contains(where: { $0.endTime == nil }) {
                    LiveActivityManager.shared.endAllStaleActivities()
                }
                setupAutoEndHandler()
                await lifelogMigrationThenLoad

                // Phase 2: Bind and reduced warmup (4 cities now, rest deferred)
                lifelogStore.bind(to: locationHub)
                lifelogRenderCache.reset()
                lifelogRenderCache.bind(
                    journeyStore: journeyStore,
                    lifelogStore: lifelogStore,
                    trackTileStore: trackTileStore,
                    cachesDir: StoragePath(userID: startupUserID).cachesDir
                )
                let journeysSnapshot = journeyStore.journeys
                let cachedCitiesSnapshot = cityCache.cachedCities
                let appearanceRaw = MapAppearanceSettings.current.rawValue
                let renderCache = cityRenderCache
                let cities = await withTaskGroup(of: [City].self) { group in
                    group.addTask(priority: .userInitiated) {
                        CityLibraryVM.buildCities(journeys: journeysSnapshot, cachedCities: cachedCitiesSnapshot)
                    }
                    return await group.first { _ in true } ?? []
                }
                StartupWarmupService.shared.start(
                    cities: cities,
                    appearanceRaw: appearanceRaw,
                    renderCacheStore: renderCache,
                    limit: 4
                )
                lifelogRenderCache.scheduleWarmupRecentDays(
                    countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                )

                // Track tile rebuild is deferred — triggered lazily by
                // onChange(trackTileRevision) + onChange(currentTab) when
                // user navigates to the lifelog tab.

                // Phase 3: Deferred non-critical services
                Task { @MainActor in
                    await Task.yield()
                    VoiceBroadcastService.shared.start()
                    onboardingGuide.startIfNeeded()
                    maybeShowFirstAuthPromptIfNeeded()
                    await sessionStore.syncHasEmailPasswordIfNeeded()
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    applyIdleLocationPolicy(requestSingleRefreshWhenIdle: true)
                    syncMotionActivityPolicy()
                }

                // Phase 4: Deferred remaining city warmup
                Task(priority: .utility) { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    let js = journeyStore.journeys
                    let cc = cityCache.cachedCities
                    let ar = MapAppearanceSettings.current.rawValue
                    let rc = cityRenderCache
                    let c = await withTaskGroup(of: [City].self) { group in
                        group.addTask(priority: .utility) {
                            CityLibraryVM.buildCities(journeys: js, cachedCities: cc)
                        }
                        return await group.first { _ in true } ?? []
                    }
                    StartupWarmupService.shared.start(
                        cities: c, appearanceRaw: ar, renderCacheStore: rc, limit: 16
                    )
                }
            }
    }

    private var appContentWithSessionHandlers: some View {
        appContentWithStartupTasks
            .onChange(of: hasSeenIntroSlides) { _, seen in
                guard seen else { return }
                maybeShowFirstAuthPromptIfNeeded()
            }
            .onChange(of: sessionStore.activeLocalProfileID) { oldUserID, uid in
                profileSwitchTask?.cancel()
                profileSwitchTask = Task {
                    UserScopedProfileStateStore.switchActiveUser(from: oldUserID, to: uid)
                    CityLevelPreferenceStore.shared.setCurrentUserID(uid)
                    CityLevelPreferenceStore.shared.clearAll()
                    let paths = StoragePath(userID: uid)
                    await sessionStore.bootstrapFileSystemAsync()
                    await LifelogMigrationService.migrateLegacyLifelogIfNeededAsync(paths: paths)
                    guard !Task.isCancelled, sessionStore.activeLocalProfileID == uid else { return }

                    journeyStore.rebind(paths: paths)
                    cityCache.rebind(paths: paths)
                    journeyStore.syncHooks = Self.makeJourneySyncHooks(
                        sessionStore: sessionStore,
                        cityCache: cityCache,
                        failureStore: journeyDeletionSyncFailureStore
                    )
                    lifelogStore.rebind(paths: paths)
                    cityRenderCache.rebind(rootDir: paths.thumbnailsDir)
                    trackTileStore.rebind(paths: paths)

                    // Load journey and lifelog in parallel
                    async let journeyLoad: () = journeyStore.loadAsync()
                    async let lifelogLoad: () = lifelogStore.loadAsync()
                    _ = await (journeyLoad, lifelogLoad)
                    guard !Task.isCancelled else { return }

                    lifelogStore.bind(to: locationHub)
                    lifelogRenderCache.reset()
                    lifelogRenderCache.bind(
                        journeyStore: journeyStore,
                        lifelogStore: lifelogStore,
                        trackTileStore: trackTileStore
                    )
                    let journeysSnapshot = journeyStore.journeys
                    let cachedCitiesSnapshot = cityCache.cachedCities
                    let appearanceRaw = MapAppearanceSettings.current.rawValue
                    let renderCache = cityRenderCache
                    let cities = await withTaskGroup(of: [City].self) { group in
                        group.addTask(priority: .userInitiated) {
                            CityLibraryVM.buildCities(journeys: journeysSnapshot, cachedCities: cachedCitiesSnapshot)
                        }
                        return await group.first { _ in true } ?? []
                    }
                    guard !Task.isCancelled else { return }
                    StartupWarmupService.shared.start(
                        cities: cities,
                        appearanceRaw: appearanceRaw,
                        renderCacheStore: renderCache,
                        limit: 4
                    )
                    lifelogRenderCache.scheduleWarmupRecentDays(
                        countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                    )

                    // Track tile rebuild deferred — triggered by onChange handlers when needed.

                    applyIdleLocationPolicy(requestSingleRefreshWhenIdle: true)
                    syncMotionActivityPolicy()
                    socialStore.switchUser(uid)
                    postcardCenter.switchUser(uid)

                    // Deferred: remaining city warmup (stays in structured task for cancellation)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    let deferredJS = journeyStore.journeys
                    let deferredCC = cityCache.cachedCities
                    let deferredAR = MapAppearanceSettings.current.rawValue
                    let deferredRC = cityRenderCache
                    let deferredCities = await withTaskGroup(of: [City].self) { group in
                        group.addTask(priority: .utility) {
                            CityLibraryVM.buildCities(journeys: deferredJS, cachedCities: deferredCC)
                        }
                        return await group.first { _ in true } ?? []
                    }
                    guard !Task.isCancelled else { return }
                    StartupWarmupService.shared.start(
                        cities: deferredCities, appearanceRaw: deferredAR, renderCacheStore: deferredRC, limit: 16
                    )
                }
            }
            .onChange(of: sessionStore.reauthenticationPromptVersion) { _, version in
                guard version > 0 else { return }
                showAuthEntry = true
            }
    }

    private var appContentWithLifecycleHandlers: some View {
        appContentWithSessionHandlers
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
                    syncMotionActivityPolicy()
                    scheduleTrackTileRebuild(delay: 0.10, force: false)
                    if sessionStore.isLoggedIn {
                        AppNotificationDelegate.registerForRemoteNotificationsIfAuthorized()
                        AppNotificationDelegate.uploadPendingPushTokenIfNeeded(
                            accessToken: sessionStore.currentAccessToken
                        )
                    }
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
                if trackTileDirty && TrackTileRebuildPolicy.shouldRebuild(for: tab) {
                    // No delay — with manifest pre-loaded in TrackTileStore.init(),
                    // rebuildTrackTiles() returns instantly when data is unchanged.
                    scheduleTrackTileRebuild(delay: 0, force: true)
                }
            }
            .onChange(of: lifelogBackgroundModeRaw) { _, _ in
                applyIdleLocationPolicy(requestSingleRefreshWhenIdle: false)
                syncMotionActivityPolicy()
            }
            .onChange(of: lifelogStore.isEnabled) { _, _ in
                applyIdleLocationPolicy(requestSingleRefreshWhenIdle: false)
                syncMotionActivityPolicy()
            }
            .onChange(of: locationHub.authorizationStatus) { _, _ in
                guard lifelogStore.isEnabled else { return }
                applyIdleLocationPolicy(requestSingleRefreshWhenIdle: false)
                syncMotionActivityPolicy()
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
            trackTileDirty = true
            return
        }
        trackTileDirty = false
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
            // Manifest matches — no rebuild needed. But tile data may not
            // be in memory yet (manifest was pre-loaded in init, tiles are
            // lazy). Ensure they're loaded so tiles() returns data.
            trackTileStore.ensureTilesLoaded(zoom: zoom)
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
