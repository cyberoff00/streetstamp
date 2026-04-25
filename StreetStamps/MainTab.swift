import SwiftUI
import Combine

struct MainTabLayout {
    enum Icon: Equatable {
        case asset(String)
        case system(String)
    }

    struct Item: Equatable {
        let tab: NavigationTab
        let icon: Icon
    }

    static let bottomTabs: [Item] = [
        Item(tab: .start, icon: .asset("tab_lifelog_icon")),
        Item(tab: .cities, icon: .asset("tab_memory_icon")),
        Item(tab: .lifelog, icon: .asset("tab_cities_icon")),
        Item(tab: .friends, icon: .asset("tab_friends_icon")),
        Item(tab: .profile, icon: .system("person"))
    ]

    static func icon(for tab: NavigationTab) -> Icon {
        bottomTabs.first(where: { $0.tab == tab })?.icon ?? .system(tab.icon)
    }

    @ViewBuilder
    static func image(for tab: NavigationTab) -> some View {
        switch icon(for: tab) {
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
        case .system(let name):
            Image(systemName: name)
        }
    }
}

enum ModalNavDestination: String, Identifiable, CaseIterable {
    case profile
    case settings
    case equipment
    case inviteFriend

    var id: String { rawValue }

    static let primaryDestinations: [ModalNavDestination] = [
        .profile,
        .equipment,
        .settings
    ]

    static let quickActions: [ModalNavDestination] = [
        .inviteFriend
    ]

    var navigationChrome: NavigationChrome {
        switch self {
        case .profile:
            return NavigationChrome(title: L10n.t("profile_title"), leadingAccessory: .none, titleLevel: .secondary)
        case .settings:
            return NavigationChrome(title: L10n.t("settings_title"), leadingAccessory: .none, titleLevel: .secondary)
        case .equipment:
            return NavigationChrome(title: L10n.upper("equipment_title"), leadingAccessory: .none, titleLevel: .secondary)
        case .inviteFriend:
            return NavigationChrome(title: L10n.upper("profile_invite_friends"), leadingAccessory: .back, titleLevel: .secondary)
        }
    }
}

struct ModalNavPresentationState {
    var activeDestination: ModalNavDestination?

    mutating func handleOpenDestinationSignal(pendingDestination: ModalNavDestination?) {
        guard let pendingDestination else { return }
        activeDestination = pendingDestination
    }

    mutating func dismiss() {
        activeDestination = nil
    }
}

@MainActor
struct MainTabView: View {
    @State private var selectedTab: NavigationTab = .start
    @State private var loadedTabs: Set<NavigationTab> = [.start]
    @State private var modalNavPresentation = ModalNavPresentationState()

    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @ObservedObject private var featureFlags = FeatureFlagStore.shared

    @State private var pendingResumeJourney: JourneyRoute? = nil
    @State private var didPromptResumeThisLaunch: Bool = false
    @ObservedObject private var tracking = TrackingService.shared
    @State private var showAutoEndedAlert: Bool = false
    @AppStorage("streetstamps.hint.journey_just_saved") private var journeyJustSaved = false
    @State private var savedHintDismissTask: Task<Void, Never>?

