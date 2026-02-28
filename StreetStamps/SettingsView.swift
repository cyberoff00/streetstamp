import SwiftUI
import Foundation
import CoreLocation
import UniformTypeIdentifiers
import AVFoundation
import CoreImage.CIFilterBuiltins
import Network
import Darwin

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var lifelogStore: LifelogStore

    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue
    @AppStorage(AppSettings.voiceBroadcastEnabledKey) private var voiceBroadcastEnabled = true
    @AppStorage(AppSettings.voiceBroadcastIntervalKMKey) private var voiceBroadcastIntervalKM = 1
    @AppStorage(AppSettings.longStationaryReminderEnabledKey) private var longStationaryReminderEnabled = true
    @AppStorage(AppSettings.avatarHeadlightEnabledKey) private var avatarHeadlightEnabled = true

    @State private var showComingSoon = false
    @State private var comingSoonTitle = ""
    @State private var showGPXImporter = false
    @State private var gpxImportError: String?
    @State private var gpxImportPreview: GPXImportPreview?
    @State private var selectedGPXFileName: String?
    @State private var selectedImportCityKey: String = ""
    @State private var gpxImportProgress: Double = 0
    @State private var gpxImportProgressText: String = L10n.t("gpx_import_progress_idle")
    @State private var isParsingGPX = false
    @State private var isImportingGPX = false
    @StateObject private var privateTransfer = PrivateDataTransferManager()
    @State private var showTransferScanner = false
    @State private var displayNameDraft = ""
    @State private var displayNameInput = ""
    @State private var showDisplayNameEditor = false
    @State private var exclusiveIDDraft = ""
    @State private var accountEmail = ""
    @State private var profileVisibility: ProfileVisibility = ProfileSharingSettings.visibility
    @State private var accountMessage = ""
    @State private var showAccountMessage = false
    @State private var showAuthSheet = false
    @State private var authSheetMode: AuthEntryMode = .signIn

    private var appearance: MapAppearanceStyle {
        get { MapAppearanceStyle(rawValue: mapAppearanceRaw) ?? .dark }
        nonmutating set { mapAppearanceRaw = newValue.rawValue }
    }

    private var accountValue: String {
        if let userID = sessionStore.accountUserID, !userID.isEmpty {
            return userID
        }
        return "游客模式"
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "V\(version)"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    accountSection
                    mapAppearanceSection
                    trackingAssistSection
                    generalSection
                    levelRulesSection
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
                Button(L10n.t("ok"), role: .cancel) {}
            } message: {
                Text(String(format: L10n.t("coming_soon_message"), comingSoonTitle))
            }
            .alert("提示", isPresented: $showAccountMessage) {
                Button("好", role: .cancel) {}
            } message: {
                Text(accountMessage)
            }
            .task {
                await refreshAccountIfPossible()
            }
            .sheet(isPresented: $showDisplayNameEditor) {
                displayNameEditorSheet
            }
            .sheet(isPresented: $showAuthSheet) {
                AuthEntryView(
                    onContinueGuest: { showAuthSheet = false },
                    initialMode: authSheetMode,
                    onAuthenticated: {
                        Task { await refreshAccountIfPossible() }
                        showAuthSheet = false
                    }
                )
                .environmentObject(sessionStore)
            }
        }
    }

    private var settingsHeader: some View {
        HStack {
            Color.clear
                .frame(width: 42, height: 42)

            Spacer()

            Text(L10n.t("settings_title"))
                .appHeaderStyle()
                .foregroundColor(FigmaTheme.text)

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
                Text(L10n.t("settings_map_appearance_desc"))
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
                        Text(L10n.t("settings_voice_broadcast_title"))
                            .font(.system(size: 30 / 2, weight: .bold))
                            .foregroundColor(FigmaTheme.text)

                        Text(L10n.t("settings_voice_broadcast_desc"))
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
                        Text(L10n.t("settings_stationary_reminder_title"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(FigmaTheme.text)

                        Text(L10n.t("settings_stationary_reminder_desc"))
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

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("settings_avatar_headlight_title"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(FigmaTheme.text)

                        Text(L10n.t("settings_avatar_headlight_desc"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(FigmaTheme.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    figmaToggle(isOn: $avatarHeadlightEnabled)
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
                NavigationLink {
                    gpxImportEntryView
                } label: {
                    settingsRowLabel(title: "IMPORT GPX", icon: "map", iconColor: FigmaTheme.primary)
                }
                .buttonStyle(.plain)

                settingsRow(title: "NOTIFICATIONS", icon: "bell", iconColor: FigmaTheme.secondary) {
                    showPlaceholder("Notifications")
                }

                NavigationLink {
                    DebugChinaTestModule()
                        .navigationTitle(L10n.t("debug_tools_title"))
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
                accountInfoCard

                NavigationLink {
                    privateTransferView
                } label: {
                    settingsRowLabel(title: "PRIVATE DATA TRANSFER", icon: "qrcode.viewfinder", iconColor: FigmaTheme.primary)
                }
                .buttonStyle(.plain)

                if !sessionStore.isLoggedIn {
                    settingsRow(title: "LOGIN", icon: "person.badge.key.fill", iconColor: FigmaTheme.primary) {
                        authSheetMode = .signIn
                        showAuthSheet = true
                    }
                }

                settingsRow(title: "SUBSCRIPTION", icon: "creditcard", iconColor: FigmaTheme.primary) {
                    showPlaceholder("Subscription")
                }
            }
        }
    }

    private var accountInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            accountInfoRow(title: "账号", value: accountValue)

            HStack(alignment: .center, spacing: 8) {
                Text("昵称")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)

                Spacer(minLength: 8)

                Text(displayNameDraft.isEmpty ? "Explorer" : displayNameDraft)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button {
                    displayNameInput = displayNameDraft
                    showDisplayNameEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)
                        .frame(width: 24, height: 24)
                        .background(FigmaTheme.mutedBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!sessionStore.isLoggedIn)
                .opacity(sessionStore.isLoggedIn ? 1 : 0.45)
            }

            accountInfoRow(title: "专属ID", value: exclusiveIDDraft.isEmpty ? "--" : exclusiveIDDraft)
            accountInfoRow(title: "邮箱", value: accountEmail.isEmpty ? "未绑定" : accountEmail)

            Divider().overlay(Color.black.opacity(0.08))

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile 可见性")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                    Text("好友可见")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                }

                Spacer(minLength: 8)

                figmaToggle(isOn: Binding(
                    get: { profileVisibility != .private },
                    set: { newValue in
                        let previousVisibility = profileVisibility
                        let newVisibility: ProfileVisibility = newValue ? .friendsOnly : .private
                        guard profileVisibility != newVisibility else { return }
                        profileVisibility = newVisibility
                        Task { await updateVisibility(previous: previousVisibility) }
                    }
                ))
                .disabled(!sessionStore.isLoggedIn)
                .opacity(sessionStore.isLoggedIn ? 1 : 0.45)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .figmaSurfaceCard(radius: 30)
    }

    private var displayNameEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("编辑昵称")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                TextField("昵称（可重复）", text: $displayNameInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .semibold))

                Text("支持 1-24 个字符")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)

                Spacer(minLength: 0)
            }
            .padding(18)
            .background(FigmaTheme.mutedBackground.ignoresSafeArea())
            .navigationTitle("修改昵称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showDisplayNameEditor = false
                        displayNameInput = displayNameDraft
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await updateDisplayName(to: displayNameInput) }
                    }
                    .disabled(!sessionStore.isLoggedIn)
                }
            }
        }
    }

    private func accountInfoRow(title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(FigmaTheme.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var levelRulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("LEVEL RULES")

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("settings_level_rules_intro"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)

                Text("• \(L10n.t("settings_level_rules_1"))")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(FigmaTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                Text("• \(L10n.t("settings_level_rules_2"))")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(FigmaTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                Text("• \(L10n.t("settings_level_rules_3"))")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(FigmaTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                Text("• \(L10n.t("settings_level_rules_4"))")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(FigmaTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .figmaSurfaceCard(radius: 30)
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

    private var privateTransferView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("私密数据迁移")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(FigmaTheme.text)

                    Text("公开 Journey 建议登录后从云端恢复；此处仅迁移本地私密 Journey / Memory 图片与 Lifelog。两台设备保持在同一 Wi-Fi。")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(FigmaTheme.subtext)
                }
                .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 12) {
                    Text("旧设备（导出）")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.76))

                    Text(privateTransfer.hostingHintText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(FigmaTheme.subtext)
                        .fixedSize(horizontal: false, vertical: true)

                    if let qr = privateTransfer.hostingQRCode {
                        HStack {
                            Spacer()
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 220, height: 220)
                                .padding(10)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Spacer()
                        }
                    }

                    if privateTransfer.isHosting {
                        Button {
                            privateTransfer.stopHosting()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "stop.circle")
                                Text("停止导出")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.red.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            Task {
                                await privateTransfer.startHosting(currentUserID: sessionStore.currentUserID)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode")
                                Text("生成扫码迁移二维码")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(FigmaTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(privateTransfer.isBusy)
                        .opacity(privateTransfer.isBusy ? 0.6 : 1)
                    }
                }
                .padding(16)
                .figmaSurfaceCard(radius: 22)

                VStack(alignment: .leading, spacing: 12) {
                    Text("新设备（导入）")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.76))

                    Text(privateTransfer.importStatusText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(FigmaTheme.subtext)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showTransferScanner = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                            Text("扫码并导入")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(FigmaTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(privateTransfer.isBusy || privateTransfer.isImporting)
                    .opacity((privateTransfer.isBusy || privateTransfer.isImporting) ? 0.6 : 1)
                }
                .padding(16)
                .figmaSurfaceCard(radius: 22)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(FigmaTheme.mutedBackground.ignoresSafeArea())
        .navigationTitle("设备迁移")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTransferScanner) {
            QRCodeScannerSheet(
                onFound: { payload in
                    showTransferScanner = false
                    Task {
                        await privateTransfer.importFromQRCodePayload(
                            payload,
                            currentUserID: sessionStore.currentUserID,
                            journeyStore: journeyStore,
                            cityCache: cityCache,
                            lifelogStore: lifelogStore
                        )
                    }
                },
                onCancel: {
                    showTransferScanner = false
                }
            )
        }
        .alert("迁移提示", isPresented: Binding(
            get: { privateTransfer.alertMessage != nil },
            set: { if !$0 { privateTransfer.alertMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(privateTransfer.alertMessage ?? "")
        }
        .onDisappear {
            privateTransfer.stopHosting()
        }
    }

    private var gpxImportEntryView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("gpx_import_entry_title"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(FigmaTheme.text)

                    Text(L10n.t("gpx_import_entry_desc"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(FigmaTheme.subtext)
                }
                .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("gpx_import_upload_block_title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.76))

                    if let selectedGPXFileName {
                        Text(String(format: L10n.t("gpx_import_selected_file"), selectedGPXFileName))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(FigmaTheme.subtext)
                            .lineLimit(2)
                    }

                    Button {
                        showGPXImporter = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                            Text(L10n.t("gpx_import_select_file"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(FigmaTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .figmaSurfaceCard(radius: 22)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("gpx_import_conversion_progress"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.76))

                    Text(gpxImportProgressText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(FigmaTheme.subtext)
                        .lineLimit(2)

                    ProgressView(value: gpxImportProgress, total: 1)
                        .tint(FigmaTheme.primary)

                    Text("\(Int((gpxImportProgress * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.5))
                }
                .padding(16)
                .figmaSurfaceCard(radius: 22)
                .opacity(isParsingGPX || gpxImportProgress > 0 ? 1 : 0.72)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(FigmaTheme.mutedBackground.ignoresSafeArea())
        .navigationTitle(L10n.t("import_gpx_title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Import Failed", isPresented: Binding(
            get: { gpxImportError != nil },
            set: { if !$0 { gpxImportError = nil } }
        )) {
            Button(L10n.t("ok"), role: .cancel) {}
        } message: {
            Text(gpxImportError ?? "")
        }
        .fileImporter(
            isPresented: $showGPXImporter,
            allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml],
            allowsMultipleSelection: false
        ) { result in
            handleGPXFileSelection(result)
        }
        .sheet(item: $gpxImportPreview) { preview in
            gpxImportSheet(preview)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FigmaTheme.text)
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
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(FigmaTheme.text.opacity(0.42))
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FigmaTheme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(FigmaTheme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(FigmaTheme.mutedBackground)
                    )
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.text.opacity(0.46))
        }
        .padding(.horizontal, 20)
        .frame(minHeight: rowHeight)
        .figmaSurfaceCard(radius: 34)
    }

    private func showPlaceholder(_ title: String) {
        comingSoonTitle = title
        showComingSoon = true
    }

    private func refreshAccountIfPossible() async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else {
            displayNameDraft = UserDefaults.standard.string(forKey: "streetstamps.profile.displayName") ?? "Explorer"
            displayNameInput = displayNameDraft
            accountEmail = sessionStore.currentEmail ?? ""
            profileVisibility = ProfileSharingSettings.visibility
            return
        }
        do {
            let me = try await BackendAPIClient.shared.fetchMyProfile(token: token)
            displayNameDraft = me.displayName
            displayNameInput = displayNameDraft
            exclusiveIDDraft = me.resolvedExclusiveID ?? ""
            accountEmail = me.email ?? sessionStore.currentEmail ?? ""
            if let pv = me.profileVisibility {
                profileVisibility = pv
                ProfileSharingSettings.visibility = pv
            } else {
                profileVisibility = .friendsOnly
            }
        } catch {
            toastAccount("获取账号信息失败：\(error.localizedDescription)")
        }
    }

    private func updateDisplayName(to input: String) async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return toastAccount("昵称不能为空")
        }
        do {
            _ = try await BackendAPIClient.shared.updateDisplayName(token: token, displayName: value)
            displayNameDraft = value
            displayNameInput = value
            showDisplayNameEditor = false
            toastAccount("昵称已更新")
        } catch {
            toastAccount("更新失败：\(error.localizedDescription)")
        }
    }

    private func updateVisibility(previous: ProfileVisibility) async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        do {
            _ = try await BackendAPIClient.shared.updateProfileVisibility(token: token, visibility: profileVisibility)
            ProfileSharingSettings.visibility = profileVisibility
        } catch {
            profileVisibility = previous
            toastAccount("更新失败：\(error.localizedDescription)")
        }
    }

    private func toastAccount(_ text: String) {
        accountMessage = text
        showAccountMessage = true
    }

    private func handleGPXFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                return
            }
            gpxImportError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await parseSelectedGPXFile(url)
            }
        }
    }

    @MainActor
    private func parseSelectedGPXFile(_ url: URL) async {
        selectedGPXFileName = url.lastPathComponent
        gpxImportPreview = nil
        selectedImportCityKey = ""
        isParsingGPX = true
        gpxImportProgress = 0.02
        gpxImportProgressText = L10n.t("gpx_import_progress_reading")

        var didAccess = false
        if url.startAccessingSecurityScopedResource() {
            didAccess = true
        }
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
            isParsingGPX = false
        }

        do {
            let data = try Data(contentsOf: url)
            gpxImportProgress = 0.1
            let preview = try await GPXImportService.buildPreview(
                data: data,
                fileName: url.deletingPathExtension().lastPathComponent
            ) { progress, text in
                gpxImportProgress = progress
                gpxImportProgressText = text
            }
            gpxImportPreview = preview
            selectedImportCityKey = preview.defaultCityKey ?? preview.detectedCityCandidates.first?.cityKey ?? ""
            gpxImportProgress = 1
            gpxImportProgressText = L10n.t("gpx_import_progress_done")
        } catch {
            gpxImportProgress = 0
            gpxImportProgressText = L10n.t("gpx_import_progress_idle")
            gpxImportError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func gpxImportSheet(_ preview: GPXImportPreview) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(preview.fileName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                Text(String(format: L10n.t("gpx_import_points_distance"), preview.points.count, preview.distanceText))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(FigmaTheme.subtext)

                Text(L10n.t("gpx_import_choose_detected_city"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FigmaTheme.text.opacity(0.72))

                if preview.detectedCityCandidates.isEmpty {
                    Text(L10n.t("gpx_import_no_detected_city"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(FigmaTheme.subtext)
                        .padding(.vertical, 4)
                } else {
                    List {
                        ForEach(preview.detectedCityCandidates, id: \.cityKey) { option in
                            Button {
                                selectedImportCityKey = option.cityKey
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(FigmaTheme.text)
                                        if let iso2 = option.iso2, !iso2.isEmpty {
                                            Text(iso2.uppercased())
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(FigmaTheme.subtext)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: selectedImportCityKey == option.cityKey ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedImportCityKey == option.cityKey ? FigmaTheme.primary : .black.opacity(0.3))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }

                Button {
                    Task {
                        await confirmImportGPX(preview)
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isImportingGPX {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(L10n.t("import"))
                                .font(.system(size: 15, weight: .bold))
                        }
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(selectedImportCityKey.isEmpty ? Color.black.opacity(0.25) : FigmaTheme.primary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(selectedImportCityKey.isEmpty || isImportingGPX)
            }
            .padding(18)
            .background(FigmaTheme.mutedBackground.ignoresSafeArea())
            .navigationTitle(L10n.t("import_gpx_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("cancel")) {
                        gpxImportPreview = nil
                    }
                }
            }
        }
    }

    @MainActor
    private func confirmImportGPX(_ preview: GPXImportPreview) async {
        guard !selectedImportCityKey.isEmpty else { return }
        guard !isImportingGPX else { return }
        guard let selected = preview.detectedCityCandidates.first(where: { $0.cityKey == selectedImportCityKey }) else { return }

        isImportingGPX = true
        defer { isImportingGPX = false }

        var route = preview.route
        route.startCityKey = selected.cityKey
        route.endCityKey = selected.cityKey
        route.cityKey = selected.cityKey
        route.canonicalCity = selected.name
        route.currentCity = selected.name
        route.cityName = selected.name
        route.countryISO2 = selected.iso2
        route.exploreMode = .city
        route.ensureThumbnail(maxPoints: 280)

        journeyStore.addCompletedJourney(route)
        cityCache.rebuildFromJourneyStore()

        let lifelogTimeline = preview.points.enumerated().map { idx, point -> (coord: CoordinateCodable, timestamp: Date) in
            let ts = point.timestamp ?? GPXImportService.fallbackTimestamp(for: idx, total: preview.points.count, start: route.startTime, end: route.endTime)
            return (coord: point.coordinate, timestamp: ts)
        }
        lifelogStore.importExternalTrack(points: lifelogTimeline)

        gpxImportPreview = nil
    }
}

private struct GPXImportPoint: Identifiable {
    let id = UUID()
    let coordinate: CoordinateCodable
    let timestamp: Date?
}

private struct GPXImportCityCandidate: Identifiable {
    var id: String { cityKey }
    let cityKey: String
    let name: String
    let iso2: String?
}

private struct GPXImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let points: [GPXImportPoint]
    let route: JourneyRoute
    let distanceMeters: Double
    let detectedCityCandidates: [GPXImportCityCandidate]
    let defaultCityKey: String?

    var distanceText: String {
        if distanceMeters >= 1000 {
            return String(format: "%.2f km", distanceMeters / 1000)
        }
        return String(format: "%.0f m", distanceMeters)
    }
}

private enum GPXImportService {
    static func buildPreview(
        data: Data,
        fileName: String,
        progress: (@MainActor @Sendable (_ progress: Double, _ status: String) -> Void)? = nil
    ) async throws -> GPXImportPreview {
        await progress?(0.2, L10n.t("gpx_import_progress_parsing"))
        let parsed = try GPXXMLParser.parse(data: data)
        guard parsed.count >= 2 else {
            throw NSError(domain: "GPXImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "GPX 轨迹点不足（至少需要 2 个点）。"])
        }

        await progress?(0.45, L10n.t("gpx_import_progress_building"))
        let coords = parsed.map(\.coordinate)
        let points = parsed.map { GPXImportPoint(coordinate: $0.coordinate, timestamp: $0.timestamp) }
        let distance = totalDistanceMeters(coords: coords)
        let start = parsed.first?.timestamp ?? Date()
        let end = parsed.last?.timestamp ?? start
        await progress?(0.55, L10n.t("gpx_import_progress_detecting"))
        let cityCandidates = await detectCities(from: parsed) { done, total in
            guard total > 0 else { return }
            let fraction = Double(done) / Double(total)
            let currentProgress = min(0.95, 0.55 + fraction * 0.4)
            let text = String(format: L10n.t("gpx_import_progress_detecting_format"), done, total)
            await progress?(currentProgress, text)
        }
        let preferredCity = cityCandidates.first

        var route = JourneyRoute()
        route.id = UUID().uuidString
        route.startTime = start
        route.endTime = end
        route.distance = distance
        route.coordinates = coords
        route.thumbnailCoordinates = downsample(coords: coords, maxPoints: 280)
        route.trackingMode = .daily
        route.visibility = .private
        route.customTitle = fileName
        route.activityTag = "GPX Import"
        route.exploreMode = .city

        if let preferredCity {
            route.startCityKey = preferredCity.cityKey
            route.endCityKey = preferredCity.cityKey
            route.cityKey = preferredCity.cityKey
            route.canonicalCity = preferredCity.name
            route.currentCity = preferredCity.name
            route.cityName = preferredCity.name
            route.countryISO2 = preferredCity.iso2
        }

        await progress?(1, L10n.t("gpx_import_progress_done"))

        return GPXImportPreview(
            fileName: fileName,
            points: points,
            route: route,
            distanceMeters: distance,
            detectedCityCandidates: cityCandidates,
            defaultCityKey: preferredCity?.cityKey
        )
    }

    static func fallbackTimestamp(for index: Int, total: Int, start: Date?, end: Date?) -> Date {
        guard total > 1 else { return end ?? start ?? Date() }
        let startValue = start ?? end ?? Date()
        let endValue = end ?? startValue
        let span = max(0, endValue.timeIntervalSince(startValue))
        guard span > 0 else { return endValue }
        let t = Double(index) / Double(max(total - 1, 1))
        return startValue.addingTimeInterval(span * t)
    }

    private static func detectCities(
        from points: [GPXRawPoint],
        progress: (@Sendable (_ done: Int, _ total: Int) async -> Void)? = nil
    ) async -> [GPXImportCityCandidate] {
        let sample = sampledPoints(points, maxSamples: 5)
        var out: [GPXImportCityCandidate] = []
        var seen = Set<String>()

        if sample.isEmpty {
            await progress?(0, 0)
            return out
        }

        for (idx, point) in sample.enumerated() {
            let location = CLLocation(latitude: point.coordinate.lat, longitude: point.coordinate.lon)
            let result = await canonicalResultWithRetry(for: location, retryCount: 1)
            if let result, !seen.contains(result.cityKey) {
                seen.insert(result.cityKey)
                out.append(
                    GPXImportCityCandidate(
                        cityKey: result.cityKey,
                        name: result.cityName,
                        iso2: result.iso2
                    )
                )
            }
            await progress?(idx + 1, sample.count)
        }
        await progress?(sample.count, sample.count)
        return out
    }

    private static func canonicalResultWithRetry(for location: CLLocation, retryCount: Int) async -> ReverseGeocodeService.CanonicalResult? {
        if let value = await ReverseGeocodeService.shared.canonical(for: location) {
            return value
        }
        guard retryCount > 0 else { return nil }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        return await canonicalResultWithRetry(for: location, retryCount: retryCount - 1)
    }

    private static func sampledPoints(_ points: [GPXRawPoint], maxSamples: Int) -> [GPXRawPoint] {
        guard points.count > maxSamples else { return points }
        guard maxSamples > 1 else { return [points[0]] }

        var out: [GPXRawPoint] = []
        out.reserveCapacity(maxSamples)
        for idx in 0..<maxSamples {
            let t = Double(idx) / Double(maxSamples - 1)
            let raw = Int((t * Double(points.count - 1)).rounded(.toNearestOrAwayFromZero))
            out.append(points[min(max(raw, 0), points.count - 1)])
        }
        return out
    }

    private static func downsample(coords: [CoordinateCodable], maxPoints: Int) -> [CoordinateCodable] {
        guard coords.count > maxPoints, maxPoints >= 2 else { return coords }
        let n = coords.count
        let m = maxPoints
        var out: [CoordinateCodable] = []
        out.reserveCapacity(m)
        for i in 0..<m {
            let t = Double(i) / Double(m - 1)
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            out.append(coords[min(max(idx, 0), n - 1)])
        }
        return out
    }

    private static func totalDistanceMeters(coords: [CoordinateCodable]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].lat, longitude: coords[i - 1].lon)
            let b = CLLocation(latitude: coords[i].lat, longitude: coords[i].lon)
            total += b.distance(from: a)
        }
        return total
    }
}

private struct GPXRawPoint {
    let coordinate: CoordinateCodable
    let timestamp: Date?
}

private enum GPXXMLParser {
    static func parse(data: Data) throws -> [GPXRawPoint] {
        let parser = XMLParser(data: data)
        let delegate = GPXXMLParserDelegate()
        parser.delegate = delegate
        let success = parser.parse()
        if success {
            return delegate.points
        }
        let message = parser.parserError?.localizedDescription ?? "Unknown parse error"
        throw NSError(domain: "GPXImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "GPX 解析失败：\(message)"])
    }
}

private final class GPXXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var points: [GPXRawPoint] = []

    private var currentLat: Double?
    private var currentLon: Double?
    private var currentTime: Date?
    private var currentText = ""
    private var readingTime = false

    private lazy var iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let lower = elementName.lowercased()
        if lower == "trkpt" || lower == "rtept" {
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentTime = nil
        } else if lower == "time" {
            currentText = ""
            readingTime = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingTime {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let lower = elementName.lowercased()
        if lower == "time" {
            let raw = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            currentTime = parseDate(raw)
            readingTime = false
            currentText = ""
            return
        }

        if lower == "trkpt" || lower == "rtept" {
            defer {
                currentLat = nil
                currentLon = nil
                currentTime = nil
            }
            guard let lat = currentLat, let lon = currentLon else { return }
            guard abs(lat) <= 90, abs(lon) <= 180 else { return }
            points.append(
                GPXRawPoint(
                    coordinate: CoordinateCodable(lat: lat, lon: lon),
                    timestamp: currentTime
                )
            )
        }
    }

    private func parseDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        if let value = iso8601.date(from: raw) {
            return value
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }
}

private struct PrivateTransferQRCodePayload: Codable {
    let version: Int
    let host: String
    let port: Int
    let token: String
    let fileName: String
    let fileSize: Int64
    let createdAt: String
}

private struct PrivateTransferArchive: Codable {
    let version: Int
    let files: [PrivateTransferArchiveFile]
}

private struct PrivateTransferArchiveFile: Codable {
    let relativePath: String
    let data: Data
    let modifiedAt: Date?
}

private enum PrivateTransferError: LocalizedError {
    case sourceMissing
    case noPrivateData
    case packageEncodeFailed
    case packageDecodeFailed
    case serverStartFailed
    case localIPUnavailable
    case invalidPayload
    case invalidResponse
    case importSourceNotFound

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            return "未找到本地私密数据目录。"
        case .noPrivateData:
            return "当前没有可迁移的私密 Journey 或 Lifelog 数据。"
        case .packageEncodeFailed:
            return "私密数据打包失败。"
        case .packageDecodeFailed:
            return "私密数据包解析失败。"
        case .serverStartFailed:
            return "本地迁移服务启动失败。"
        case .localIPUnavailable:
            return "无法获取本机局域网地址，请确认已连接 Wi-Fi。"
        case .invalidPayload:
            return "二维码内容无效。"
        case .invalidResponse:
            return "旧设备返回异常。"
        case .importSourceNotFound:
            return "导入包内容不完整。"
        }
    }
}

@MainActor
private final class PrivateDataTransferManager: ObservableObject {
    @Published var hostingQRCode: UIImage?
    @Published var alertMessage: String?
    @Published var isHosting = false
    @Published var isImporting = false
    @Published var isBusy = false
    @Published private(set) var hostingHintText: String = "点击生成二维码后，保持此页面常亮，等待新设备扫码。"
    @Published private(set) var importStatusText: String = "点击“扫码并导入”，扫描旧设备上的二维码。"

    private struct HostedSession {
        let server: PrivateDataTransferHTTPServer
        let stagingDirectory: URL
    }

    private struct PrivateExportSummary {
        let privateJourneyCount: Int
        let privatePhotoCount: Int
        let includesLifelog: Bool
    }

    private var hostedSession: HostedSession?

    func startHosting(currentUserID: String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        stopHosting(clearAlert: true)

        do {
            let sourceRoot = StoragePath(userID: currentUserID).userRoot
            guard FileManager.default.fileExists(atPath: sourceRoot.path) else {
                throw PrivateTransferError.sourceMissing
            }

            hostingHintText = "正在准备私密数据包…"

            let staged = try await Task.detached(priority: .userInitiated) {
                try Self.makeHostedArchive(from: sourceRoot)
            }.value

            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            let server = PrivateDataTransferHTTPServer(fileURL: staged.packageURL, token: token)
            let port = try await server.start()

            guard let host = PrivateDataTransferHTTPServer.preferredLocalIPv4Address() else {
                server.stop()
                throw PrivateTransferError.localIPUnavailable
            }

            let attrs = try FileManager.default.attributesOfItem(atPath: staged.packageURL.path)
            let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let payload = PrivateTransferQRCodePayload(
                version: 1,
                host: host,
                port: Int(port),
                token: token,
                fileName: staged.packageURL.lastPathComponent,
                fileSize: fileSize,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            let payloadData = try JSONEncoder().encode(payload)
            guard let payloadText = String(data: payloadData, encoding: .utf8),
                  let qr = Self.generateQRCode(from: payloadText) else {
                server.stop()
                throw PrivateTransferError.serverStartFailed
            }

            hostedSession = HostedSession(server: server, stagingDirectory: staged.stagingDirectory)
            hostingQRCode = qr
            isHosting = true
            let lifelogText = staged.summary.includesLifelog ? "，含 Lifelog" : ""
            hostingHintText = "二维码已生成（\(Self.prettySize(fileSize))，私密 Journey \(staged.summary.privateJourneyCount) 条，照片 \(staged.summary.privatePhotoCount) 张\(lifelogText)）。请在新设备扫码并保持两台设备处于同一 Wi-Fi。"
        } catch {
            stopHosting(clearAlert: true)
            alertMessage = error.localizedDescription
        }
    }

    func stopHosting() {
        stopHosting(clearAlert: false)
    }

    func importFromQRCodePayload(
        _ payloadText: String,
        currentUserID: String,
        journeyStore: JourneyStore,
        cityCache: CityCache,
        lifelogStore: LifelogStore
    ) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            let payload = try Self.parsePayload(payloadText)
            importStatusText = "正在连接旧设备…"

            var components = URLComponents()
            components.scheme = "http"
            components.host = payload.host
            components.port = payload.port
            components.path = "/download"
            components.queryItems = [URLQueryItem(name: "token", value: payload.token)]
            guard let url = components.url else {
                throw PrivateTransferError.invalidPayload
            }

            importStatusText = "正在下载私密数据包…"
            let (downloadURL, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw PrivateTransferError.invalidResponse
            }

            importStatusText = "正在导入私密数据包…"
            let recoverResult = try await Task.detached(priority: .userInitiated) {
                try Self.importArchive(
                    downloadURL: downloadURL,
                    currentUserID: currentUserID
                )
            }.value

            importStatusText = "正在刷新本地数据…"
            journeyStore.load()
            cityCache.rebuildFromJourneyStore()
            lifelogStore.load()

            importStatusText = "导入完成。"
            alertMessage = "导入完成：新增 Journey \(recoverResult.mergedJourneyCount) 条，照片 \(recoverResult.copiedPhotos) 个，Lifelog \(recoverResult.replacedLifelog ? "已替换为更完整版本" : "无需替换")。"
        } catch {
            importStatusText = "导入失败。"
            alertMessage = error.localizedDescription
        }
    }

    private func stopHosting(clearAlert: Bool) {
        hostedSession?.server.stop()
        if let staging = hostedSession?.stagingDirectory {
            try? FileManager.default.removeItem(at: staging)
        }
        hostedSession = nil
        hostingQRCode = nil
        isHosting = false
        hostingHintText = "点击生成二维码后，保持此页面常亮，等待新设备扫码。"
        if clearAlert {
            alertMessage = nil
        }
    }

    nonisolated private static func makeHostedArchive(from sourceRoot: URL) throws -> (stagingDirectory: URL, packageURL: URL, summary: PrivateExportSummary) {
        let fm = FileManager.default
        let stagingDirectory = fm.temporaryDirectory.appendingPathComponent("ss-private-transfer-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let packageURL = stagingDirectory.appendingPathComponent("streetstamps-private-backup.sspkg")

        let plan = try buildPrivateExportPlan(from: sourceRoot, fileManager: fm)
        let files = try collectArchiveFiles(from: sourceRoot, allowedRelativePaths: plan.allowedRelativePaths, fileManager: fm)
        guard !files.isEmpty else {
            throw PrivateTransferError.noPrivateData
        }
        let archive = PrivateTransferArchive(version: 1, files: files)
        do {
            let data = try JSONEncoder().encode(archive)
            try data.write(to: packageURL, options: .atomic)
        } catch {
            throw PrivateTransferError.packageEncodeFailed
        }
        return (stagingDirectory, packageURL, plan.summary)
    }

    nonisolated private static func parsePayload(_ text: String) throws -> PrivateTransferQRCodePayload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw PrivateTransferError.invalidPayload
        }
        guard let payload = try? JSONDecoder().decode(PrivateTransferQRCodePayload.self, from: data),
              payload.version == 1,
              !payload.host.isEmpty,
              payload.port > 0,
              !payload.token.isEmpty else {
            throw PrivateTransferError.invalidPayload
        }
        return payload
    }

    nonisolated private static func importArchive(downloadURL: URL, currentUserID: String) throws -> GuestRecoveryResult {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("ss-private-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let packageURL = workDir.appendingPathComponent("import.sspkg")
        if fm.fileExists(atPath: packageURL.path) {
            try fm.removeItem(at: packageURL)
        }
        do {
            try fm.moveItem(at: downloadURL, to: packageURL)
        } catch {
            try fm.copyItem(at: downloadURL, to: packageURL)
        }

        let archiveData = try Data(contentsOf: packageURL)
        guard let archive = try? JSONDecoder().decode(PrivateTransferArchive.self, from: archiveData),
              archive.version == 1 else {
            throw PrivateTransferError.packageDecodeFailed
        }

        let importSourceID = "transfer_import_\(UUID().uuidString.lowercased())"
        let sourcePaths = StoragePath(userID: importSourceID)
        let targetPaths = StoragePath(userID: currentUserID)
        try sourcePaths.ensureBaseDirectoriesExist()
        try targetPaths.ensureBaseDirectoriesExist()
        defer { try? fm.removeItem(at: sourcePaths.userRoot) }

        let wroteFiles = try writeArchive(archive, to: sourcePaths.userRoot, fileManager: fm)
        guard wroteFiles > 0 else {
            throw PrivateTransferError.importSourceNotFound
        }
        return try GuestDataRecoveryService.recover(from: importSourceID, to: currentUserID)
    }

    nonisolated private static func collectArchiveFiles(from root: URL, allowedRelativePaths: [String], fileManager fm: FileManager) throws -> [PrivateTransferArchiveFile] {
        var files: [PrivateTransferArchiveFile] = []
        files.reserveCapacity(allowedRelativePaths.count)

        for relativePath in allowedRelativePaths {
            guard isAllowedRelativePath(relativePath) else { continue }
            let absoluteURL = root.appendingPathComponent(relativePath, isDirectory: false)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: absoluteURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let data = try Data(contentsOf: absoluteURL)
            let attrs = try? fm.attributesOfItem(atPath: absoluteURL.path)
            let modifiedAt = attrs?[.modificationDate] as? Date
            files.append(PrivateTransferArchiveFile(relativePath: relativePath, data: data, modifiedAt: modifiedAt))
        }

        files.sort { $0.relativePath < $1.relativePath }
        return files
    }

    nonisolated private static func buildPrivateExportPlan(from sourceRoot: URL, fileManager fm: FileManager) throws -> (allowedRelativePaths: [String], summary: PrivateExportSummary) {
        let journeysDir = sourceRoot.appendingPathComponent("Journeys", isDirectory: true)
        let photosDir = sourceRoot.appendingPathComponent("Photos", isDirectory: true)
        let lifelogURL = sourceRoot
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("lifelog_route.json", isDirectory: false)

        var journeyIDs = Set<String>()
        var memoryPhotoNames = Set<String>()

        if fm.fileExists(atPath: journeysDir.path),
           let files = try? fm.contentsOfDirectory(at: journeysDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            let candidateIDs = files.compactMap { url -> String? in
                let name = url.lastPathComponent
                return privateJourneyID(fromFileName: name)
            }

            for id in Set(candidateIDs) {
                guard let route = loadJourneyRoute(id: id, journeysDir: journeysDir),
                      route.visibility == .private else {
                    continue
                }
                journeyIDs.insert(id)
                for memory in route.memories {
                    for path in memory.imagePaths {
                        let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
                        if cleaned.isEmpty { continue }
                        memoryPhotoNames.insert(cleaned)
                    }
                }
            }
        }

        var allowedRelativePaths = Set<String>()
        for id in journeyIDs {
            let fileNames = [
                "\(id).json",
                "\(id).meta.json",
                "\(id).delta.jsonl"
            ]
            for fileName in fileNames {
                let url = journeysDir.appendingPathComponent(fileName, isDirectory: false)
                if fm.fileExists(atPath: url.path) {
                    allowedRelativePaths.insert("Journeys/\(fileName)")
                }
            }
        }

        var existingPhotos = 0
        for fileName in memoryPhotoNames {
            let url = photosDir.appendingPathComponent(fileName, isDirectory: false)
            if fm.fileExists(atPath: url.path) {
                allowedRelativePaths.insert("Photos/\(fileName)")
                existingPhotos += 1
            }
        }

        var includesLifelog = false
        if fm.fileExists(atPath: lifelogURL.path) {
            allowedRelativePaths.insert("Caches/lifelog_route.json")
            includesLifelog = true
        }

        let sortedPaths = allowedRelativePaths
            .filter { isAllowedRelativePath($0) }
            .sorted()
        let summary = PrivateExportSummary(
            privateJourneyCount: journeyIDs.count,
            privatePhotoCount: existingPhotos,
            includesLifelog: includesLifelog
        )
        return (sortedPaths, summary)
    }

    nonisolated private static func privateJourneyID(fromFileName name: String) -> String? {
        guard name != "index.json" else { return nil }
        if name.hasSuffix(".meta.json") {
            let raw = String(name.dropLast(".meta.json".count))
            return raw.isEmpty ? nil : raw
        }
        if name.hasSuffix(".delta.jsonl") {
            let raw = String(name.dropLast(".delta.jsonl".count))
            return raw.isEmpty ? nil : raw
        }
        if name.hasSuffix(".json") {
            let raw = String(name.dropLast(".json".count))
            return raw.isEmpty ? nil : raw
        }
        return nil
    }

    nonisolated private static func loadJourneyRoute(id: String, journeysDir: URL) -> JourneyRoute? {
        let fm = FileManager.default
        let full = journeysDir.appendingPathComponent("\(id).json")
        let meta = journeysDir.appendingPathComponent("\(id).meta.json")

        let candidateURL: URL? = {
            if fm.fileExists(atPath: full.path) { return full }
            if fm.fileExists(atPath: meta.path) { return meta }
            return nil
        }()
        guard let candidateURL,
              let data = try? Data(contentsOf: candidateURL),
              let route = try? JSONDecoder().decode(JourneyRoute.self, from: data) else {
            return nil
        }
        return route
    }

    nonisolated private static func writeArchive(_ archive: PrivateTransferArchive, to root: URL, fileManager fm: FileManager) throws -> Int {
        var wrote = 0
        for file in archive.files {
            guard isAllowedRelativePath(file.relativePath) else { continue }
            let destination = root.appendingPathComponent(file.relativePath, isDirectory: false)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: destination, options: .atomic)
            if let modifiedAt = file.modifiedAt {
                try? fm.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: destination.path)
            }
            wrote += 1
        }
        return wrote
    }

    nonisolated private static func isAllowedRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        if path.hasPrefix("/") { return false }
        if path.contains("..") { return false }
        return true
    }

    nonisolated private static func generateQRCode(from text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    nonisolated private static func prettySize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private final class PrivateDataTransferHTTPServer {
    private let fileURL: URL
    private let token: String
    private let queue = DispatchQueue(label: "streetstamps.private.transfer.server")
    private var listener: NWListener?

    init(fileURL: URL, token: String) {
        self.fileURL = fileURL
        self.token = token
    }

    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.sendError("500 Internal Server Error", on: connection, body: "server error: \(error.localizedDescription)")
                return
            }
            guard let data, let req = String(data: data, encoding: .utf8) else {
                self.sendError("400 Bad Request", on: connection, body: "bad request")
                return
            }
            self.respond(to: req, on: connection)
        }
    }

    private func respond(to request: String, on connection: NWConnection) {
        let line = request.components(separatedBy: "\r\n").first ?? ""
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else {
            sendError("400 Bad Request", on: connection, body: "bad request")
            return
        }

        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        guard method == "GET" else {
            sendError("405 Method Not Allowed", on: connection, body: "only GET supported")
            return
        }

        guard let components = URLComponents(string: "http://local\(target)"),
              let queryToken = components.queryItems?.first(where: { $0.name == "token" })?.value,
              queryToken == token else {
            sendError("401 Unauthorized", on: connection, body: "token mismatch")
            return
        }

        guard components.path == "/download" else {
            sendError("404 Not Found", on: connection, body: "not found")
            return
        }

        sendFile(on: connection)
    }

    private func sendFile(on connection: NWConnection) {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let header =
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: application/octet-stream\r\n" +
            "Content-Length: \(fileSize)\r\n" +
            "Connection: close\r\n\r\n"

        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            guard let handle = try? FileHandle(forReadingFrom: self.fileURL) else {
                self.sendError("500 Internal Server Error", on: connection, body: "file open failed")
                return
            }
            self.sendFileChunk(handle: handle, on: connection)
        })
    }

    private func sendFileChunk(handle: FileHandle, on connection: NWConnection) {
        do {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                try? handle.close()
                connection.send(content: nil, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
                guard self != nil else { return }
                if error != nil {
                    try? handle.close()
                    connection.cancel()
                    return
                }
                self?.sendFileChunk(handle: handle, on: connection)
            })
        } catch {
            try? handle.close()
            sendError("500 Internal Server Error", on: connection, body: "file read failed")
        }
    }

    private func sendError(_ status: String, on connection: NWConnection, body: String) {
        let data = Data(body.utf8)
        let header =
            "HTTP/1.1 \(status)\r\n" +
            "Content-Type: text/plain; charset=utf-8\r\n" +
            "Content-Length: \(data.count)\r\n" +
            "Connection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static func preferredLocalIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var pointer = ifaddr
        while let interface = pointer?.pointee {
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "bridge100" || name.hasPrefix("en") {
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let len = socklen_t(interface.ifa_addr.pointee.sa_len)
                    if getnameinfo(&addr, len, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        if let address, !address.isEmpty, address != "127.0.0.1" {
                            return address
                        }
                    }
                }
            }
            pointer = interface.ifa_next
        }
        return address
    }
}

