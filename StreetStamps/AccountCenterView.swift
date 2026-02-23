import SwiftUI

struct AccountCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var socialStore: SocialGraphStore

    @State private var backendBaseURL = BackendConfig.baseURLString
    @State private var googleClientID = BackendConfig.googleIOSClientID
    @State private var displayNameDraft = ""
    @State private var exclusiveIDDraft = ""
    @State private var accountEmail = ""
    @State private var canChangeExclusiveID = true
    @State private var profileVisibility: ProfileVisibility = ProfileSharingSettings.visibility

    @State private var isLoading = false
    @State private var message = ""
    @State private var showMessage = false
    @State private var recoveryCandidates: [GuestRecoveryCandidate] = []
    @State private var showAuthSheet = false
    @State private var authSheetMode: AuthEntryMode = .signIn

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("ACCOUNT")
                    accountPanel

                    sectionTitle("PROFILE VISIBILITY")
                    visibilityPanel

                    sectionTitle("DATA")
                    dataPanel

                    sectionTitle("SECURITY")
                    securityPanel

                    if !sessionStore.isLoggedIn {
                        sectionTitle("DEVELOPER")
                        backendCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .task {
            await refreshMeIfPossible()
            scanRecoveryCandidates()
        }
        .alert("提示", isPresented: $showMessage) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message)
        }
        .sheet(isPresented: $showAuthSheet) {
            AuthEntryView(
                onContinueGuest: { showAuthSheet = false },
                initialMode: authSheetMode,
                onAuthenticated: {
                    Task { await refreshMeIfPossible() }
                    showAuthSheet = false
                }
            )
            .environmentObject(sessionStore)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                    Text("BACK")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(FigmaTheme.text)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Account Center")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(FigmaTheme.text)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FigmaTheme.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 33 * 0.48, weight: .bold))
            .foregroundColor(FigmaTheme.subtext)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sessionStore.isLoggedIn {
                Text(displayNameDraft.isEmpty ? "Explorer" : displayNameDraft)
                    .font(.system(size: 32 * 0.58, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                accountInfoRow(label: "昵称", value: displayNameDraft.isEmpty ? "Explorer" : displayNameDraft)
                accountInfoRow(label: "专属ID", value: exclusiveIDDraft.isEmpty ? "--" : exclusiveIDDraft)
                accountInfoRow(label: "邮箱", value: accountEmail.isEmpty ? "未绑定" : accountEmail)

                Divider().overlay(Color.black.opacity(0.08))

                TextField("昵称（可重复）", text: $displayNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .semibold))

                TextField("专属ID（字母/数字/下划线）", text: $exclusiveIDDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .semibold))
                    .disabled(!canChangeExclusiveID)

                Text(canChangeExclusiveID ? "专属ID仅可修改一次，请谨慎设置" : "专属ID已完成一次修改，无法再次更改")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)

                HStack(spacing: 8) {
                    capsuleAction("保存昵称", filled: true) { Task { await updateDisplayName() } }
                    capsuleAction(canChangeExclusiveID ? "保存专属ID" : "专属ID已锁定", filled: false) {
                        Task { await updateExclusiveID() }
                    }
                    .disabled(!canChangeExclusiveID)
                }

                capsuleAction("退出登录", filled: false) {
                    sessionStore.logoutToGuest()
                    toast("已切回游客模式")
                }
            } else {
                Text("Guest Mode")
                    .font(.system(size: 32 * 0.58, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                Divider().overlay(Color.black.opacity(0.08))

                Text("Please login to access your account")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)

                capsuleAction("LOGIN", filled: true) {
                    authSheetMode = .signIn
                    showAuthSheet = true
                }
                capsuleAction("REGISTER", filled: false) {
                    authSheetMode = .register
                    showAuthSheet = true
                }
            }
        }
        .cardStyle()
    }

    private func accountInfoRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(FigmaTheme.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    private var visibilityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("主页可见性", selection: $profileVisibility) {
                ForEach(ProfileVisibility.frontendCases) { v in
                    Text(v.titleCN).tag(v)
                }
            }
            .pickerStyle(.segmented)

            capsuleAction("保存可见性", filled: false) {
                Task { await updateVisibility() }
            }
            .disabled(!sessionStore.isLoggedIn)
        }
        .cardStyle()
        .onChange(of: profileVisibility) { _, newValue in
            ProfileSharingSettings.visibility = newValue
        }
    }

    private var dataPanel: some View {
        VStack(spacing: 0) {
            infoRow(
                icon: "externaldrive",
                title: "Check Local Data Migration",
                subtitle: "Verify device Lifelog data migration"
            ) {
                scanRecoveryCandidates()
                if recoveryCandidates.isEmpty {
                    toast("未发现可恢复的本地数据")
                } else {
                    toast("发现 \(recoveryCandidates.count) 组可恢复本地数据")
                }
            }
            Divider().overlay(Color.black.opacity(0.08))
            infoRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Lifelog Device Transfer",
                subtitle: "Import/Export data to new device"
            ) {
                toast("Lifelog 不上云，请使用本地导入/导出手动迁移")
            }
            if sessionStore.isLoggedIn {
                Divider().overlay(Color.black.opacity(0.08))
                infoRow(
                    icon: "icloud.and.arrow.up",
                    title: "Sync Shareable Journeys",
                    subtitle: "Upload public/friendsOnly journeys and memories"
                ) {
                    Task { await migrateAll() }
                }
            }
        }
        .cardStyle()
    }

    private var securityPanel: some View {
        VStack(spacing: 0) {
            infoRow(
                icon: "key",
                title: "Change Password",
                subtitle: "Update account password"
            ) {
                toast("后端尚未提供改密接口，先保留此入口")
            }
        }
        .cardStyle()
    }

    private func infoRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FigmaTheme.primary)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    private func capsuleAction(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(filled ? .white : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(filled ? FigmaTheme.primary : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(filled ? 0 : 0.12), lineWidth: filled ? 0 : 2)
                )
        }
        .buttonStyle(.plain)
    }

    private var backendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("后端配置")
                .font(.system(size: 13, weight: .semibold))

            TextField("API_BASE_URL（例如 https://api.xxx.com）", text: $backendBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textFieldStyle(.roundedBorder)

            TextField("Google iOS Client ID（可选）", text: $googleClientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button("保存后端地址") {
                    BackendConfig.baseURLString = backendBaseURL
                    toast("已保存后端地址")
                }
                .buttonStyle(.borderedProminent)

                Button("保存 Google Client ID") {
                    BackendConfig.googleIOSClientID = googleClientID
                    toast("已保存 Google Client ID")
                }
                .buttonStyle(.bordered)
            }

            Text("当前地址：\(BackendConfig.baseURLString.isEmpty ? "未配置" : BackendConfig.baseURLString)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .cardStyle()
    }

    private func refreshMeIfPossible() async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        do {
            let me = try await BackendAPIClient.shared.fetchMyProfile(token: token)
            displayNameDraft = me.displayName
            exclusiveIDDraft = me.resolvedExclusiveID ?? ""
            accountEmail = me.email ?? sessionStore.currentEmail ?? ""
            canChangeExclusiveID = me.canChangeExclusiveID
            if let pv = me.profileVisibility {
                profileVisibility = pv
                ProfileSharingSettings.visibility = pv
            }
        } catch {
            toast("获取资料失败：\(error.localizedDescription)")
        }
    }

    private func updateDisplayName() async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        guard !displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return toast("昵称不能为空")
        }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await BackendAPIClient.shared.updateDisplayName(token: token, displayName: displayNameDraft)
            toast("昵称已更新")
            await refreshMeIfPossible()
        } catch {
            toast("更新失败：\(error.localizedDescription)")
        }
    }

    private func updateExclusiveID() async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        guard canChangeExclusiveID else { return toast("专属ID已完成一次修改，无法再次更改") }

        let value = exclusiveIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return toast("专属ID不能为空") }
        guard value.range(of: #"^[A-Za-z0-9_]{1,24}$"#, options: .regularExpression) != nil else {
            return toast("专属ID仅支持字母、数字、下划线")
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let updated = try await BackendAPIClient.shared.updateExclusiveID(token: token, exclusiveID: value)
            exclusiveIDDraft = updated.resolvedExclusiveID ?? value
            canChangeExclusiveID = updated.canChangeExclusiveID
            accountEmail = updated.email ?? sessionStore.currentEmail ?? accountEmail
            toast("专属ID已更新")
        } catch {
            toast("更新失败：\(error.localizedDescription)")
        }
    }

    private func migrateAll() async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else {
            return toast("请先登录账号")
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let report = try await JourneyCloudMigrationService.migrateAll(
                sessionStore: sessionStore,
                journeyStore: journeyStore,
                cityCache: cityCache
            )
            let msg = "迁移完成，已上传 \(report.uploadedJourneys) 条旅程，\(report.uploadedMemories) 条记忆（媒体 \(report.uploadedMediaFiles) 个），私密本地 \(report.localOnlyPrivateJourneys) 条。Lifelog 未上传云端。"
            MigrationStatusStore.save(msg)
            await socialStore.reloadFromBackendIfPossible(accessToken: sessionStore.currentAccessToken)
            toast(msg)
        } catch {
            toast("迁移失败：\(error.localizedDescription)")
        }
    }

    private func scanRecoveryCandidates() {
        recoveryCandidates = GuestDataRecoveryService.discoverCandidates(currentUserID: sessionStore.currentUserID)
    }

    private func updateVisibility() async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await BackendAPIClient.shared.updateProfileVisibility(token: token, visibility: profileVisibility)
            ProfileSharingSettings.visibility = profileVisibility
            toast("可见性已更新")
            await refreshMeIfPossible()
        } catch {
            toast("更新失败：\(error.localizedDescription)")
        }
    }

    private func toast(_ text: String) {
        message = text
        showMessage = true
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(FigmaTheme.border, lineWidth: 1)
            )
            .shadow(color: FigmaTheme.softShadow, radius: 18, x: 0, y: 8)
    }
}
