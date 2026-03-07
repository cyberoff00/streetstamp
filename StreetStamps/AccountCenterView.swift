import SwiftUI

struct AccountCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: UserSessionStore

    @State private var backendBaseURL = BackendConfig.baseURLString
    @State private var displayNameDraft = ""
    @State private var displayNameInput = ""
    @State private var isEditingDisplayName = false
    @State private var exclusiveIDDraft = ""
    @State private var exclusiveIDInput = ""
    @State private var isEditingExclusiveID = false
    @State private var accountEmail = ""
    @State private var canChangeExclusiveID = true
    @State private var profileVisibility: ProfileVisibility = ProfileSharingSettings.visibility

    @State private var isLoading = false
    @State private var message = ""
    @State private var showMessage = false
    @State private var showLogoutConfirmation = false
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

                    if sessionStore.isLoggedIn {
                        sectionTitle("ACCOUNT ACTIONS")
                        logoutPanel
                    }

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
        }
        .alert("提示", isPresented: $showMessage) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message)
        }
        .alert(L10n.t("settings_logout_confirm_title"), isPresented: $showLogoutConfirmation) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("settings_logout"), role: .destructive) {
                sessionStore.logoutToGuest()
                accountEmail = ""
                exclusiveIDDraft = ""
                profileVisibility = ProfileSharingSettings.visibility
                toast("已切回游客模式")
                dismiss()
            }
        } message: {
            Text(L10n.t("settings_logout_confirm_message"))
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

                if isEditingDisplayName {
                    TextField("昵称（可重复）", text: $displayNameInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, weight: .semibold))

                    HStack(spacing: 8) {
                        capsuleAction("保存昵称", filled: true) {
                            Task { await updateDisplayName(to: displayNameInput) }
                        }
                        capsuleAction("取消", filled: false) {
                            isEditingDisplayName = false
                            displayNameInput = displayNameDraft
                        }
                    }
                } else {
                    capsuleAction("编辑昵称", filled: false) {
                        displayNameInput = displayNameDraft
                        isEditingDisplayName = true
                    }
                }

                if canChangeExclusiveID {
                    if isEditingExclusiveID {
                        TextField("专属ID（字母/数字/下划线）", text: $exclusiveIDInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, weight: .semibold))

                        Text("专属ID仅可修改一次，请谨慎设置")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(FigmaTheme.subtext)

                        HStack(spacing: 8) {
                            capsuleAction("保存专属ID", filled: true) {
                                Task { await updateExclusiveID(to: exclusiveIDInput) }
                            }
                            capsuleAction("取消", filled: false) {
                                isEditingExclusiveID = false
                                exclusiveIDInput = exclusiveIDDraft
                            }
                        }
                    } else {
                        capsuleAction("编辑专属ID", filled: false) {
                            exclusiveIDInput = exclusiveIDDraft
                            isEditingExclusiveID = true
                        }
                    }
                } else {
                    Text("专属ID已完成一次修改，无法再次更改")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext)
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
            Toggle(isOn: Binding(
                get: { profileVisibility != .private },
                set: { newValue in
                    let previousVisibility = profileVisibility
                    let newVisibility: ProfileVisibility = newValue ? .friendsOnly : .private
                    guard profileVisibility != newVisibility else { return }
                    profileVisibility = newVisibility
                    Task { await updateVisibility(previous: previousVisibility) }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("仅好友可见")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                    Text(profileVisibility == .private ? "当前：仅自己可见" : "当前：好友可见")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                }
            }
            .disabled(!sessionStore.isLoggedIn)
        }
        .cardStyle()
    }

    private var logoutPanel: some View {
        VStack(spacing: 0) {
            infoRow(
                icon: "rectangle.portrait.and.arrow.right",
                title: L10n.t("settings_logout"),
                subtitle: L10n.t("settings_logout_subtitle"),
                iconColor: .red.opacity(0.88),
                titleColor: .red.opacity(0.9),
                subtitleColor: .red.opacity(0.62)
            ) {
                showLogoutConfirmation = true
            }
        }
        .cardStyle()
    }

    private func infoRow(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color = FigmaTheme.primary,
        titleColor: Color = FigmaTheme.text,
        subtitleColor: Color = FigmaTheme.subtext,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(titleColor)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(subtitleColor)
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

            HStack(spacing: 10) {
                Button("保存后端地址") {
                    BackendConfig.baseURLString = backendBaseURL
                    toast("已保存后端地址")
                }
                .buttonStyle(.borderedProminent)
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
            displayNameInput = displayNameDraft
            exclusiveIDInput = exclusiveIDDraft
            isEditingDisplayName = false
            isEditingExclusiveID = false
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

    private func updateDisplayName(to input: String) async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return toast("昵称不能为空")
        }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await BackendAPIClient.shared.updateDisplayName(token: token, displayName: value)
            displayNameDraft = value
            displayNameInput = value
            isEditingDisplayName = false
            toast("昵称已更新")
        } catch {
            toast("更新失败：\(error.localizedDescription)")
        }
    }

    private func updateExclusiveID(to input: String) async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        guard canChangeExclusiveID else { return toast("专属ID已完成一次修改，无法再次更改") }

        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return toast("专属ID不能为空") }
        guard value.range(of: #"^[A-Za-z0-9_]{1,24}$"#, options: .regularExpression) != nil else {
            return toast("专属ID仅支持字母、数字、下划线")
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let updated = try await BackendAPIClient.shared.updateExclusiveID(token: token, exclusiveID: value)
            exclusiveIDDraft = updated.resolvedExclusiveID ?? value
            exclusiveIDInput = exclusiveIDDraft
            canChangeExclusiveID = updated.canChangeExclusiveID
            accountEmail = updated.email ?? sessionStore.currentEmail ?? accountEmail
            isEditingExclusiveID = false
            toast("专属ID已更新")
        } catch {
            toast("更新失败：\(error.localizedDescription)")
        }
    }

    private func updateVisibility(previous: ProfileVisibility) async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await BackendAPIClient.shared.updateProfileVisibility(token: token, visibility: profileVisibility)
            ProfileSharingSettings.visibility = profileVisibility
            toast("可见性已更新")
        } catch {
            profileVisibility = previous
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
