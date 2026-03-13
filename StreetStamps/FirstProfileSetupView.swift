import SwiftUI

struct FirstProfileSetupView: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @State private var nickname: String = ""
    @State private var loadout: RobotLoadout = AvatarLoadoutStore.load()
    @State private var showEquipmentEditor = false
    @State private var submitting = false
    @State private var errorMessage: String?

    private let accent = FigmaTheme.primary
    private let warm = FigmaTheme.secondary

    var body: some View {
        ZStack {
            gridBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    titleBlock
                    avatarCard
                    nicknameCard
                    actionsCard
                    confirmButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showEquipmentEditor) {
            NavigationStack {
                EquipmentView(loadout: $loadout)
            }
        }
        .alert(L10n.t("prompt"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button(L10n.t("ok"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if nickname.isEmpty {
                nickname = suggestedNickname
            }
        }
    }

    private var suggestedNickname: String {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.caseInsensitiveCompare("explorer") == .orderedSame { return "" }
        return trimmed
    }

    private var gridBackground: some View {
        ZStack {
            FigmaTheme.background

            GeometryReader { proxy in
                Path { path in
                    let spacing: CGFloat = 24
                    var x: CGFloat = 0
                    while x <= proxy.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        x += spacing
                    }

                    var y: CGFloat = 0
                    while y <= proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        y += spacing
                    }
                }
                .stroke(Color.black.opacity(0.03), lineWidth: 0.7)
            }
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text(L10n.t("profile_setup_title"))
                .appHeaderStyle()
                .multilineTextAlignment(.center)

            Text(L10n.t("profile_setup_subtitle"))
                .appBodyStrongStyle()
                .foregroundColor(FigmaTheme.subtext)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var avatarCard: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.9))

                VStack(spacing: 12) {
                    RobotRendererView(size: 170, face: .front, loadout: loadout)
                    Text(L10n.t("profile_setup_avatar_hint"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black.opacity(0.55))
                }
                .padding(.vertical, 18)
            }
            .frame(height: 250)
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )

            Button(L10n.t("profile_setup_edit_look")) {
                showEquipmentEditor = true
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(warm.opacity(0.35), lineWidth: 2)
            )
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(warm)
            .buttonStyle(CardPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.95))
        }
        .padding(18)
        .background(FigmaTheme.card.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
    }

    private var nicknameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("profile_setup_nickname_label"))
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.black.opacity(0.55))

            HStack(spacing: 12) {
                Image(systemName: "signature")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.black.opacity(0.43))
                    .frame(width: 40, height: 40)
                    .background(Color(red: 243.0 / 255.0, green: 243.0 / 255.0, blue: 242.0 / 255.0))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                TextField(L10n.t("profile_setup_nickname_placeholder"), text: $nickname)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black.opacity(0.65))
            }
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(Color.white.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 29, style: .continuous)
                    .stroke(Color.black.opacity(0.03), lineWidth: 1)
            )

            Text(L10n.t("profile_setup_nickname_hint"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.black.opacity(0.52))
        }
        .padding(18)
        .background(FigmaTheme.card.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("profile_setup_ready_title"))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(FigmaTheme.text)

            Text(L10n.t("profile_setup_ready_body"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(FigmaTheme.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(FigmaTheme.card.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(FigmaTheme.border, lineWidth: 1)
        )
    }

    private var confirmButton: some View {
        Button(submitting ? L10n.t("processing") : L10n.t("profile_setup_confirm")) {
            Task { await submit() }
        }
        .disabled(submitting)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(accent)
        .foregroundColor(.white)
        .font(.system(size: 17, weight: .semibold))
        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
        .shadow(color: accent.opacity(0.28), radius: 20, x: 0, y: 12)
    }

    @MainActor
    private func submit() async {
        let trimmedName = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = L10n.t("profile_name_empty")
            return
        }
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else {
            errorMessage = BackendAPIError.unauthorized.localizedDescription
            return
        }

        submitting = true
        defer { submitting = false }

        do {
            let profile = try await BackendAPIClient.shared.completeProfileSetup(
                token: token,
                displayName: trimmedName,
                loadout: loadout
            )
            let resolvedLoadout = (profile.loadout ?? loadout).normalizedForCurrentAvatar()
            AvatarLoadoutStore.save(resolvedLoadout)
            UserScopedProfileStateStore.saveCurrentLoadout(resolvedLoadout, for: sessionStore.currentUserID)
            profileName = profile.displayName
            sessionStore.markProfileSetupCompleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
