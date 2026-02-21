import SwiftUI
import AuthenticationServices

struct AccountCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var lifelogStore: LifelogStore
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
                        .font(.system(size: 14, weight: .black))
                }
                .foregroundColor(.black)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Account Center")
                .font(.system(size: 24, weight: .black))
                .foregroundColor(.black)

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
            .font(.system(size: 33 * 0.48, weight: .black))
            .foregroundColor(FigmaTheme.subtext)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sessionStore.isLoggedIn {
                Text(displayNameDraft.isEmpty ? "Explorer" : displayNameDraft)
                    .font(.system(size: 32 * 0.58, weight: .black))
                    .foregroundColor(.black)

                Group {
                    TextField("昵称（可重复）", text: $displayNameDraft)
                        .textFieldStyle(.roundedBorder)
                    TextField("handle（唯一）", text: $handleDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textFieldStyle(.roundedBorder)
                }
                .font(.system(size: 14, weight: .semibold))

                Picker("主页可见性", selection: $profileVisibility) {
                    ForEach(ProfileVisibility.allCases) { v in
                        Text(v.titleCN).tag(v)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    capsuleAction("保存昵称", filled: true) { Task { await updateDisplayName() } }
                    capsuleAction("保存 Handle", filled: false) { Task { await updateHandle() } }
                    capsuleAction("可见性", filled: false) { Task { await updateVisibility() } }
                }

                capsuleAction("退出登录", filled: false) {
                    sessionStore.logoutToGuest()
                    myProfile = nil
                    toast("已切回游客模式")
                }
            } else {
                Text("Guest Mode")
                    .font(.system(size: 32 * 0.58, weight: .black))
                    .foregroundColor(.black)

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
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.black)
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
                .font(.system(size: 14, weight: .black))
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

            Text("迁移规则：private 保留本地；friendsOnly/public 上传云端。Lifelog 不上传云端，仅支持本机/手动恢复。")
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

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("游客数据恢复")
                .font(.system(size: 13, weight: .bold))

            Text("用于找回旧 guest 目录里的旅程、笔记和照片。")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Text("当前用户：\(sessionStore.currentUserID)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Button(isLoading ? "扫描中..." : "扫描旧 guest") {
                    scanRecoveryCandidates()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                Button(isLoading ? "重跑中..." : "强制重跑迁移") {
                    Task { await forceReplayMigration() }
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }

            if recoveryCandidates.isEmpty {
                Text("未发现可恢复的旧 guest 数据。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                ForEach(recoveryCandidates) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.userID)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)

                        Text("旅程 \(item.journeyCount) · 笔记 \(item.memoryCount) · 照片 \(item.photoCount) · Lifelog点 \(item.lifelogPointCount)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        if !item.topCities.isEmpty {
                            Text("城市预览：\(item.topCities.joined(separator: "、"))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        if let dt = item.lastModified {
                            Text("最近更新时间：\(dt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Button(isLoading ? "恢复中..." : "恢复这个 guest 到当前用户") {
                            Task { await recoverGuestData(sourceUserID: item.userID) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
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

    private func recoverGuestData(sourceUserID: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try GuestDataRecoveryService.recover(
                from: sourceUserID,
                to: sessionStore.currentUserID
            )

            journeyStore.load()
            cityCache.loadFromDisk()
            cityCache.rebuildFromJourneyStore()
            lifelogStore.load()

            scanRecoveryCandidates()

            let msg = "恢复完成：新增旅程 \(result.mergedJourneyCount) 条，拷贝旅程文件 \(result.copiedJourneyFiles) 个，照片 \(result.copiedPhotos) 个，缩略图 \(result.copiedThumbnails) 个\(result.replacedLifelog ? "，并替换了 Lifelog" : "")"
            toast(msg)
        } catch {
            toast("恢复失败：\(error.localizedDescription)")
        }
    }

    private func forceReplayMigration() async {
        isLoading = true
        defer { isLoading = false }

        let report = sessionStore.forceReplayLegacyMigration()
        journeyStore.load()
        cityCache.loadFromDisk()
        cityCache.rebuildFromJourneyStore()
        lifelogStore.load()
        scanRecoveryCandidates()

        let ids = report.discoveredLegacyUserIDs.isEmpty
            ? "无"
            : report.discoveredLegacyUserIDs.joined(separator: ", ")
        toast("已强制重跑。移除 marker \(report.removedMarkers) 个；扫描到 legacy ID: \(ids)")
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