private struct QRCodeScannerSheet: View {
    let onFound: (String) -> Void
    let onCancel: () -> Void
    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRCodeScannerRepresentable(
                    onFound: onFound,
                    onFailure: { scannerError = $0 }
                )
                .ignoresSafeArea()

                VStack(spacing: 8) {
                    Text("扫描旧设备显示的迁移二维码")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("请保持两台设备在同一 Wi-Fi 下")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, 32)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
            .alert("扫码失败", isPresented: Binding(
                get: { scannerError != nil },
                set: { if !$0 { scannerError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(scannerError ?? "")
            }
        }
    }
}

private struct QRCodeScannerRepresentable: UIViewControllerRepresentable {
    let onFound: (String) -> Void
    let onFailure: (String) -> Void

    final class Coordinator {
        var didEmit = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        let vc = QRCodeScannerViewController()
        vc.onCode = { code in
            guard !context.coordinator.didEmit else { return }
            context.coordinator.didEmit = true
            onFound(code)
        }
        vc.onFailure = { message in
            guard !context.coordinator.didEmit else { return }
            onFailure(message)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {}
}

private final class QRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didSetupSession = false
    private var didEmit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestPermissionAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func requestPermissionAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSessionIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureSessionIfNeeded()
                    } else {
                        self.onFailure?("未授予相机权限，无法扫码。")
                    }
                }
            }
        default:
            onFailure?("相机权限已关闭，请在系统设置中开启。")
        }
    }

    private func configureSessionIfNeeded() {
        guard !didSetupSession else { return }
        didSetupSession = true

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            onFailure?("无法访问摄像头。")
            return
        }

        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            session.commitConfiguration()
            onFailure?("相机输入初始化失败。")
            return
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        } else {
            session.commitConfiguration()
            onFailure?("扫码输出初始化失败。")
            return
        }
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        session.startRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didEmit else { return }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let text = object.stringValue,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        didEmit = true
        session.stopRunning()
        onCode?(text)
    }
}
