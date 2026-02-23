import SwiftUI

// MARK: - Navigation Tabs Enum

enum NavigationTab: Int, CaseIterable, Identifiable {
    case start = 0
    case cities = 1
    case friends = 2
    case memory = 3
    case profile = 4
    case lifelog = 5
    case global = 6
    case settings = 7

    var id: Int { rawValue }

    /// Sidebar order aligned with current product UI.
    static var allCases: [NavigationTab] {
        [.start, .memory, .cities, .friends, .lifelog, .profile, .settings]
    }

    var title: String {
        switch self {
        case .start: return "START"
        case .global: return "GLOBE VIEW"
        case .cities: return "CITIES"
        case .friends: return "FRIENDS"
        case .memory: return "MEMORY"
        case .lifelog: return "LIFELOG"
        case .profile: return "PROFILE"
        case .settings: return "SETTINGS"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .start: return "HOME"
        case .memory: return "MEMORIES"
        case .cities: return "CITIES"
        case .profile: return "PROFILE"
        case .settings: return "SETTINGS"
        case .global: return "GLOBE VIEW"
        case .friends: return "FRIENDS"
        case .lifelog: return "LIFELOG"
        }
    }

    var icon: String {
        switch self {
        case .start: return "house"
        case .global: return "globe.europe.africa"
        case .cities: return "mappin.and.ellipse"
        case .friends: return "person.2"
        case .memory: return "heart"
        case .lifelog: return "point.bottomleft.forward.to.point.topright.scurvepath"
        case .profile: return "person"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Sidebar View

struct SidebarMenuView: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @Binding var selectedTab: NavigationTab
    @Binding var isPresented: Bool

    private var displayName: String {
        let profile = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.isEmpty {
            return profile.uppercased()
        }
        if let uid = sessionStore.accountUserID, !uid.isEmpty {
            return uid.uppercased()
        }
        return "EXPLORER"
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

                        menuList

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
                Text(L10n.t("explore"))
                    .appHeaderStyle()
                    .foregroundColor(FigmaTheme.text)
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

                    Text(L10n.t("explorer_fallback"))
                        .font(.system(size: 12, weight: .regular))
                        .tracking(0.3)
                        .foregroundColor(Color(red: 0.42, green: 0.42, blue: 0.42))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    private var menuList: some View {
        VStack(spacing: 8) {
            ForEach(sidebarTabs) { tab in
                SidebarMenuItem(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    onTap: {
                        selectedTab = tab
                        withAnimation(.easeOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var sidebarTabs: [NavigationTab] {
        NavigationTab.allCases
    }
}

// MARK: - Sidebar Menu Item

struct SidebarMenuItem: View {
    let tab: NavigationTab
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(isSelected ? .white : .black)
                    .frame(width: 30)

                Text(tab.sidebarTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(0.3)
                    .foregroundColor(isSelected ? .white : .black)

                Spacer(minLength: 0)
            }
            .padding(.leading, 20)
            .padding(.trailing, 18)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isSelected ? Color(red: 82 / 255, green: 183 / 255, blue: 136 / 255) : Color(red: 0.984, green: 0.984, blue: 0.976))
            )
            .shadow(color: isSelected ? Color(red: 82 / 255, green: 183 / 255, blue: 136 / 255).opacity(0.22) : .clear, radius: 12, x: 0, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header with Hamburger Menu

struct NavigationHeader: View {
    let title: String
    let subtitle: String?
    @Binding var showSidebar: Bool
    var trailing: AnyView? = nil

    init(title: String, subtitle: String? = nil, showSidebar: Binding<Bool>, trailing: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self._showSidebar = showSidebar
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            SidebarHamburgerButton(showSidebar: $showSidebar, size: 42, iconSize: 20, iconWeight: .semibold, foreground: .black)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .appHeaderStyle()
                    .tracking(0.6)

                if let subtitle = subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(FigmaTheme.text.opacity(0.5))
                }
            }

            Spacer()

            if let trailing = trailing {
                trailing
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(UITheme.bg)
    }
}

// MARK: - Two-line Title Header

struct TwoLineNavigationHeader: View {
    let line1: String
    let line2: String
    let subtitle: String?
    @Binding var showSidebar: Bool
    var trailing: AnyView? = nil

    init(line1: String, line2: String, subtitle: String? = nil, showSidebar: Binding<Bool>, trailing: AnyView? = nil) {
        self.line1 = line1
        self.line2 = line2
        self.subtitle = subtitle
        self._showSidebar = showSidebar
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(line1.uppercased())
                    .appBodyStrongStyle()
                    .tracking(0.6)
                    .foregroundColor(FigmaTheme.text)

                Text(line2.uppercased())
                    .appBodyStrongStyle()
                    .tracking(0.6)
                    .foregroundColor(FigmaTheme.text)

                if let subtitle = subtitle {
                    Text(subtitle.uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.5)
                        .foregroundColor(FigmaTheme.text.opacity(0.5))
                        .padding(.top, 4)
                }
            }

            Spacer()

            if let trailing = trailing {
                trailing
            }

            SidebarHamburgerButton(showSidebar: $showSidebar, size: 42, iconSize: 20, iconWeight: .semibold, foreground: .black)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(UITheme.bg)
    }
}
