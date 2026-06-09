import Combine
import SwiftUI
import UIKit
import UserNotifications
import RevenueCat
#if canImport(FirebaseCore)
import FirebaseCore
#endif

struct JourneyDeletionSyncFailure: Equatable {
    let journeyID: String
    let message: String
}

struct PendingUpdatePrompt: Identifiable {
    let id = UUID()
    let latestVersion: String
    let releaseNotes: String?
    let appStoreURL: URL
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
    static func shouldPresent(requiresProfileSetup: Bool) -> Bool {
        requiresProfileSetup
    }
}

@main
struct StreetStampsApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("streetstamps.intro_slides_shown.v1") private var hasSeenIntroSlides = false
    @AppStorage(AppSettings.dailyTrackingPrecisionKey) private var dailyTrackingPrecisionRaw = DailyTrackingPrecision.defaultPrecision.rawValue
    @StateObject private var locationHub = LocationHub.shared
    @StateObject private var sessionStore: UserSessionStore
    @StateObject private var journeyStore: JourneyStore
    @StateObject private var cityCache: CityCache
    @StateObject private var cityRenderCache: CityRenderCacheStore
    @StateObject private var lifelogStore: LifelogStore
    @StateObject private var trackTileStore: TrackTileStore
    @StateObject private var renderMaskStore: RenderMaskStore
    @StateObject private var lifelogRenderCache: LifelogRenderCacheCoordinator
    @StateObject private var socialStore: SocialGraphStore
    @StateObject private var postcardCenter: PostcardCenter
    @StateObject private var journeyCommentStore: JourneyCommentStore
    @StateObject private var flow = AppFlowCoordinator.shared
    @StateObject private var deepLinkStore = AppDeepLinkStore()
    @StateObject private var onboardingGuide = OnboardingGuideStore()
    @StateObject private var publishStore = JourneyPublishStore()
    @StateObject private var notificationStore = SocialNotificationStore()
    @StateObject private var blockStore = UserBlockStore()
    @StateObject private var languagePreference = LanguagePreference.shared
    @State private var journeyDeletionSyncFailureStore = JourneyDeletionSyncFailureStore()
    @State private var showAuthEntry = false
    @State private var showSplash = true
    @State private var scheduledTileRebuild: DispatchWorkItem?
    @State private var trackTileRebuildTask: Task<Void, Never>?
    @State private var trackTileDirty: Bool = false
    @State private var profileSwitchTask: Task<Void, Never>?
    @State private var pendingUpdatePrompt: PendingUpdatePrompt?
    @State private var pendingCommentDeepLink: JourneyCommentDeepLink?

    @ViewBuilder
    private var firstProfileSetupScreen: some View {
        FirstProfileSetupView()
    }

    private var dailyTrackingPrecision: DailyTrackingPrecision {
        DailyTrackingPrecision(rawValue: dailyTrackingPrecisionRaw) ?? .defaultPrecision
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
            locationHub.startPassiveLifelog()
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

    private func retryStalledJourneyUploads() async {
        guard AppSettings.isICloudSyncEnabled else { return }
        let localUserID = sessionStore.activeLocalProfileID
        let pendingIDs = AppSettings.pendingJourneyUploadIDs(for: localUserID)
        guard !pendingIDs.isEmpty else { return }

        let allJourneys = await MainActor.run { journeyStore.journeys }
        let toRetry = allJourneys.filter { pendingIDs.contains($0.id) }

        // Journeys in pending but no longer in the store were deleted — clean up.
        let existingIDs = Set(toRetry.map(\.id))
        let ghostIDs = Array(pendingIDs.subtracting(existingIDs))
        if !ghostIDs.isEmpty {
            AppSettings.clearJourneyPendingUploads(ghostIDs, for: localUserID)
        }

        guard !toRetry.isEmpty else { return }
        await CloudKitSyncService.shared.retryJourneyUploads(toRetry, localUserID: localUserID)
    }

    private func retryStalledJourneyDeletions() async {
        guard AppSettings.isICloudSyncEnabled else { return }
        let localUserID = sessionStore.activeLocalProfileID
        let pendingIDs = AppSettings.pendingJourneyDeletionIDs(for: localUserID)
        guard !pendingIDs.isEmpty else { return }
        await CloudKitSyncService.shared.retryJourneyDeletions(Array(pendingIDs), localUserID: localUserID)
    }

    private func syncPendingCloudChanges(userID: String, reason: String) async {
        await CloudKitSyncService.shared.syncCurrentState(
            userID: userID,
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
            reason: reason
        )
    }

    private func performICloudAutoEnableForceFullUpload() async {
        // If iCloud is currently unavailable, the persistent flag keeps the intent
        // alive so the next scenePhase == .active triggers a retry automatically.
        let available = await CloudKitSyncService.shared.isAvailable()
        guard available else {
            print("☁️ iCloud unavailable at auto-enable time; will retry on next activation")
            return
        }

        // Clear the retry flag before the upload attempt.  If the attempt is
        // interrupted mid-way, failed lifelog day batches remain dirty via the
        // persistent pendingCloudUploadDayKeys tracker and are retried on the
        // next incremental sync.
        AppSettings.clearPendingFullSyncAfterAutoEnable()

        // Extend background execution budget so a backgrounded upload gets ~30s
        // of grace before the OS suspends the process.
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "icloud_auto_enable_upload") {
            // Expiry handler: OS is about to suspend — nothing to clean up here
            // since the persistent dirty tracker will resume on next launch.
        }
        defer { UIApplication.shared.endBackgroundTask(bgTask) }

        journeyStore.flushPersist()
        lifelogStore.flushPersistNow()
        let localUserID = sessionStore.activeLocalProfileID
        let accountID = sessionStore.accountUserID ?? localUserID
        await CloudKitSyncService.shared.syncCurrentState(
            userID: accountID,
            localUserID: localUserID,
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
            reason: "membership_auto_enable",
            forceFullJourneyUpload: true,
            forceFullLifelogUpload: true
        )
    }

    // Journeys whose local visibility is friends-only/public but whose backend
    // publish never confirmed (sharedAt == nil) are recovery candidates after
    // an app kill mid-upload. Restore the most recent one as a .failed banner
    // so the user can decide (Retry or Save Private); demote the rest to
    // .private so their UI no longer claims friends-visible.
    @MainActor
    private func recoverUnconfirmedJourneyPublishes() {
        let pending = journeyStore.journeys
            .filter { $0.visibility != .private && $0.sharedAt == nil && $0.endTime != nil }
            .sorted { ($0.endTime ?? .distantPast) > ($1.endTime ?? .distantPast) }
        guard let mostRecent = pending.first else { return }
        publishStore.restoreUnconfirmedPublish(
            journey: mostRecent,
            sessionStore: sessionStore,
            cityCache: cityCache,
            journeyStore: journeyStore
        )
        let rest = pending.dropFirst()
        guard !rest.isEmpty else { return }
        var demoted: [JourneyRoute] = []
        for j in rest {
            var updated = j
            updated.visibility = .private
            demoted.append(updated)
        }
        journeyStore.applyBulkCompletedUpdates(demoted)
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
                    let localUserID = await MainActor.run { sessionStore.activeLocalProfileID }
                    await JourneyDeletionSyncRunner.run(
                        journeyID: journeyID,
                        failureStore: failureStore,
                        cloudDeletion: {
                            await CloudKitSyncService.shared.syncJourneyDeletion(id: journeyID, localUserID: localUserID)
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
        // Auto-pause does not finalize the journey — no handler needed.
        // The journey stays alive in paused state until the user resumes or ends manually.
    }

    private func setupBackgroundPersistHandler() {
        let store = journeyStore
        TrackingService.shared.onBackgroundPersistNeeded = { [weak store] in
            store?.flushPersist()
        }
    }

    @MainActor
    private func maybeShowFirstAuthPromptIfNeeded() {
        guard hasSeenIntroSlides, !sessionStore.isLoggedIn else { return }
        // Only prompt when we have positive confirmation that social is enabled
        // for this install. That covers three cases: (1) gated regions like CN
        // where the server says no and we keep the user in guest mode, (2) the
        // offline cold start where `socialEnabled` still sits at the default
        // `true` but no server answer has arrived — login wouldn't work over
        // a dead network anyway, and (3) debug overrides. When flags later
        // confirm, `.onReceive($hasConfirmedSocial)` re-runs this method.
        guard FeatureFlagStore.shared.hasConfirmedSocial else { return }
        guard FeatureFlagStore.shared.socialEnabled else { return }

        let firstPromptKey = "streetstamps.auth_entry_shown.v1"
        let isFirstLaunchPrompt = !UserDefaults.standard.bool(forKey: firstPromptKey)
        let hasPendingReauthPrompt = sessionStore.hasPendingReauthPrompt

        guard isFirstLaunchPrompt || hasPendingReauthPrompt else { return }

        if isFirstLaunchPrompt {
            UserDefaults.standard.set(true, forKey: firstPromptKey)
        }
        showAuthEntry = true
    }


    init() {
        BackendConfig.resetToDefault()
        #if canImport(FirebaseCore)
        if BackendConfig.firebaseBackupRuntimeEnabled,
           FirebaseApp.app() == nil,
           BackendConfig.firebaseSetupIssue() == nil {
            FirebaseApp.configure()
        }
        #endif

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: "appl_lgQllosipiiEpwoJtfTRpGpWCHC")

        let session = UserSessionStore()
        UserScopedProfileStateStore.initializeCurrentUser(session.activeLocalProfileID)
        _sessionStore = StateObject(wrappedValue: session)

        if let accountID = session.accountUserID, !accountID.isEmpty {
            Task.detached {
                _ = try? await Purchases.shared.logIn(accountID)
            }
        }

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
        _renderMaskStore = StateObject(wrappedValue: RenderMaskStore(paths: paths))
        _lifelogRenderCache = StateObject(wrappedValue: LifelogRenderCacheCoordinator())
        _socialStore = StateObject(wrappedValue: SocialGraphStore(userID: session.activeLocalProfileID))
        _postcardCenter = StateObject(wrappedValue: PostcardCenter(userID: session.activeLocalProfileID))
        // Comments are cloud-only and keyed by backend account ID, not the
        // local profile scope. Initialize with the account ID so thread keys
        // match what the backend computes from the JWT uid.
        _journeyCommentStore = StateObject(wrappedValue: JourneyCommentStore(
            userID: session.accountUserID ?? "",
            backend: RESTJourneyCommentBackend.shared
        ))

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
            .environment(\.locale, languagePreference.displayLocale)
            .environmentObject(locationHub)
            .environmentObject(sessionStore)
            .environmentObject(journeyStore)
            .environmentObject(cityCache)
            .environmentObject(cityRenderCache)
            .environmentObject(lifelogStore)
            .environmentObject(trackTileStore)
            .environmentObject(renderMaskStore)
            .environmentObject(lifelogRenderCache)
            .environmentObject(socialStore)
            .environmentObject(postcardCenter)
            .environmentObject(journeyCommentStore)
            .environmentObject(flow)
            .environmentObject(deepLinkStore)
            .environmentObject(onboardingGuide)
            .environmentObject(publishStore)
            .environmentObject(notificationStore)
            .environmentObject(blockStore)
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
            .alert(
                L10n.t("settings_check_updates_available_title"),
                isPresented: Binding(
                    get: { pendingUpdatePrompt != nil },
                    set: { if !$0 { pendingUpdatePrompt = nil } }
                ),
                presenting: pendingUpdatePrompt
            ) { prompt in
                Button(L10n.t("settings_check_updates_action_update")) {
                    UIApplication.shared.open(prompt.appStoreURL)
                    pendingUpdatePrompt = nil
                }
                Button(L10n.t("settings_check_updates_action_later"), role: .cancel) {
                    pendingUpdatePrompt = nil
                }
                Button(L10n.t("settings_check_updates_action_skip"), role: .destructive) {
                    AppUpdateChecker.skipVersion(prompt.latestVersion)
                    pendingUpdatePrompt = nil
                }
            } message: { prompt in
                if let notes = prompt.releaseNotes, !notes.isEmpty {
                    Text(String(format: L10n.t("settings_check_updates_available_message_with_notes"), prompt.latestVersion, notes))
                } else {
                    Text(String(format: L10n.t("settings_check_updates_available_message"), prompt.latestVersion))
                }
            }
            .fullScreenCover(isPresented: $showAuthEntry) {
                AuthEntryView(
                    onContinueGuest: {
                        sessionStore.clearPendingReauthPrompt()
                        showAuthEntry = false
                    },
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
                            requiresProfileSetup: sessionStore.requiresProfileSetup
                        )
                    },
                    set: { _ in }
                )
            ) {
                firstProfileSetupScreen
                    .environmentObject(sessionStore)
            }
            .onChange(of: flow.openJourneyCommentSignal) { _, _ in
                guard let link = flow.pendingJourneyCommentLink else { return }
                pendingCommentDeepLink = link
                flow.consumePendingJourneyCommentLink()
            }
            .fullScreenCover(item: $pendingCommentDeepLink) { link in
                // Host the detail as a PUSHED navigation destination, not as the
                // NavigationStack's root. A `.sheet` presented from the root view
                // of a NavigationStack that is itself the content of a
                // `fullScreenCover` silently fails to present (the comment sheet
                // never appeared and the comment button looked dead). The same
                // view works fine when it is a pushed destination — which is how
                // the normal in-app path (CollectionTabView) presents it. Mirrors
                // the proven `ModalNavigationWrapper` pattern in MainTabView.
                JourneyCommentDeepLinkCover(
                    link: link,
                    onDismiss: { pendingCommentDeepLink = nil }
                ) { routedLink in
                    journeyCommentDeepLinkView(for: routedLink)
                }
                .environmentObject(sessionStore)
                .environmentObject(journeyStore)
                .environmentObject(cityCache)
                .environmentObject(cityRenderCache)
                .environmentObject(locationHub)
                .environmentObject(flow)
                .environmentObject(socialStore)
                .environmentObject(journeyCommentStore)
                .environmentObject(publishStore)
                .environmentObject(onboardingGuide)
            }
    }

    @ViewBuilder
    private func journeyCommentDeepLinkView(for link: JourneyCommentDeepLink) -> some View {
        // Comments are keyed by backend account ID, not the local profile scope.
        // `link.ownerID` is the account ID from the push payload, so it must be
        // compared against `accountUserID` (not `currentUserID`, which resolves
        // to `activeLocalProfileID` = `local_<guestID>` and never matches an
        // account ID — that mismatch routed every own-journey comment tap into
        // the friend branch and onto the "content unavailable" screen).
        if link.ownerID == sessionStore.accountUserID {
            OwnerCommentDeepLinkContent(link: link)
        } else {
            FriendCommentDeepLinkContent(
                link: link,
                initialSnapshot: socialStore.friends.first(where: { $0.id == link.ownerID })
            )
        }
    }

    /// Hosts the journey-comment deep-link detail as a PUSHED navigation
    /// destination (not the NavigationStack root) so the detail's `.sheet`s —
    /// most importantly the comment sheet — present reliably. Initializing
    /// `path` with the link renders the detail on the first frame; popping back
    /// to root (the detail's back button / swipe) auto-dismisses the enclosing
    /// `fullScreenCover`. Mirrors `MainTabView.ModalNavigationWrapper`.
    private struct JourneyCommentDeepLinkCover<Content: View>: View {
        let link: JourneyCommentDeepLink
        let onDismiss: () -> Void
        @ViewBuilder let content: (JourneyCommentDeepLink) -> Content
        @State private var path: [JourneyCommentDeepLink]

        init(
            link: JourneyCommentDeepLink,
            onDismiss: @escaping () -> Void,
            @ViewBuilder content: @escaping (JourneyCommentDeepLink) -> Content
        ) {
            self.link = link
            self.onDismiss = onDismiss
            self.content = content
            _path = State(initialValue: [link])
        }

        var body: some View {
            NavigationStack(path: $path) {
                Color.clear
                    .navigationBarHidden(true)
                    .navigationDestination(for: JourneyCommentDeepLink.self) { routedLink in
                        content(routedLink)
                    }
            }
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty { onDismiss() }
            }
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
                await MembershipStore.shared.refreshEntitlement()
            }
            .task {
                // Populate per-journey unread badges so bubbles in
                // JourneyRouteDetailView show the dot without first opening
                // the sheet. Cheap (single endpoint, returns only buckets).
                await journeyCommentStore.refreshUnreadSummary(
                    token: sessionStore.currentAccessToken
                )
            }
            .task {
                BackendAPIClient.shared.bindSessionStore(sessionStore)
                CoinService.shared.bindSessionStore(sessionStore)
                let startupUserID = sessionStore.activeLocalProfileID
                await sessionStore.bootstrapFileSystemAsync()
                await CoinService.shared.bootstrap()

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
                async let cityCacheLoad: () = cityCache.loadInitialDataAsync()

                await journeyLoad
                let hasOngoing = journeyStore.journeys.contains(where: { $0.endTime == nil })
                LiveActivityManager.shared.adoptOrEndStaleActivities(hasOngoingJourney: hasOngoing)
                setupAutoEndHandler()
                setupBackgroundPersistHandler()
                recoverUnconfirmedJourneyPublishes()
                await lifelogMigrationThenLoad

                // Ensure city cache decode finished before reading cachedCities
                await cityCacheLoad

                // Both journeys and cities are loaded — safe to run identity repair
                cityCache.repairAllCityIdentityData()

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
                let appearanceRaw = MapLayerStyle.current.rawValue
                let renderCache = cityRenderCache
                let cities = await withTaskGroup(of: [City].self) { group in
                    group.addTask(priority: .userInitiated) {
                        CityLibraryVM.buildCities(journeys: journeysSnapshot, cachedCities: cachedCitiesSnapshot)
                    }
                    return await group.first { _ in true } ?? []
                }
                let renderMaskSnapshot = renderMaskStore.snapshot()
                StartupWarmupService.shared.start(
                    cities: cities,
                    appearanceRaw: appearanceRaw,
                    renderCacheStore: renderCache,
                    limit: 4,
                    renderMaskByJourney: renderMaskSnapshot
                )
                // Splash-window warmup, in order:
                //   1. await trackTile rebuild so the manifest is current
                //   2. then start lifelog render warmup — by that point
                //      launchPendingWarmupIfPossible's manifest guard passes,
                //      so the warmup actually runs instead of silently no-oping
                //      and waiting for the onChange(refreshRevision) retry hop.
                // The whole chain runs inside the same .task that owns the
                // startup phases, so it shares the splash window without
                // blocking the splash itself.
                Task { @MainActor in
                    await rebuildTrackTilesAsync()
                    lifelogRenderCache.scheduleWarmupRecentDays(
                        countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                    )
                }

                // Phase 3: Deferred non-critical services. The auth prompt check
                // is a no-op if feature flags haven't resolved yet; the
                // .onReceive($hasFetched) handler re-runs it once they do.
                Task { @MainActor in
                    await Task.yield()
                    VoiceBroadcastService.shared.start()
                    onboardingGuide.markExistingUserIfNeeded(hasJourneys: !journeyStore.journeys.isEmpty)
                    onboardingGuide.startIfNeeded()
                    maybeShowFirstAuthPromptIfNeeded()
                    await sessionStore.syncHasEmailPasswordIfNeeded()
                    await blockStore.refresh(accessToken: sessionStore.currentAccessToken)
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    applyIdleLocationPolicy(requestSingleRefreshWhenIdle: true)
                    syncMotionActivityPolicy()
                }

                // Auto check for App Store updates after splash dismisses,
                // throttled to once per 24h, skipped versions suppressed.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if case let .updateAvailable(version, notes, url)? = await AppUpdateChecker.autoCheckIfDue() {
                        pendingUpdatePrompt = PendingUpdatePrompt(
                            latestVersion: version,
                            releaseNotes: notes,
                            appStoreURL: url
                        )
                    }
                }

                // Phase 4: Deferred remaining city warmup
                Task(priority: .utility) { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    let js = journeyStore.journeys
                    let cc = cityCache.cachedCities
                    let ar = MapLayerStyle.current.rawValue
                    let rc = cityRenderCache
                    let c = await withTaskGroup(of: [City].self) { group in
                        group.addTask(priority: .utility) {
                            CityLibraryVM.buildCities(journeys: js, cachedCities: cc)
                        }
                        return await group.first { _ in true } ?? []
                    }
                    let masks = renderMaskStore.snapshot()
                    StartupWarmupService.shared.start(
                        cities: c, appearanceRaw: ar, renderCacheStore: rc, limit: 16, renderMaskByJourney: masks
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
            .onReceive(FeatureFlagStore.shared.$hasConfirmedSocial) { confirmed in
                guard confirmed else { return }
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
                    journeyStore.syncHooks = Self.makeJourneySyncHooks(
                        sessionStore: sessionStore,
                        cityCache: cityCache,
                        failureStore: journeyDeletionSyncFailureStore
                    )
                    lifelogStore.rebind(paths: paths)
                    cityRenderCache.rebind(rootDir: paths.thumbnailsDir)
                    renderMaskStore.rebind(paths: paths)
                    journeyCommentStore.switchUser(sessionStore.accountUserID ?? "")

                    // Load journey, lifelog, city cache, and track tiles in parallel.
                    // All four do heavy disk I/O — running them concurrently avoids
                    // serializing the stall on the main thread during profile switch.
                    async let journeyLoad: () = journeyStore.loadAsync()
                    async let lifelogLoad: () = lifelogStore.loadAsync()
                    async let cityCacheLoad: () = cityCache.rebindAsync(paths: paths)
                    async let trackTileLoad: () = trackTileStore.rebindAsync(paths: paths)
                    _ = await (journeyLoad, lifelogLoad, cityCacheLoad, trackTileLoad)
                    guard !Task.isCancelled else { return }

                    // Profile-switch may leave stale publish state from the previous
                    // profile; clear before scanning the newly-bound journey store.
                    publishStore.dismiss()
                    recoverUnconfirmedJourneyPublishes()

                    onboardingGuide.markExistingUserIfNeeded(hasJourneys: !journeyStore.journeys.isEmpty)
                    lifelogStore.bind(to: locationHub)
                    lifelogRenderCache.reset()
                    lifelogRenderCache.bind(
                        journeyStore: journeyStore,
                        lifelogStore: lifelogStore,
                        trackTileStore: trackTileStore
                    )
                    let journeysSnapshot = journeyStore.journeys
                    let cachedCitiesSnapshot = cityCache.cachedCities
                    let appearanceRaw = MapLayerStyle.current.rawValue
                    let renderCache = cityRenderCache
                    let cities = await withTaskGroup(of: [City].self) { group in
                        group.addTask(priority: .userInitiated) {
                            CityLibraryVM.buildCities(journeys: journeysSnapshot, cachedCities: cachedCitiesSnapshot)
                        }
                        return await group.first { _ in true } ?? []
                    }
                    guard !Task.isCancelled else { return }
                    let renderMaskSnapshot = renderMaskStore.snapshot()
                    StartupWarmupService.shared.start(
                        cities: cities,
                        appearanceRaw: appearanceRaw,
                        renderCacheStore: renderCache,
                        limit: 4,
                        renderMaskByJourney: renderMaskSnapshot
                    )
                    rebuildTrackTiles()
                    lifelogRenderCache.scheduleWarmupRecentDays(
                        countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                    )

                    applyIdleLocationPolicy(requestSingleRefreshWhenIdle: true)
                    syncMotionActivityPolicy()
                    socialStore.switchUser(uid)
                    postcardCenter.switchUser(uid)

                    // Deferred: remaining city warmup (stays in structured task for cancellation)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    let deferredJS = journeyStore.journeys
                    let deferredCC = cityCache.cachedCities
                    let deferredAR = MapLayerStyle.current.rawValue
                    let deferredRC = cityRenderCache
                    let deferredCities = await withTaskGroup(of: [City].self) { group in
                        group.addTask(priority: .utility) {
                            CityLibraryVM.buildCities(journeys: deferredJS, cachedCities: deferredCC)
                        }
                        return await group.first { _ in true } ?? []
                    }
                    guard !Task.isCancelled else { return }
                    let deferredMasks = renderMaskStore.snapshot()
                    StartupWarmupService.shared.start(
                        cities: deferredCities, appearanceRaw: deferredAR, renderCacheStore: deferredRC, limit: 16, renderMaskByJourney: deferredMasks
                    )
                }
            }
            .onChange(of: sessionStore.activeLocalProfileID) { _, _ in
                Task {
                    let accountID = sessionStore.accountUserID
                    if let accountID, !accountID.isEmpty {
                        _ = try? await Purchases.shared.logIn(accountID)
                    } else if !Purchases.shared.isAnonymous {
                        _ = try? await Purchases.shared.logOut()
                        // After logout, the new anonymous appUserId starts
                        // empty. Re-attach the device's Apple ID transactions
                        // so users who go account → guest don't see premium
                        // disappear just because their Worldo account changed.
                        try? await MembershipStore.shared.restorePurchases()
                    }
                    await MembershipStore.shared.refreshEntitlement()
                    await CoinService.shared.bootstrap()
                }
            }
            .onChange(of: sessionStore.accountUserID ?? "") { _, accountID in
                // Sign-in/out can change the account ID without changing
                // activeLocalProfileID, so the profile-switch rebind above
                // doesn't always cover it. Comments are cloud-only and keyed
                // by account ID; rebind here too.
                journeyCommentStore.switchUser(accountID)
            }
            .onChange(of: sessionStore.reauthenticationPromptVersion) { _, version in
                guard version > 0 else { return }
                showAuthEntry = true
            }
            .onChange(of: sessionStore.sessionRefreshVersion) { _, _ in
                if sessionStore.isLoggedIn {
                    AppNotificationDelegate.registerForRemoteNotificationsIfAuthorized()
                    AppNotificationDelegate.uploadPendingPushTokenIfNeeded(
                        accessToken: sessionStore.currentAccessToken
                    )
                    Task { @MainActor in
                        await notificationStore.refresh(token: sessionStore.currentAccessToken)
                    }
                    notificationStore.startPolling { [sessionStore] in
                        sessionStore.currentAccessToken
                    }
                } else {
                    notificationStore.stopPolling()
                }
            }
    }

    private var appContentWithLifecycleHandlers: some View {
        appContentWithSessionHandlers
            .onChange(of: scenePhase) { _, phase in
                // Best-effort: reduce data loss when the app is backgrounded or suspended.
                if phase == .background || phase == .inactive {
                    journeyStore.flushPersist()
                    lifelogStore.flushPersistNow()
                    notificationStore.stopPolling()
                    Task {
                        await syncPendingCloudChanges(
                            userID: sessionStore.accountUserID ?? sessionStore.activeLocalProfileID,
                            reason: "scene_\(phase == .background ? "background" : "inactive")"
                        )
                    }
                }
                if phase == .active {
                    UNUserNotificationCenter.current().setBadgeCount(0)
                    publishStore.handleSceneActivation()
                    Task { await MembershipStore.shared.refreshEntitlement() }
                    // Retry the full post-membership-enable upload if iCloud was
                    // unavailable when the user first subscribed.
                    if AppSettings.hasPendingFullSyncAfterAutoEnable {
                        Task { await performICloudAutoEnableForceFullUpload() }
                    }
                    // Retry individual journeys that failed their incremental upload
                    // (network error, iCloud unavailable, app killed mid-hook).
                    Task { await retryStalledJourneyUploads() }
                    // Same idea for deletions: a stalled delete leaves the CK record
                    // alive and would resurrect the journey on a future restore.
                    Task { await retryStalledJourneyDeletions() }
                    applyIdleLocationPolicy(requestSingleRefreshWhenIdle: true)
                    syncMotionActivityPolicy()
                    lifelogRenderCache.markTodayDirty(
                        countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
                    )
                    scheduleTrackTileRebuild(delay: 0.10, force: false)
                    if sessionStore.isLoggedIn {
                        AppNotificationDelegate.registerForRemoteNotificationsIfAuthorized()
                        AppNotificationDelegate.uploadPendingPushTokenIfNeeded(
                            accessToken: sessionStore.currentAccessToken
                        )
                        Task { @MainActor in
                            await notificationStore.refresh(token: sessionStore.currentAccessToken)
                        }
                        notificationStore.startPolling { [sessionStore] in
                            sessionStore.currentAccessToken
                        }
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
            .onChange(of: dailyTrackingPrecisionRaw) { _, _ in
                // If a daily journey is active, update background mode immediately
                let ts = TrackingService.shared
                if ts.isTracking && ts.trackingMode == .daily {
                    ts.enterLowPowerBackgroundMode()
                }
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
            .onReceive(NotificationCenter.default.publisher(for: .journeyCommentReceivedPush)) { notification in
                let journeyID = notification.userInfo?["journeyID"] as? String
                Task {
                    let token = sessionStore.currentAccessToken
                    // Refresh global summary so the bubble badge updates across
                    // every journey detail screen, not just the one in front.
                    await journeyCommentStore.refreshUnreadSummary(token: token)
                    // If the affected journey is currently being shown, also
                    // refresh its thread list so any open sheet picks up the
                    // new message without a manual pull.
                    if let journeyID, !journeyID.isEmpty {
                        await journeyCommentStore.loadThreads(journeyID: journeyID, token: token)
                    }
                }
            }
            .onReceive(MembershipStore.shared.$pendingICloudAutoEnableNotice) { pending in
                guard pending else { return }
                Task { await performICloudAutoEnableForceFullUpload() }
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
        // Live Activity: 拍照/记忆入口
        if url.scheme == "streetstamps" && url.host == "capture" {
            NotificationCenter.default.post(name: .openCaptureFromWidget, object: nil)
            return
        }

        if let postcardIntent = AppDeepLinkStore.parsePostcardInbox(from: url) {
            guard FeatureFlagStore.shared.socialEnabled else { return }
            flow.requestOpenPostcardSidebar(postcardIntent)
            return
        }

        guard deepLinkStore.handleIncomingURL(url) else { return }
        if deepLinkStore.pendingPasswordResetToken != nil {
            showAuthEntry = true
        } else {
            guard FeatureFlagStore.shared.socialEnabled else { return }
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
            // lazy). Load tiles off the main thread — _loadFromDisk() reads
            // hundreds of JSON files and must NOT block the UI.
            let tStore = trackTileStore
            Task.detached(priority: .utility) {
                tStore.ensureTilesLoaded(zoom: zoom)
            }
            return
        }

        trackTileRebuildTask?.cancel()
        // MUST use Task.detached — a plain Task inherits MainActor isolation
        // from the caller, which would cause storageQueue.sync inside refresh()
        // to block the main thread for seconds.
        let jStore = journeyStore
        let lStore = lifelogStore
        let tStore = trackTileStore
        let jRev = journeyRevision
        let pRev = passiveRevision
        trackTileRebuildTask = Task.detached(priority: .utility) {
            async let journeyEvents = jStore.trackRenderEventsAsync()
            async let passiveEvents = lStore.trackRenderEventsAsync()
            let (resolvedJourneyEvents, resolvedPassiveEvents) = await (journeyEvents, passiveEvents)
            guard !Task.isCancelled else { return }
            do {
                try tStore.refresh(
                    journeyEvents: resolvedJourneyEvents,
                    passiveEvents: resolvedPassiveEvents,
                    journeyRevision: jRev,
                    passiveRevision: pRev,
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
    let parchment = UIColor(FigmaTheme.background)

    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = parchment
    tabAppearance.shadowColor = UIColor.black.withAlphaComponent(0.08)

    UITabBar.appearance().standardAppearance = tabAppearance
    if #available(iOS 15.0, *) {
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    let navAppearance = UINavigationBarAppearance()
    navAppearance.configureWithOpaqueBackground()
    navAppearance.backgroundColor = parchment
    navAppearance.shadowColor = .clear

    UINavigationBar.appearance().standardAppearance = navAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    UINavigationBar.appearance().compactAppearance = navAppearance
}

private extension StreetStampsApp {
    func hideSplash() {
        guard showSplash else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            showSplash = false
        }
    }
}
