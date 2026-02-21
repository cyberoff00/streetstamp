import SwiftUI
import AuthenticationServices

struct AccountCenterView: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var socialStore: SocialGraphStore

    @State private var backendBaseURL = BackendConfig.baseURLString
    @State private var googleClientID = BackendConfig.googleIOSClientID

    @State private var email = ""
    @State private var password = ""

    @State private var myProfile: BackendProfileDTO?
    @State private var displayNameDraft = ""
    @State private var handleDraft = ""
    @State private var profileVisibility: ProfileVisibility = ProfileSharingSettings.visibility

    @State private var isLoading = false
    @State private var message = ""
    @State private var showMessage = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                backendCard
                authCard
                accountCard
                migrationCard
            }
            .padding(16)
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .navigationTitle("账户中心")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshMeIfPossible()
        }
        .alert("提示", isPresented: $showMessage) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    private var backendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("后端配置")
                .font(.system(size: 13, weight: .bold))

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

    private var authCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("登录 / 注册")
                .font(.system(size: 13, weight: .bold))

            TextField("邮箱", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled(true)
                .textFieldStyle(.roundedBorder)

            SecureField("密码（至少 8 位）", text: $password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button(isLoading ? "处理中..." : "邮箱登录") {
                    Task { await loginWithEmail() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)

                Button(isLoading ? "处理中..." : "邮箱注册") {
                    Task { await registerWithEmail() }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }

            HStack(spacing: 10) {
                Button(isLoading ? "处理中..." : "Google 登录") {
                    Task { await loginWithGoogle() }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                Button(isLoading ? "处理中..." : "Apple 登录") {
                    Task { await loginWithApple() }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
        }
        .cardStyle()
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("账号状态")
                .font(.system(size: 13, weight: .bold))

            Text("登录方式：\(sessionStore.currentProvider)")
                .font(.system(size: 12, weight: .semibold))
            Text("用户 ID：\(sessionStore.accountUserID ?? "guest")")
                .font(.system(size: 12, weight: .semibold))
                .textSelection(.enabled)

            if sessionStore.isLoggedIn {
                TextField("展示名称（可重复）", text: $displayNameDraft)
                    .textFieldStyle(.roundedBorder)
                TextField("Handle（唯一）", text: $handleDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)

                Picker("主页可见性", selection: $profileVisibility) {
                    ForEach(ProfileVisibility.allCases) { v in
                        Text(v.titleCN).tag(v)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Button("刷新资料") {
                        Task { await refreshMeIfPossible() }
                    }
                    .buttonStyle(.bordered)

                    Button("保存展示名称") {
                        Task { await updateDisplayName() }
                    }
                    .buttonStyle(.bordered)

                    Button("保存 Handle") {
                        Task { await updateHandle() }
                    }
                    .buttonStyle(.bordered)

                    Button("保存可见性") {
                        Task { await updateVisibility() }
                    }
                    .buttonStyle(.bordered)
                }

                Button("切回游客模式") {
                    sessionStore.logoutToGuest()
                    myProfile = nil
                    toast("已切回游客模式")
                }
                .buttonStyle(.bordered)
            }

            Text("说明：默认仅本地；公开/好友可见内容会进入云端同步。")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .cardStyle()
        .onChange(of: profileVisibility) { _, newValue in
            ProfileSharingSettings.visibility = newValue
        }
    }

    private var migrationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("迁移与同步")
                .font(.system(size: 13, weight: .bold))

            Button(isLoading ? "迁移中..." : "迁移本地旅程与记忆到云端") {
                Task { await migrateAll() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || !sessionStore.isLoggedIn)

            Text("迁移规则：private 保留本地；friendsOnly/public 上传云端。")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if !MigrationStatusStore.lastMessage().isEmpty {
                Text(MigrationStatusStore.lastMessage())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black.opacity(0.7))
            }
        }
        .cardStyle()
    }

    private func registerWithEmail() async {
        guard BackendConfig.isEnabled else { return toast("请先配置后端地址") }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, password.count >= 8 else {
            return toast("请输入有效邮箱和至少 8 位密码")
        }
        isLoading = true
        defer { isLoading = false }

        do {
            try await sessionStore.registerWithEmail(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            toast("注册并登录成功")
            await refreshMeIfPossible()
        } catch {
            toast("注册失败：\(error.localizedDescription)")
        }
    }

    private func loginWithEmail() async {
        guard BackendConfig.isEnabled else { return toast("请先配置后端地址") }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, password.count >= 8 else {
            return toast("请输入有效邮箱和至少 8 位密码")
        }
        isLoading = true
        defer { isLoading = false }

        do {
            try await sessionStore.loginWithEmail(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            toast("登录成功")
            await refreshMeIfPossible()
        } catch {
            toast("登录失败：\(error.localizedDescription)")
        }
    }

    private func loginWithGoogle() async {
        guard BackendConfig.isEnabled else { return toast("请先配置后端地址") }
        isLoading = true
        defer { isLoading = false }

        do {
            let token = try await GoogleSignInService.signIn()
            try await sessionStore.loginWithOAuth(provider: "google", idToken: token)
            toast("Google 登录成功")
            await refreshMeIfPossible()
        } catch {
            toast("Google 登录失败：\(error.localizedDescription)")
        }
    }

    private func loginWithApple() async {
        guard BackendConfig.isEnabled else { return toast("请先配置后端地址") }
        isLoading = true
        defer { isLoading = false }

        do {
            let token = try await AppleSignInService.signIn()
            try await sessionStore.loginWithOAuth(provider: "apple", idToken: token)
            toast("Apple 登录成功")
            await refreshMeIfPossible()
        } catch {
            toast("Apple 登录失败：\(error.localizedDescription)")
        }
    }

    private func refreshMeIfPossible() async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        do {
            let me = try await BackendAPIClient.shared.fetchMyProfile(token: token)
            myProfile = me
            displayNameDraft = me.displayName
            handleDraft = me.handle ?? ""
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
            return toast("展示名称不能为空")
        }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await BackendAPIClient.shared.updateDisplayName(token: token, displayName: displayNameDraft)
            toast("展示名称已更新")
            await refreshMeIfPossible()
        } catch {
            toast("更新失败：\(error.localizedDescription)")
        }
    }

    private func updateHandle() async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        let h = handleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return toast("Handle 不能为空") }
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await BackendAPIClient.shared.updateHandle(token: token, handle: h)
            toast("Handle 已更新")
            await refreshMeIfPossible()
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
            let msg = "迁移完成，已上传 \(report.uploadedJourneys) 条旅程，\(report.uploadedMemories) 条记忆（媒体 \(report.uploadedMediaFiles) 个），私密本地 \(report.localOnlyPrivateJourneys) 条"
            MigrationStatusStore.save(msg)
            await socialStore.reloadFromBackendIfPossible(accessToken: sessionStore.currentAccessToken)
            toast(msg)
        } catch {
            toast("迁移失败：\(error.localizedDescription)")
        }
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
