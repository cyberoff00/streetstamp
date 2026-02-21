import SwiftUI
@main
struct StreetStampsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationHub = LocationHub.shared
    @StateObject private var sessionStore: UserSessionStore
    @StateObject private var journeyStore: JourneyStore
    @StateObject private var cityCache: CityCache
    @StateObject private var lifelogStore: LifelogStore
    @StateObject private var socialStore: SocialGraphStore
    @StateObject private var flow = AppFlowCoordinator()
    @State private var showAuthEntry = false

    init() {
        let session = UserSessionStore()
        _sessionStore = StateObject(wrappedValue: session)

        let paths = StoragePath(userID: session.currentUserID)
        let jStore = JourneyStore(paths: paths)
        _journeyStore = StateObject(wrappedValue: jStore)
        _cityCache = StateObject(wrappedValue: CityCache(paths: paths, journeyStore: jStore))
        _lifelogStore = StateObject(wrappedValue: LifelogStore(paths: paths))
        _socialStore = StateObject(wrappedValue: SocialGraphStore(userID: session.currentUserID))
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(locationHub)
                .environmentObject(sessionStore)
                .environmentObject(journeyStore)
                .environmentObject(cityCache)
                .environmentObject(lifelogStore)
                .environmentObject(socialStore)
                .environmentObject(flow)
                .task {
                    sessionStore.bootstrapFileSystem()
                    VoiceBroadcastService.shared.start()
                    journeyStore.load()
                    lifelogStore.load()
                    lifelogStore.bind(to: locationHub)
                    let firstPromptKey = "streetstamps.auth_entry_shown.v1"
                    if !sessionStore.isLoggedIn && !UserDefaults.standard.bool(forKey: firstPromptKey) {
                        UserDefaults.standard.set(true, forKey: firstPromptKey)
                        showAuthEntry = true
                    }
                }
                .onChange(of: sessionStore.currentUserID) { _, uid in
                    socialStore.switchUser(uid)
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
                }
                .onChange(of: scenePhase) { phase in
                    // Best-effort: reduce data loss when the app is backgrounded or suspended.
                    if phase == .background || phase == .inactive {
                        journeyStore.flushPersist()
                    }
                }
        }
    }
}
