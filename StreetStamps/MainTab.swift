import SwiftUI
import Combine

private enum MainSidebarDestination: String, Identifiable {
    case profile
    case settings
    case equipment

    var id: String { rawValue }
}

@MainActor
struct MainTabView: View {
    @State private var selectedTab: NavigationTab = .start
    @State private var loadedTabs: Set<NavigationTab> = [.start]
    @State private var showSidebar = false
    @State private var sidebarDestination: MainSidebarDestination? = nil

    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore

    @State private var pendingResumeJourney: JourneyRoute? = nil
    @State private var didPromptResumeThisLaunch: Bool = false

    var body: some View {
        ZStack(alignment: .leading) {
            tabContent
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .global)
                        .onEnded { v in
                            guard canSwipeSidebar else { return }
                            guard !showSidebar else { return }
                            if v.startLocation.x < 24, v.translation.width > 60 {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showSidebar = true
                                }
                            }
                        }
                )

            if showSidebar {
                MainSidebarMenuView(
                    isPresented: $showSidebar,
                    onSelectDestination: { destination in
                        sidebarDestination = destination
                    }
                )
                .zIndex(100)
            }
        }
        .overlay(alignment: .topLeading) {
            if flow.shouldShowSidebarButton && !showSidebar {
                sidebarLauncherButton
                    .padding(.leading, 20)
                    .padding(.top, 14)
            }
        }
        .overlay(alignment: .top) {
            if onboardingGuide.canResume {
                HStack {
                    Spacer()
                    Button("继续引导") {
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
        .sheet(item: $sidebarDestination) { destination in
            NavigationStack {
                switch destination {
                case .profile:
                    ProfileView()
                case .settings:
                    SettingsView()
                case .equipment:
                    SidebarEquipmentEntryView()
                }
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
            }
            if tab == .memory {
                onboardingGuide.advance(.openMemory)
            }
        }
        .onAppear {
            flow.updateCurrentTab(selectedTab)
        }
        .onReceive(flow.$requestedTab) { tab in
            guard let tab else { return }
            selectedTab = tab
            flow.clearRequestedTab()
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
                Label("Home", systemImage: "house.fill")
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
                Label("Friends", systemImage: "person.2.fill")
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
                Label("Collection", systemImage: "square.grid.2x2.fill")
            }

            NavigationStack {
                if shouldRenderTab(.memory) {
                    JourneyMemoryMainView(
                        showSidebar: .constant(false),
                        usesSidebarHeader: false,
                        hideLeadingControl: true
                    )
                } else {
                    Color.clear
                }
            }
            .tag(NavigationTab.memory)
            .tabItem {
                Label("Memory", systemImage: "heart.fill")
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
                    Label(L10n.t("tab_lifelog"), systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                }
        }
        .tint(FigmaTheme.primary)
        .toolbarColorScheme(.light, for: .tabBar)
        .toolbarBackground(.white, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private var canSwipeSidebar: Bool { true }
    private func shouldRenderTab(_ tab: NavigationTab) -> Bool {
        TabRenderPolicy.shouldRender(
            tab: tab,
            selectedTab: selectedTab,
            loadedTabs: loadedTabs
        )
    }

    private var globalGuideStep: OnboardingGuideStore.Step? {
        guard onboardingGuide.isActive, let step = onboardingGuide.currentStep else { return nil }
        switch step {
        case .openCityCards:
            return selectedTab == .cities ? nil : .openCityCards
        case .openMemory:
            return selectedTab == .memory ? nil : .openMemory
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
            selectedTab = .memory
            onboardingGuide.advance(.openMemory)
        default:
            break
        }
    }

    private var sidebarLauncherButton: some View {
        SidebarHamburgerButton(
            showSidebar: $showSidebar,
            size: 42,
            iconSize: 20,
            iconWeight: .semibold,
            foreground: .black
        )
        .accessibilityLabel("Open sidebar")
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
        ("PROFILE", "person", .profile),
        ("EQUIPMENT", "tshirt", .equipment),
        ("SETTINGS", "gearshape", .settings)
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

                        Text(L10n.t("journey_diary_version"))
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

#Preview {
    MainTabView()
}