    var body: some View {
        tabContent
        .overlay(alignment: .bottom) {
            if journeyJustSaved && onboardingGuide.shouldShowHint(.journeySavedToMemory) {
                ContextualHintBar(
                    icon: "checkmark.circle",
                    message: L10n.t("hint_journey_saved"),
                    actionTitle: L10n.t("hint_journey_saved_action"),
                    onAction: {
                        selectedTab = .cities
                        onboardingGuide.dismissHint(.journeySavedToMemory)
                        journeyJustSaved = false
                    },
                    onDismiss: {
                        onboardingGuide.dismissHint(.journeySavedToMemory)
                        journeyJustSaved = false
                    }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 90)
                .onAppear {
                    savedHintDismissTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        guard !Task.isCancelled else { return }
                        onboardingGuide.dismissHint(.journeySavedToMemory)
                        journeyJustSaved = false
                    }
                }
            }
        }
        .onReceive(store.$hasLoaded) { loaded in
            guard loaded else { return }
            // Delay the prompt so startup animations finish before the alert
            // appears. Presenting a fullScreenCover while SwiftUI is still
            // mid-animation silently drops the presentation and leaves the
            // app in a frozen state.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                maybePromptResumeIfNeeded()
            }
        }
        .onChange(of: selectedTab) { tab in
            loadedTabs.insert(tab)
            flow.updateCurrentTab(tab)
            if tab == .cities {
                onboardingGuide.advance(.openCityCards)
                onboardingGuide.advance(.openMemory)
            }
            // Dismiss journey-saved hint on tab switch
            if journeyJustSaved {
                savedHintDismissTask?.cancel()
                onboardingGuide.dismissHint(.journeySavedToMemory)
                journeyJustSaved = false
            }
        }
        .onAppear {
            flow.updateCurrentTab(selectedTab)
        }
        .onReceive(flow.$requestedTab) { tab in
            guard let tab else { return }
            selectedTab = MainTabLayout.bottomTabs.contains(where: { $0.tab == tab }) ? tab : .start
            flow.clearRequestedTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCaptureFromWidget)) { _ in
            selectedTab = .start
            flow.requestWidgetCapture()
        }
        .onReceive(flow.$openModalDestinationSignal) { _ in
            modalNavPresentation.handleOpenDestinationSignal(
                pendingDestination: flow.pendingModalDestination
            )
            flow.consumePendingModalDestination()
        }
        .fullScreenCover(item: $modalNavPresentation.activeDestination, onDismiss: {
            modalNavPresentation.dismiss()
        }) { destination in
            modalDestinationView(for: destination)
        }
        .alert(L10n.t("resume_prompt_title"), isPresented: Binding(
            get: { pendingResumeJourney != nil },
            set: { if !$0 { pendingResumeJourney = nil } }
        )) {
            Button(L10n.t("resume_prompt_continue")) {
                pendingResumeJourney = nil
                selectedTab = .start
                flow.requestResumeOngoing()
            }
            Button(L10n.t("resume_prompt_end")) {
                pendingResumeJourney = nil
                selectedTab = .start
                flow.requestEndOngoing()
            }
        } message: {
            Text(L10n.t("resume_prompt_message"))
        }
        .alert(L10n.t("auto_pause_alert_title"), isPresented: $showAutoEndedAlert) {
            Button(L10n.t("ok"), role: .cancel) {
                tracking.clearAutoEndedNotice()
            }
        } message: {
            Text(L10n.t("auto_pause_alert_message"))
        }
        .onChange(of: tracking.pendingAutoEndedNotice) { notice in
            if notice != nil {
                showAutoEndedAlert = true
            }
        }
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            MainView(selectedTab: Binding(
                get: { selectedTab.rawValue },
                set: { selectedTab = NavigationTab(rawValue: $0) ?? .start }
            ))
            .tag(NavigationTab.start)
            .tabItem {
                MainTabLayout.image(for: .start)
                Text(L10n.t("tab_home"))
            }

            NavigationStack {
                if shouldRenderTab(.cities) {
                    CollectionTabView()
                } else {
                    Color.clear
                }
            }
            .tag(NavigationTab.cities)
            .tabItem {
                MainTabLayout.image(for: .cities)
                Text(L10n.t("tab_memory"))
            }

            Group {
                if shouldRenderTab(.lifelog) {
                    LifelogView()
                } else {
                    Color.clear
                }
            }
            .tag(NavigationTab.lifelog)
            .tabItem {
                MainTabLayout.image(for: .lifelog)
                Text(L10n.upper("tab_worldo"))
            }

            if featureFlags.socialEnabled {
                NavigationStack {
                    if shouldRenderTab(.friends) {
                        FriendsHubView()
                    } else {
                        Color.clear
                    }
                }
                .tag(NavigationTab.friends)
                .tabItem {
                    MainTabLayout.image(for: .friends)
                    Text(L10n.t("tab_friends"))
                }
            }

            NavigationStack {
                if shouldRenderTab(.profile) {
                    ProfileView()
                } else {
                    Color.clear
                }
            }
            .tag(NavigationTab.profile)
            .tabItem {
                MainTabLayout.image(for: .profile)
                Text(L10n.t("profile_title"))
            }
        }
        .tint(FigmaTheme.primary)
        .toolbarColorScheme(.light, for: .tabBar)
        .toolbarBackground(.white, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(
            TabBarSelectionHapticObserver(currentTab: selectedTab)
                .frame(width: 0, height: 0)
        )
    }

    private func shouldRenderTab(_ tab: NavigationTab) -> Bool {
        TabRenderPolicy.shouldRender(
            tab: tab,
            selectedTab: selectedTab,
            loadedTabs: loadedTabs
        )
    }

    @ViewBuilder
    private func modalDestinationView(for destination: ModalNavDestination) -> some View {
        switch destination {
        case .equipment:
            // Flat presentation (no wrapping NavigationStack) so returning
            // via the back button dismisses the fullScreenCover directly.
            // This avoids the iOS 17 blank-flash caused by the two-stage
            // "NavigationStack pop → cover dismiss" sequence. EquipmentView
            // has no inner NavigationLink/navigationDestination so it doesn't
            // need an outer stack. Trade-off: no edge swipe-back gesture
            // (SwipeBackEnabler relies on UINavigationController).
            ModalEquipmentEntryView()
        default:
            ModalNavigationWrapper(destination: destination) {
                modalNavPresentation.dismiss()
            }
        }
    }

    /// Prompt user once per launch if there is an unfinished journey on disk.
    private func maybePromptResumeIfNeeded() {
        guard !didPromptResumeThisLaunch else { return }
        didPromptResumeThisLaunch = true

        if let j = store.latestOngoing, j.endTime == nil {
            pendingResumeJourney = j
            return
        }
        if let j = store.journeys.first(where: { $0.endTime == nil }) {
            pendingResumeJourney = j
            return
        }
    }
}

