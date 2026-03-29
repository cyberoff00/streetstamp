import Combine
import Foundation
import SwiftUI

enum AppAuthPresentationCoordinator {
    private static let firstPromptKey = "streetstamps.auth_entry_shown.v1"

    @discardableResult
    static func consumeInitialAuthEntryPresentation(
        hasSeenIntroSlides: Bool,
        isLoggedIn: Bool,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard hasSeenIntroSlides, !isLoggedIn else { return false }
        guard !defaults.bool(forKey: firstPromptKey) else { return false }
        defaults.set(true, forKey: firstPromptKey)
        return true
    }
}

enum AppJourneySyncCoordinator {
    static func syncPendingCloudChanges(
        userID: String,
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        reason: String
    ) async {
        await CloudKitSyncService.shared.syncCurrentState(
            userID: userID,
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
            reason: reason
        )
    }

    static func makeJourneySyncHooks(
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
    static func performStartupLoad(
        sessionStore: UserSessionStore,
        journeyStore: JourneyStore,
        cityCache: CityCache,
        cityRenderCache: CityRenderCacheStore,
        lifelogStore: LifelogStore,
        trackTileStore: TrackTileStore,
        lifelogRenderCache: LifelogRenderCacheCoordinator,
        onboardingGuide: OnboardingGuideStore,
        locationHub: LocationHub,
        hasSeenIntroSlides: Bool,
        onNeedAuthPrompt: @escaping @MainActor () -> Void,
        applyIdleLocationPolicy: @escaping @MainActor (Bool) -> Void,
        syncMotionActivityPolicy: @escaping @MainActor () -> Void
    ) async {
        BackendAPIClient.shared.bindSessionStore(sessionStore)
        let startupUserID = sessionStore.activeLocalProfileID
        await sessionStore.bootstrapFileSystemAsync()
        await LifelogMigrationService.migrateLegacyLifelogIfNeededAsync(
            paths: StoragePath(userID: startupUserID)
        )

        // Phase 1: Load journey and lifelog data in parallel
        async let journeyLoad: () = journeyStore.loadAsync()
        async let lifelogLoad: () = lifelogStore.loadAsync()
        _ = await (journeyLoad, lifelogLoad)

        // Phase 2: Bind and reduced warmup (4 cities now, rest deferred)
        lifelogStore.bind(to: locationHub)
        lifelogRenderCache.reset()
        lifelogRenderCache.bind(
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
            trackTileStore: trackTileStore
        )
        await warmupCaches(
            journeyStore: journeyStore,
            cityCache: cityCache,
            cityRenderCache: cityRenderCache,
            limit: 4
        )
        lifelogRenderCache.scheduleWarmupRecentDays(
            countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
        )

        // Eagerly kick off track tile rebuild so lifelog data is ready before
        // the user switches to the lifelog tab.  Runs on .utility and does not
        // block the startup path — the city warmup above already returned.
        eagerTrackTileRebuild(
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
            trackTileStore: trackTileStore
        )

        // Phase 3: Deferred non-critical services
        Task { @MainActor in
            await Task.yield()
            VoiceBroadcastService.shared.start()
            onboardingGuide.startIfNeeded()
            if AppAuthPresentationCoordinator.consumeInitialAuthEntryPresentation(
                hasSeenIntroSlides: hasSeenIntroSlides,
                isLoggedIn: sessionStore.isLoggedIn
            ) {
                onNeedAuthPrompt()
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            applyIdleLocationPolicy(true)
            syncMotionActivityPolicy()
        }

        // Phase 4: Deferred remaining city warmup
        Task(priority: .utility) { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await warmupCaches(
                journeyStore: journeyStore,
                cityCache: cityCache,
                cityRenderCache: cityRenderCache,
                limit: 16
            )
        }
    }

    @MainActor
    static func handleActiveLocalProfileChange(
        from oldUserID: String,
        to userID: String,
        sessionStore: UserSessionStore,
        journeyStore: JourneyStore,
        cityCache: CityCache,
        cityRenderCache: CityRenderCacheStore,
        lifelogStore: LifelogStore,
        trackTileStore: TrackTileStore,
        lifelogRenderCache: LifelogRenderCacheCoordinator,
        socialStore: SocialGraphStore,
        postcardCenter: PostcardCenter,
        locationHub: LocationHub,
        failureStore: JourneyDeletionSyncFailureStore,
        applyIdleLocationPolicy: @escaping @MainActor (Bool) -> Void,
        syncMotionActivityPolicy: @escaping @MainActor () -> Void
    ) async {
        UserScopedProfileStateStore.switchActiveUser(from: oldUserID, to: userID)
        CityLevelPreferenceStore.shared.setCurrentUserID(userID)
        let paths = StoragePath(userID: userID)
        await sessionStore.bootstrapFileSystemAsync()
        await LifelogMigrationService.migrateLegacyLifelogIfNeededAsync(paths: paths)
        guard sessionStore.activeLocalProfileID == userID else { return }

        journeyStore.rebind(paths: paths)
        cityCache.rebind(paths: paths)
        journeyStore.syncHooks = makeJourneySyncHooks(
            sessionStore: sessionStore,
            cityCache: cityCache,
            failureStore: failureStore
        )
        lifelogStore.rebind(paths: paths)
        cityRenderCache.rebind(rootDir: paths.thumbnailsDir)
        trackTileStore.rebind(paths: paths)

        // Load journey and lifelog in parallel
        async let journeyLoad: () = journeyStore.loadAsync()
        async let lifelogLoad: () = lifelogStore.loadAsync()
        _ = await (journeyLoad, lifelogLoad)

        lifelogStore.bind(to: locationHub)
        lifelogRenderCache.reset()
        lifelogRenderCache.bind(
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
            trackTileStore: trackTileStore
        )
        await warmupCaches(
            journeyStore: journeyStore,
            cityCache: cityCache,
            cityRenderCache: cityRenderCache,
            limit: 4
        )
        lifelogRenderCache.scheduleWarmupRecentDays(
            countryISO2: lifelogStore.countryISO2 ?? locationHub.countryISO2
        )

        eagerTrackTileRebuild(
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
            trackTileStore: trackTileStore
        )

        applyIdleLocationPolicy(true)
        syncMotionActivityPolicy()
        socialStore.switchUser(userID)
        postcardCenter.switchUser(userID)

        // Deferred: remaining city warmup
        Task(priority: .utility) { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await warmupCaches(
                journeyStore: journeyStore,
                cityCache: cityCache,
                cityRenderCache: cityRenderCache,
                limit: 16
            )
        }
    }

    /// Fire-and-forget track tile rebuild so tiles are ready before the user
    /// opens the lifelog tab.  Runs on `.utility` to avoid competing with
    /// UI-critical startup work.  If manifest already matches, this is a
    /// near-instant no-op (just ensures tile data is in memory).
    @MainActor
    private static func eagerTrackTileRebuild(
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        trackTileStore: TrackTileStore,
        zoom: Int = TrackRenderAdapter.unifiedRenderZoom
    ) {
        let journeyRevision = journeyStore.trackTileRevision
        let passiveRevision = lifelogStore.trackTileRevision
        if let manifest = trackTileStore.currentManifest,
           manifest.zoom == zoom,
           manifest.journeyRevision == journeyRevision,
           manifest.passiveRevision == passiveRevision {
            Task.detached(priority: .utility) {
                trackTileStore.ensureTilesLoaded(zoom: zoom)
            }
            return
        }
        Task.detached(priority: .utility) {
            async let journeyEvents = journeyStore.trackRenderEventsAsync()
            async let passiveEvents = lifelogStore.trackRenderEventsAsync()
            let (je, pe) = await (journeyEvents, passiveEvents)
            try? trackTileStore.refresh(
                journeyEvents: je,
                passiveEvents: pe,
                journeyRevision: journeyRevision,
                passiveRevision: passiveRevision,
                zoom: zoom
            )
        }
    }

    @MainActor
    private static func warmupCaches(
        journeyStore: JourneyStore,
        cityCache: CityCache,
        cityRenderCache: CityRenderCacheStore,
        limit: Int = 16
    ) async {
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
            limit: limit
        )
    }
}

@MainActor
final class TrackTileRebuildCoordinator: ObservableObject {
    private var scheduledTileRebuild: DispatchWorkItem?
    private var trackTileRebuildTask: Task<Void, Never>?
    private var isDirty: Bool = false

