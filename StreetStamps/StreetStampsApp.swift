import SwiftUI
import UIKit
@main
struct StreetStampsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("streetstamps.intro_slides_shown.v1") private var hasSeenIntroSlides = false
    @StateObject private var locationHub = LocationHub.shared
    @StateObject private var sessionStore: UserSessionStore
    @StateObject private var journeyStore: JourneyStore
    @StateObject private var cityCache: CityCache
    @StateObject private var lifelogStore: LifelogStore
    @StateObject private var socialStore: SocialGraphStore
    @StateObject private var flow = AppFlowCoordinator()
    @StateObject private var onboardingGuide = OnboardingGuideStore()
    @State private var showAuthEntry = false

    /// Ensure passive location stream is alive for Lifelog when no active journey is running.
    private func ensurePassiveLocationTrackingIfNeeded() {
        if !TrackingService.shared.isTracking {
            locationHub.startLowPower()
        }
    }

    init() {
        let session = UserSessionStore()
        _sessionStore = StateObject(wrappedValue: session)

        let paths = StoragePath(userID: session.currentUserID)
        let jStore = JourneyStore(paths: paths)
        _journeyStore = StateObject(wrappedValue: jStore)
        _cityCache = StateObject(wrappedValue: CityCache(paths: paths, journeyStore: jStore))
        _lifelogStore = StateObject(wrappedValue: LifelogStore(paths: paths))
        _socialStore = StateObject(wrappedValue: SocialGraphStore(userID: session.currentUserID))

        configureGlobalTabBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenIntroSlides {
                    MainTabView()
                } else {
                    IntroSlidesView {
                        hasSeenIntroSlides = true
                    }
                }
            }
                .environmentObject(locationHub)
                .environmentObject(sessionStore)
                .environmentObject(journeyStore)
                .environmentObject(cityCache)
                .environmentObject(lifelogStore)
                .environmentObject(socialStore)
                .environmentObject(flow)
                .environmentObject(onboardingGuide)
                .task {
                    BackendAPIClient.shared.bindSessionStore(sessionStore)
                    sessionStore.bootstrapFileSystem()
                    VoiceBroadcastService.shared.start()
                    journeyStore.load()
                    lifelogStore.load()
                    lifelogStore.bind(to: locationHub)
                    locationHub.requestPermissionIfNeeded()
                    ensurePassiveLocationTrackingIfNeeded()
                    onboardingGuide.startIfNeeded()
                    let firstPromptKey = "streetstamps.auth_entry_shown.v1"
                    if hasSeenIntroSlides &&
                        !sessionStore.isLoggedIn &&
                        !UserDefaults.standard.bool(forKey: firstPromptKey) {
                        UserDefaults.standard.set(true, forKey: firstPromptKey)
                        showAuthEntry = true
                    }
                }
                .onChange(of: hasSeenIntroSlides) { _, seen in
                    guard seen else { return }
                    let firstPromptKey = "streetstamps.auth_entry_shown.v1"
                    if !sessionStore.isLoggedIn && !UserDefaults.standard.bool(forKey: firstPromptKey) {
                        UserDefaults.standard.set(true, forKey: firstPromptKey)
                        showAuthEntry = true
                    }
                }
                .onChange(of: sessionStore.currentUserID) { _, uid in
                    let paths = StoragePath(userID: uid)
                    sessionStore.bootstrapFileSystem()
                    journeyStore.rebind(paths: paths)
                    journeyStore.load()
                    cityCache.rebind(paths: paths)
                    lifelogStore.rebind(paths: paths)
                    lifelogStore.load()
                    lifelogStore.bind(to: locationHub)
                    ensurePassiveLocationTrackingIfNeeded()
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
                    if phase == .active {
                        ensurePassiveLocationTrackingIfNeeded()
                    }
                }
        }
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
