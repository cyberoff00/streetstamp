import SwiftUI

struct SettingsView: View {
    @Binding var showSidebar: Bool

    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue
    @AppStorage(AppSettings.voiceBroadcastEnabledKey) private var voiceBroadcastEnabled = true
    @AppStorage(AppSettings.voiceBroadcastIntervalKMKey) private var voiceBroadcastIntervalKM = 1
    @AppStorage(AppSettings.longStationaryReminderEnabledKey) private var longStationaryReminderEnabled = true

    @State private var showComingSoon = false
    @State private var comingSoonTitle = ""

    private var appearance: MapAppearanceStyle {
        get { MapAppearanceStyle(rawValue: mapAppearanceRaw) ?? .dark }
        nonmutating set { mapAppearanceRaw = newValue.rawValue }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "V\(version)"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    mapAppearanceSection
                    trackingAssistSection
                    generalSection
                    accountSection
                    infoSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
            .background(FigmaTheme.mutedBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                settingsHeader
            }
            .alert("Coming Soon", isPresented: $showComingSoon) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(comingSoonTitle) is not available yet.")
            }
        }
    }

    private var settingsHeader: some View {
        HStack {
            SidebarHamburgerButton(showSidebar: $showSidebar, size: 42, iconSize: 20, iconWeight: .semibold, foreground: .black)

            Spacer()

            Text("SETTINGS")
                .appHeaderStyle()
                .foregroundColor(.black)

            Spacer()

            Color.clear
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.14))
                .frame(height: 0.8)
        }
    }

    private var mapAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("MAP APPEARANCE")

            VStack(alignment: .leading, spacing: 14) {
                Text("Apply to all maps and route rendering")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(FigmaTheme.subtext)

                segmentedContainer {
                    segmentButton(
                        title: "Dark",
                        isSelected: appearance == .dark,
                        action: {
                            appearance = .dark
                            MapAppearanceSettings.apply(.dark)
                        }
                    )
                    segmentButton(
                        title: "Day",
                        isSelected: appearance == .light,
                        action: {
                            appearance = .light
                            MapAppearanceSettings.apply(.light)
                        }
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .figmaSurfaceCard(radius: 30)
        }
    }

    private var trackingAssistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("TRACKING ASSIST")

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Voice Broadcast")
                            .font(.system(size: 30 / 2, weight: .black))
                            .foregroundColor(.black)

                        Text("Broadcast distance, elapsed time, and average pace at milestones.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(FigmaTheme.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    figmaToggle(isOn: $voiceBroadcastEnabled)
                }

                segmentedContainer {
                    segmentButton(title: "1 km", isSelected: voiceBroadcastIntervalKM == 1) {
                        voiceBroadcastIntervalKM = 1
                    }
                    segmentButton(title: "2 km", isSelected: voiceBroadcastIntervalKM == 2) {
                        voiceBroadcastIntervalKM = 2
                    }
                    segmentButton(title: "5 km", isSelected: voiceBroadcastIntervalKM == 5) {
                        voiceBroadcastIntervalKM = 5
                    }
                }
                .opacity(voiceBroadcastEnabled ? 1 : 0.45)
                .allowsHitTesting(voiceBroadcastEnabled)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .figmaSurfaceCard(radius: 30)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Long Stationary Reminder")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.black)

                        Text("Alert when movement stays within 100 m for 60 minutes.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(FigmaTheme.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    figmaToggle(isOn: $longStationaryReminderEnabled)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .figmaSurfaceCard(radius: 30)
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("GENERAL")

            VStack(spacing: 10) {
                settingsRow(title: "IMPORT GPX", icon: "map", iconColor: FigmaTheme.primary) {
                    showPlaceholder("Import GPX")
                }

                settingsRow(title: "NOTIFICATIONS", icon: "bell", iconColor: FigmaTheme.secondary) {
                    showPlaceholder("Notifications")
                }

                NavigationLink {
                    DebugChinaTestModule()
                        .navigationTitle("Debug Tools")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    settingsRowLabel(
                        title: "DEBUG TOOLS",
                        icon: "wrench.and.screwdriver",
                        iconColor: .black.opacity(0.68),
                        badgeText: "DEV",
                        rowHeight: 74
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("ACCOUNT")

            VStack(spacing: 10) {
                NavigationLink {
                    AccountCenterView()
                } label: {
                    settingsRowLabel(title: "ACCOUNT CENTER", icon: "person.crop.circle", iconColor: FigmaTheme.primary)
                }
                .buttonStyle(.plain)

                settingsRow(title: "SUBSCRIPTION", icon: "creditcard", iconColor: FigmaTheme.primary) {
                    showPlaceholder("Subscription")
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("INFORMATION")

            VStack(spacing: 10) {
                settingsRow(
                    title: "CHECK FOR\nUPDATES",
                    icon: "sparkles",
                    iconColor: FigmaTheme.secondary,
                    badgeText: appVersionText,
                    rowHeight: 88
                ) {
                    showPlaceholder("Check for Updates")
                }

                settingsRow(title: "ABOUT US", icon: "info.circle", iconColor: .black.opacity(0.75)) {
                    showPlaceholder("About Us")
                }

                settingsRow(title: "PRIVACY POLICY", icon: "shield", iconColor: .black.opacity(0.75)) {
                    showPlaceholder("Privacy Policy")
                }
            }
        }
    }

    @ViewBuilder
    private func segmentedContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(3)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FigmaTheme.mutedBackground)
        )
    }

    private func segmentButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isSelected ? Color.white : Color.clear)
                )
                .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func figmaToggle(isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn.wrappedValue ? FigmaTheme.primary : Color.black.opacity(0.2))
                    .frame(width: 56, height: 32)

                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .padding(.horizontal, 4)
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .tracking(0.6)
            .foregroundColor(.black.opacity(0.42))
            .padding(.horizontal, 4)
    }

    private func settingsRow(
        title: String,
        icon: String,
        iconColor: Color,
        badgeText: String? = nil,
        rowHeight: CGFloat = 68,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsRowLabel(
                title: title,
                icon: icon,
                iconColor: iconColor,
                badgeText: badgeText,
                rowHeight: rowHeight
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsRowLabel(
        title: String,
        icon: String,
        iconColor: Color,
        badgeText: String? = nil,
        rowHeight: CGFloat = 68
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.black)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.6)
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(FigmaTheme.mutedBackground)
                    )
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.46))
        }
        .padding(.horizontal, 20)
        .frame(minHeight: rowHeight)
        .figmaSurfaceCard(radius: 34)
    }

    private func showPlaceholder(_ title: String) {
        comingSoonTitle = title
        showComingSoon = true
    }
}
