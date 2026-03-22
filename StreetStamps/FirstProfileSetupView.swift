import SwiftUI

enum FirstProfileSetupAction {
    case confirm
    case skip
}

struct FirstProfileSetupActionPresentation: Equatable {
    let usesFullSurfaceHitTarget: Bool
}

enum FirstProfileSetupSection: Equatable {
    case nickname
    case avatar
    case actions
}

struct FirstProfileSetupPresentationModel: Equatable {
    let heroTitleKey: String
    let heroHelperKey: String
    let showsSubtitle: Bool
    let showsNicknameHint: Bool
    let showsSummaryCard: Bool
    let showsHeroCardTitle: Bool
    let usesScrollLayout: Bool
    let contentOrder: [FirstProfileSetupSection]
    let skipButtonTopOffset: CGFloat
    let skipAction: FirstProfileSetupActionPresentation
    let editLookAction: FirstProfileSetupActionPresentation
    let confirmAction: FirstProfileSetupActionPresentation

    static let minimal = FirstProfileSetupPresentationModel(
        heroTitleKey: "profile_setup_avatar_title",
        heroHelperKey: "profile_setup_avatar_hint",
        showsSubtitle: false,
        showsNicknameHint: false,
        showsSummaryCard: false,
        showsHeroCardTitle: false,
        usesScrollLayout: true,
        contentOrder: [.nickname, .avatar],
        skipButtonTopOffset: -6,
        skipAction: FirstProfileSetupActionPresentation(usesFullSurfaceHitTarget: true),
        editLookAction: FirstProfileSetupActionPresentation(usesFullSurfaceHitTarget: true),
        confirmAction: FirstProfileSetupActionPresentation(usesFullSurfaceHitTarget: true)
    )
}

enum FirstProfileSetupSubmission: Equatable {
    case blocked(message: String)
    case submit(displayName: String)

    static func decision(for action: FirstProfileSetupAction, nickname: String) -> FirstProfileSetupSubmission {
        let trimmedName = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .blocked(message: L10n.t("profile_name_empty"))
        }
        _ = action
        return .submit(displayName: trimmedName)
    }
}

enum FirstProfileSetupDebugPreviewBehavior {
    static func shouldDismissImmediately(
        for action: FirstProfileSetupAction,
        isDebugPreview: Bool,
        hasAccessToken: Bool
    ) -> Bool {
        isDebugPreview && action == .skip && !hasAccessToken
    }
}

struct FirstProfileSetupView: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @State private var nickname: String = ""
    @State private var loadout: RobotLoadout = AvatarLoadoutStore.load()
    @State private var showEquipmentEditor = false
    @State private var submitting = false
    @State private var errorMessage: String?

    private let presentation = FirstProfileSetupPresentationModel.minimal
    private let accent = FigmaTheme.primary
    private let warm = FigmaTheme.secondary
    private let isDebugPreview: Bool
    private let onDismissDebugPreview: (() -> Void)?

    init() {
        self.isDebugPreview = false
        self.onDismissDebugPreview = nil
    }

    #if DEBUG
    init(
        isDebugPreview: Bool = false,
        onDismissDebugPreview: (() -> Void)? = nil
    ) {
        self.isDebugPreview = isDebugPreview
        self.onDismissDebugPreview = onDismissDebugPreview
    }
    #endif

    var body: some View {
        ZStack {
            gridBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 10)
                    titleBlock
                    Spacer(minLength: 18)
                    contentCards
                    Spacer(minLength: 16)
                    confirmButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .interactiveDismissDisabled(!debugPreviewEnabled)
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

    private var debugPreviewEnabled: Bool {
        #if DEBUG
        isDebugPreview
        #else
        false
        #endif
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
        VStack(spacing: presentation.showsSubtitle ? 8 : 0) {
            Text(L10n.t("profile_setup_title"))
                .appHeaderStyle()
                .multilineTextAlignment(.center)

            if presentation.showsSubtitle {
                Text(L10n.t("profile_setup_subtitle"))
                    .appBodyStrongStyle()
                    .foregroundColor(FigmaTheme.subtext)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()

            Button {
                Task { await submit(.skip) }
            } label: {
                Text(submitting ? L10n.t("processing") : L10n.t("profile_setup_skip"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FigmaTheme.subtext)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.92))
                    .clipShape(Capsule())
                    .appFullSurfaceTapTarget(.capsule)
            }
            .disabled(submitting)
        }
        .padding(.top, presentation.skipButtonTopOffset)
    }

    @ViewBuilder
    private var contentCards: some View {
        ForEach(Array(presentation.contentOrder.enumerated()), id: \.offset) { index, section in
            if index > 0 {
                Spacer(minLength: 16)
            }

            switch section {
            case .nickname:
                nicknameCard
            case .avatar:
                avatarCard
            case .actions:
                if presentation.showsSummaryCard {
                    actionsCard
                }
            }
        }

        if presentation.showsSummaryCard && !presentation.contentOrder.contains(.actions) {
            Spacer(minLength: 16)
            actionsCard
        }
    }

    private var avatarCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if presentation.showsHeroCardTitle {
                Text(L10n.t(presentation.heroTitleKey))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.9))

                VStack(spacing: 12) {
                    RobotRendererView(size: 154, face: .front, loadout: loadout)
                    Text(L10n.t(presentation.heroHelperKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .frame(height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )

            Button {
                showEquipmentEditor = true
            } label: {
                Text(L10n.t("profile_setup_edit_look"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(warm.opacity(0.35), lineWidth: 2)
                    )
                    .appFullSurfaceTapTarget(.roundedRect(26))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(warm)
            }
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

            if presentation.showsNicknameHint {
                Text(L10n.t("profile_setup_nickname_hint"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.52))
            }
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
        Button {
            Task { await submit(.confirm) }
        } label: {
            Text(submitting ? L10n.t("processing") : L10n.t("profile_setup_confirm"))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(accent)
                .foregroundColor(.white)
                .font(.system(size: 17, weight: .semibold))
                .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                .appFullSurfaceTapTarget(.roundedRect(29))
        }
        .disabled(submitting)
        .shadow(color: accent.opacity(0.28), radius: 20, x: 0, y: 12)
    }

    @MainActor
    private func submit(_ action: FirstProfileSetupAction) async {
        let decision = FirstProfileSetupSubmission.decision(for: action, nickname: nickname)
        guard case .submit(let displayName) = decision else {
            if case .blocked(let message) = decision {
                errorMessage = message
            }
            return
        }
        let token = sessionStore.currentAccessToken ?? ""
        if FirstProfileSetupDebugPreviewBehavior.shouldDismissImmediately(
            for: action,
            isDebugPreview: debugPreviewEnabled,
            hasAccessToken: !token.isEmpty
        ) {
            onDismissDebugPreview?()
            return
        }
        guard !token.isEmpty else {
            errorMessage = BackendAPIError.unauthorized.localizedDescription
            return
        }

        submitting = true
        defer { submitting = false }

        do {
            let profile = try await BackendAPIClient.shared.completeProfileSetup(
                token: token,
                displayName: displayName,
                loadout: loadout
            )
            let resolvedLoadout = (profile.loadout ?? loadout).normalizedForCurrentAvatar()
            AvatarLoadoutStore.save(resolvedLoadout)
            UserScopedProfileStateStore.saveCurrentLoadout(resolvedLoadout, for: sessionStore.currentUserID)
            profileName = profile.displayName
            sessionStore.markProfileSetupCompleted()
            if debugPreviewEnabled {
                onDismissDebugPreview?()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
