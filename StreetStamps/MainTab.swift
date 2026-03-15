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
        Item(tab: .start, icon: .asset("tab_start_icon")),
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

enum MainSidebarDestination: String, Identifiable, CaseIterable {
    case profile
    case settings
    case equipment
    case postcards
    case inviteFriend

    var id: String { rawValue }

    static let primaryDestinations: [MainSidebarDestination] = [
        .profile,
        .equipment,
        .settings
    ]

    static let quickActions: [MainSidebarDestination] = [
        .postcards,
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
        case .postcards:
            return NavigationChrome(title: L10n.upper("postcard_nav_title"), leadingAccessory: .back, titleLevel: .secondary)
        case .inviteFriend:
            return NavigationChrome(title: L10n.upper("profile_invite_friends"), leadingAccessory: .back, titleLevel: .secondary)
        }
    }
}

struct MainSidebarPresentationState {
    var activeDestination: MainSidebarDestination?

    mutating func handleOpenDestinationSignal(pendingDestination: MainSidebarDestination?) {
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
    @State private var sidebarPresentation = MainSidebarPresentationState()

    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore

    @State private var pendingResumeJourney: JourneyRoute? = nil
    @State private var didPromptResumeThisLaunch: Bool = false

    var body: some View {
        tabContent
        .overlay(alignment: .top) {
            if onboardingGuide.canResume {
                HStack {
                    Spacer()
                    Button(L10n.t("main_resume_onboarding")) {
                        onboardingGuide.resume()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Color.black)
                    .clipShape(Capsule(style: .continuous))
                    .padding(.top, 12)
                    .padding(.trailing, 14)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let step = globalGuideStep {
                OnboardingCoachCard(
                    message: step.message,
                    actionTitle: step.actionTitle,
                    onAction: { runGlobalGuideAction(step) },
                    onLater: { onboardingGuide.pauseForLater() },
                    onSkip: { onboardingGuide.skipAll() }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 90)
            }
        }
        .onReceive(store.$hasLoaded) { loaded in
            guard loaded else { return }
            maybePromptResumeIfNeeded()
        }
        .onChange(of: selectedTab) { tab in
            loadedTabs.insert(tab)
            flow.updateCurrentTab(tab)
            if tab == .cities {
                onboardingGuide.advance(.openCityCards)
                onboardingGuide.advance(.openMemory)
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
        .onReceive(flow.$openSidebarDestinationSignal) { _ in
            sidebarPresentation.handleOpenDestinationSignal(
                pendingDestination: flow.pendingSidebarDestination
            )
            flow.consumePendingSidebarDestination()
        }
        .fullScreenCover(item: $sidebarPresentation.activeDestination, onDismiss: {
            sidebarPresentation.dismiss()
        }) { destination in
            sidebarDestinationView(for: destination)
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
            Button(L10n.t("resume_prompt_end"), role: .destructive) {
                pendingResumeJourney = nil
                selectedTab = .start
                flow.requestEndOngoing()
            }
        } message: {
            Text(L10n.t("resume_prompt_message"))
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
    }

    private func shouldRenderTab(_ tab: NavigationTab) -> Bool {
        TabRenderPolicy.shouldRender(
            tab: tab,
            selectedTab: selectedTab,
            loadedTabs: loadedTabs
        )
    }

    @ViewBuilder
    private func sidebarDestinationView(for destination: MainSidebarDestination) -> some View {
        NavigationStack {
            switch destination {
            case .profile:
                ProfileView()
            case .settings:
                SettingsView()
            case .equipment:
                SidebarEquipmentEntryView()
            case .postcards:
                SidebarPostcardsEntryView(initialBox: .received, focusMessageID: nil)
            case .inviteFriend:
                SidebarInviteFriendEntryView()
            }
        }
    }

    private var globalGuideStep: OnboardingGuideStore.Step? {
        guard onboardingGuide.isActive, let step = onboardingGuide.currentStep else { return nil }
        switch step {
        case .openCityCards:
            return selectedTab == .cities ? nil : .openCityCards
        case .openMemory:
            return selectedTab == .cities ? nil : .openMemory
        default:
            return nil
        }
    }

    private func runGlobalGuideAction(_ step: OnboardingGuideStore.Step) {
        switch step {
        case .openCityCards:
            selectedTab = .cities
            onboardingGuide.advance(.openCityCards)
        case .openMemory:
            selectedTab = .cities
            onboardingGuide.advance(.openMemory)
        default:
            break
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
        // Lifelog hosts a heavy map stack; keep it off-tree when not active.
        tab != .lifelog
    }
}

private struct SidebarEquipmentEntryView: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    @State private var loadout = AvatarLoadoutStore.load()

    var body: some View {
        EquipmentView(loadout: $loadout)
            .onChange(of: loadout) { _, newValue in
                UserScopedProfileStateStore.saveCurrentLoadout(newValue, for: sessionStore.currentUserID)
                UserScopedProfileStateStore.markPendingLoadout(newValue, for: sessionStore.currentUserID)
            }
    }
}

private struct MainSidebarMenuView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @Binding var isPresented: Bool
    let onSelectDestination: (MainSidebarDestination) -> Void
    
    private let sidebarItems: [(title: String, icon: String, destination: MainSidebarDestination)] = [
        (L10n.t("profile_title"), "person", .profile),
        (L10n.upper("equipment_title"), "tshirt", .equipment),
        (L10n.t("settings_title"), "gearshape", .settings),
        (L10n.upper("postcard_nav_title"), "envelope", .postcards),
        (L10n.upper("profile_invite_friends"), "person.badge.plus", .inviteFriend)
    ]

    private var displayName: String {
        let profile = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.isEmpty { return profile.uppercased() }
        if let uid = sessionStore.accountUserID, !uid.isEmpty { return uid.uppercased() }
        return L10n.t("explorer_fallback")
    }

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = min(320, proxy.size.width * 0.86)

            ZStack(alignment: .leading) {
                Color.black.opacity(0.30)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        header

                        Divider()
                            .overlay(Color.black.opacity(0.06))

                        VStack(spacing: 8) {
                            ForEach(sidebarItems, id: \.title) { item in
                                drawerItem(title: item.title, icon: item.icon) {
                                    onSelectDestination(item.destination)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        Spacer(minLength: 0)

                        Divider()
                            .overlay(Color.black.opacity(0.06))

                        Text(L10n.t("app_name"))
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundColor(FigmaTheme.text.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                    .frame(width: drawerWidth)
                    .background(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 40, x: 8, y: 0)

                    Spacer(minLength: 0)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { v in
                        if v.translation.width < -80 {
                            withAnimation(.easeOut(duration: 0.25)) {
                                isPresented = false
                            }
                        }
                    }
            )
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(FigmaTheme.text)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }

            Button {
                onSelectDestination(.profile)
                withAnimation(.easeOut(duration: 0.25)) {
                    isPresented = false
                }
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 82 / 255, green: 183 / 255, blue: 136 / 255).opacity(0.10),
                                    Color(red: 116 / 255, green: 198 / 255, blue: 157 / 255).opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay {
                            RobotRendererView(size: 30, face: .front, loadout: AvatarLoadoutStore.load())
                        }
                        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    private func drawerItem(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.25)) {
                isPresented = false
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(FigmaTheme.text)
                    .frame(width: 30)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.3)
                    .foregroundColor(FigmaTheme.text)

                Spacer(minLength: 0)
            }
            .padding(.leading, 20)
            .padding(.trailing, 18)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.984, green: 0.984, blue: 0.976))
            )
            .shadow(color: .clear, radius: 12, x: 0, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarPostcardsEntryView: View {
    let initialBox: PostcardInboxView.Box
    let focusMessageID: String?

    var body: some View {
        PostcardInboxView(initialBox: initialBox, focusMessageID: focusMessageID)
    }
}

private struct SidebarInviteFriendEntryView: View {
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

#Preview {
    MainTabView()
}
