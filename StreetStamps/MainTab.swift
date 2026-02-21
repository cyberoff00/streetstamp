import SwiftUI
import Combine

struct MainTabView: View {
    @State private var selectedTab: NavigationTab = .start
    @State private var showSidebar = false

    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var flow: AppFlowCoordinator

    @State private var pendingResumeJourney: JourneyRoute? = nil
    @State private var didPromptResumeThisLaunch: Bool = false

    @State private var showToast = false
    @State private var toastText = ""

    var body: some View {
        GeometryReader { _ in
        let core = ZStack {
            // Main content based on selected tab
            Group {
                switch selectedTab {
                case .start:
                    MainView(selectedTab: Binding(
                        get: { selectedTab.rawValue },
                        set: { selectedTab = NavigationTab(rawValue: $0) ?? .start }
                    ), showSidebar: $showSidebar)
                case .global:
                    GlobeViewScreen(showSidebar: $showSidebar)

                case .cities:
                    NavigationStack {
                        CityStampLibraryView(showSidebar: $showSidebar)
                    }

                case .friends:
                    NavigationStack {
                        FriendsHubView()
                    }

                case .memory:
                    NavigationStack {
                        JourneyMemoryMainView(showSidebar: $showSidebar)
                    }

                case .lifelog:
                    LifelogView(showSidebar: $showSidebar)

                case .profile:
                    ProfileView(showSidebar: $showSidebar)
                case .settings:
                    SettingsView(showSidebar: $showSidebar)
                }
            }
            .onReceive(cityCache.$lastEvent) { evt in
                guard let evt else { return }
                if case .addedNewCity(_, let name) = evt {
                    toastText = String(format: L10n.t("toast_city_added"), name)
                    showToastTemporarily()
                }
            }
            .onReceive(store.$hasLoaded) { loaded in
                guard loaded else { return }
                maybePromptResumeIfNeeded()
            }

            // App-level resume prompt
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

            // Toast at top
            VStack {
                if showToast {
                    Text(toastText)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(10)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .safeAreaInset(edge: .top, spacing: 0) { EmptyView() }
            
            // Sidebar overlay
            if showSidebar {
                SidebarMenuView(
                    selectedTab: $selectedTab,
                    isPresented: $showSidebar
                )
                .zIndex(100)
            }
        }
        // Swipe from left edge to open sidebar.
        // Avoid attaching this root gesture on heavy map pages (Lifelog),
        // which can create huge recognizer dependency graphs with Mapbox gestures.
        if selectedTab == .lifelog {
            core
        } else {
            core
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .global)
                        .onEnded { v in
                            guard !showSidebar else { return }
                            let startX = v.startLocation.x
                            // Start near the left edge, swipe right
                            if startX < 24, v.translation.width > 60 {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showSidebar = true
                                }
                            }
                        }
                )
        }
        }
    }

    private func showToastTemporarily() {
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { showToast = false }
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

#Preview {
    MainTabView()
}