    func scheduleRebuild(
        currentTab: NavigationTab,
        delay: TimeInterval = 0.25,
        force: Bool = true,
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        trackTileStore: TrackTileStore
    ) {
        if !force && !TrackTileRebuildPolicy.shouldRebuild(for: currentTab) {
            isDirty = true
            return
        }
        isDirty = false
        scheduledTileRebuild?.cancel()
        let work = DispatchWorkItem {
            self.rebuildTrackTiles(
                journeyStore: journeyStore,
                lifelogStore: lifelogStore,
                trackTileStore: trackTileStore
            )
        }
        scheduledTileRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Called when user switches to a tab that needs tiles.
    /// Only triggers a rebuild if data changed while on another tab.
    func flushIfDirty(
        currentTab: NavigationTab,
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        trackTileStore: TrackTileStore
    ) {
        guard isDirty else { return }
        scheduleRebuild(
            currentTab: currentTab,
            delay: 0.25,
            force: true,
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
            trackTileStore: trackTileStore
        )
    }

    private func rebuildTrackTiles(
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        trackTileStore: TrackTileStore,
        zoom: Int = TrackRenderAdapter.unifiedRenderZoom
    ) {
        let journeyRevision = journeyStore.trackTileRevision
        let passiveRevision = lifelogStore.trackTileRevision
        if let manifest = trackTileStore.currentManifest,
           manifest.zoom == zoom,
           manifest.journeyRevision == journeyRevision,
           manifest.passiveRevision == passiveRevision {
            return
        }

        trackTileRebuildTask?.cancel()
        trackTileRebuildTask = Task.detached(priority: .utility) { [journeyStore, lifelogStore, trackTileStore] in
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

    private func rebuildTrackTilesAsync(
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        trackTileStore: TrackTileStore,
        zoom: Int = TrackRenderAdapter.unifiedRenderZoom
    ) async {
        rebuildTrackTiles(
            journeyStore: journeyStore,
            lifelogStore: lifelogStore,
            trackTileStore: trackTileStore,
            zoom: zoom
        )
        await trackTileRebuildTask?.value
    }
}

enum AppLifecycleCoordinator {
    @MainActor
    static func handleScenePhaseChange(
        phase: ScenePhase,
        currentUserID: String,
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        trackTileStore: TrackTileStore,
        trackTileCoordinator: TrackTileRebuildCoordinator,
        currentTab: NavigationTab,
        applyIdleLocationPolicy: @escaping @MainActor (Bool) -> Void,
        syncMotionActivityPolicy: @escaping @MainActor () -> Void
    ) {
        if phase == .background || phase == .inactive {
            journeyStore.flushPersist()
            lifelogStore.flushPersistNow()
            Task {
                await AppJourneySyncCoordinator.syncPendingCloudChanges(
                    userID: currentUserID,
                    journeyStore: journeyStore,
                    lifelogStore: lifelogStore,
                    reason: "scene_\(phase == .background ? "background" : "inactive")"
                )
            }
        }
        if phase == .active {
            applyIdleLocationPolicy(true)
            syncMotionActivityPolicy()
            trackTileCoordinator.scheduleRebuild(
                currentTab: currentTab,
                delay: 0.10,
                force: false,
                journeyStore: journeyStore,
                lifelogStore: lifelogStore,
                trackTileStore: trackTileStore
            )
        }
    }
}