enum TabRenderPolicy {
    static func shouldRender(
        tab: NavigationTab,
        selectedTab: NavigationTab,
        loadedTabs: Set<NavigationTab>
    ) -> Bool {
        if tab == selectedTab {
            return true
        }
        guard keepsViewAliveAfterSelection(tab) else {
            return false
        }
        return loadedTabs.contains(tab)
    }

    static func keepsViewAliveAfterSelection(_ tab: NavigationTab) -> Bool {
        true
    }
}

private struct ModalEquipmentEntryView: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    @State private var loadout = AvatarLoadoutStore.load()

    var body: some View {
        EquipmentView(loadout: $loadout)
            .id(sessionStore.currentUserID)
            .onChange(of: loadout) { _, newValue in
                UserScopedProfileStateStore.saveCurrentLoadout(newValue, for: sessionStore.currentUserID)
                UserScopedProfileStateStore.markPendingLoadout(newValue, for: sessionStore.currentUserID)
            }
            .onChange(of: sessionStore.currentUserID) { _, _ in
                loadout = AvatarLoadoutStore.load()
            }
    }
}

private struct ModalInviteFriendEntryView: View {
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"
    @State private var exclusiveID = ""
    @State private var inviteCode = ""

    private var resolvedDisplayName: String {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.t("explorer_fallback") : trimmed
    }

    private var resolvedExclusiveID: String {
        let remote = exclusiveID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remote.isEmpty { return remote }
        let source = sessionStore.accountUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return source.isEmpty ? "explorer" : source
    }

    private var resolvedInviteCode: String {
        let remote = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !remote.isEmpty { return remote }
        return SocialGraphStore.generateInviteCode(source: sessionStore.accountUserID ?? resolvedExclusiveID)
    }

    var body: some View {
        InviteFriendSheet(
            displayName: resolvedDisplayName,
            loadout: AvatarLoadoutStore.load(),
            exclusiveID: resolvedExclusiveID,
            inviteCode: resolvedInviteCode
        )
        .environmentObject(socialStore)
        .environmentObject(sessionStore)
        .task(id: sessionStore.currentAccessToken) {
            await refreshInviteIdentity()
        }
    }

    @MainActor
    private func refreshInviteIdentity() async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            return
        }

        do {
            let me = try await BackendAPIClient.shared.fetchMyProfile(token: token)
            if let id = me.resolvedExclusiveID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                exclusiveID = id
            }
            if let code = me.inviteCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
                inviteCode = code.uppercased()
            } else {
                inviteCode = SocialGraphStore.generateInviteCode(source: me.id)
            }
        } catch {
            // Keep local fallback values when backend data cannot be fetched.
        }
    }
}

/// Wraps modal destinations in a NavigationStack with an initial push,
/// so the user can swipe back to dismiss using the system gesture.
/// When the stack pops back to root, it auto-dismisses the fullScreenCover.
private struct ModalNavigationWrapper: View {
    let destination: ModalNavDestination
    let onDismiss: () -> Void

    @State private var path: [ModalNavDestination]

    init(destination: ModalNavDestination, onDismiss: @escaping () -> Void) {
        self.destination = destination
        self.onDismiss = onDismiss
        // Initialize path with the destination so NavigationStack renders the
        // target content on the first frame. Deferring to .onAppear caused a
        // blank flash on iOS 17 (root Color.clear visible before push animation).
        self._path = State(initialValue: [destination])
    }

    var body: some View {
        NavigationStack(path: $path) {
            Color.clear
                .navigationBarHidden(true)
                .navigationDestination(for: ModalNavDestination.self) { dest in
                    modalContent(for: dest)
                }
        }
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty {
                onDismiss()
            }
        }
    }

    @ViewBuilder
    private func modalContent(for dest: ModalNavDestination) -> some View {
        switch dest {
        case .profile:
            ProfileView()
        case .settings:
            SettingsView(showsBackButton: true)
        case .equipment:
            ModalEquipmentEntryView()
        case .inviteFriend:
            ModalInviteFriendEntryView()
        }
    }
}

#Preview {
    MainTabView()
}
