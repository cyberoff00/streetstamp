import SwiftUI

enum AuthEntryMode: String {
    case signIn
    case register

    var primaryButtonTitle: String {
        switch self {
        case .signIn: return L10n.t("auth_sign_in")
        case .register: return L10n.t("auth_create_account")
        }
    }
}

private enum OAuthProvider {
    case google
    case apple
}

private enum AuthField: Hashable {
    case fullName
    case email
    case password
    case confirmPassword
}

struct AuthEntryView: View {
    @EnvironmentObject private var sessionStore: UserSessionStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    let onContinueGuest: () -> Void
    let initialMode: AuthEntryMode?
    let onAuthenticated: (() -> Void)?

    @State private var mode: AuthEntryMode = .signIn
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var submitting = false
    @State private var showMessage = false
    @State private var messageText = ""
    @State private var showGuestNotice = false
    @FocusState private var focusedField: AuthField?

    private let accent = FigmaTheme.primary
    private let warm = FigmaTheme.secondary

    init(
        onContinueGuest: @escaping () -> Void,
        initialMode: AuthEntryMode? = nil,
        onAuthenticated: (() -> Void)? = nil
    ) {
        self.onContinueGuest = onContinueGuest
        self.initialMode = initialMode
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        ZStack {
            gridBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    titleBlock
                    formBlock
                    authPrimaryButton
                    switchModeRow
                    socialDivider
                    socialButtons
                    guestButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 22)
            }
        }
        .interactiveDismissDisabled()
        .alert(L10n.t("prompt"), isPresented: $showMessage) {
            Button(L10n.t("ok"), role: .cancel) {}
        } message: {
            Text(messageText)
        }
        .alert(L10n.t("guest_mode_title"), isPresented: $showGuestNotice) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("resume_prompt_continue")) { onContinueGuest() }
        } message: {
            Text(L10n.t("guest_mode_message"))
        }
        .onAppear {
            if let initialMode {
                mode = initialMode
            }
        }
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
                Text(mode == .signIn ? L10n.t("auth_sign_in") : L10n.t("auth_sign_up"))
                    .appHeaderStyle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

            Text(mode == .signIn ? L10n.t("auth_sign_in_subtitle") : L10n.t("auth_create_account_subtitle"))
                .appBodyStrongStyle()
                .foregroundColor(FigmaTheme.subtext)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var formBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .register {
                fieldLabel(L10n.t("auth_full_name"))
                fieldContainer(
                    icon: "person",
                    placeholder: "Cyber Kaka",
                    text: $fullName,
                    secure: false,
                    visible: true,
                    focused: .fullName
                )
            }

            fieldLabel(L10n.t("auth_email"))
            fieldContainer(
                icon: "envelope",
                placeholder: "your@email.com",
                text: $email,
                secure: false,
                visible: true,
                focused: .email
            )

            fieldLabel(L10n.t("auth_password"))
            fieldContainer(
                icon: "lock",
                placeholder: "••••••••",
                text: $password,
                secure: true,
                visible: isPasswordVisible,
                focused: .password,
                onToggleVisibility: { isPasswordVisible.toggle() }
            )

            if mode == .register {
                fieldContainer(
                    icon: "lock.rotation",
                    placeholder: "confirm password",
                    text: $confirmPassword,
                    secure: true,
                    visible: isConfirmPasswordVisible,
                    focused: .confirmPassword,
                    onToggleVisibility: { isConfirmPasswordVisible.toggle() }
                )
            } else {
                HStack {
                    Spacer()
                    Button(L10n.t("auth_forgot_password")) {
                        messageText = L10n.t("auth_forgot_password_hint")
                        showMessage = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.58))
                }
            }
        }
    }

    private var authPrimaryButton: some View {
        Button(submitting ? L10n.t("processing") : mode.primaryButtonTitle) {
            submitEmailAuth()
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

    private var switchModeRow: some View {
        HStack(spacing: 8) {
            if mode == .signIn {
                Text(L10n.t("auth_no_account"))
                    .foregroundColor(.black.opacity(0.56))
                Button(L10n.t("auth_sign_up")) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        mode = .register
                    }
                }
                .foregroundColor(accent)
                .fontWeight(.bold)
            } else {
                Text(L10n.t("auth_have_account"))
                    .foregroundColor(.black.opacity(0.56))
                Button(L10n.t("auth_sign_in_lower")) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        mode = .signIn
                    }
                }
                .foregroundColor(accent)
                .fontWeight(.bold)
            }
        }
        .font(.system(size: 14, weight: .semibold))
    }

    private var socialDivider: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(height: 1)
            Text(L10n.t("or"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.56))
            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(height: 1)
        }
        .padding(.top, 2)
    }

    private var socialButtons: some View {
        VStack(spacing: 12) {
            socialButton(title: "Google", iconName: "g.circle.fill", iconColor: .blue) {
                Task { await submitOAuth(provider: .google) }
            }

            socialButton(title: "Apple", iconName: "applelogo", iconColor: .black) {
                Task { await submitOAuth(provider: .apple) }
            }
        }
    }

    private var guestButton: some View {
        Button(L10n.t("continue_as_guest")) {
            showGuestNotice = true
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(warm.opacity(0.5), lineWidth: 2)
        )
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(warm)
        .padding(.top, 6)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(.black.opacity(0.55))
            .padding(.leading, 2)
    }

    @ViewBuilder
    private func fieldContainer(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        secure: Bool,
        visible: Bool,
        focused: AuthField,
        onToggleVisibility: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.black.opacity(0.43))
                .frame(width: 40, height: 40)
                .background(Color(red: 243.0 / 255.0, green: 243.0 / 255.0, blue: 242.0 / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if secure && !visible {
                SecureField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: focused)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .keyboardType(focused == .email ? .emailAddress : .default)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: focused)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
            }

            if let onToggleVisibility {
                Button {
                    onToggleVisibility()
                } label: {
                    Image(systemName: visible ? "eye.slash" : "eye")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 29, style: .continuous)
                .stroke(Color.black.opacity(0.03), lineWidth: 1)
        )
    }

    private func socialButton(title: String, iconName: String, iconColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
        }
        .buttonStyle(CardPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.95))
    }

    private func submitEmailAuth() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            messageText = L10n.t("auth_fill_email_password")
            showMessage = true
            return
        }

        if mode == .register,
           trimmedPassword != confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines) {
            messageText = L10n.t("auth_password_mismatch")
            showMessage = true
            return
        }

        Task {
            submitting = true
            defer { submitting = false }
            do {
                if mode == .register {
                    try await sessionStore.registerWithEmail(email: trimmedEmail, password: trimmedPassword)
                    let normalized = normalizedDisplayName(fullName)
                    if !normalized.isEmpty {
                        profileName = normalized
                    }
                    onAuthenticated?()
                } else {
                    try await sessionStore.loginWithEmail(email: trimmedEmail, password: trimmedPassword)
                    onAuthenticated?()
                }
            } catch {
                messageText = error.localizedDescription
                showMessage = true
            }
        }
    }

    private func submitOAuth(provider: OAuthProvider) async {
        submitting = true
        defer { submitting = false }
        do {
            let token: String
            switch provider {
            case .apple:
                token = try await AppleSignInService.signIn()
            case .google:
                token = try await GoogleSignInService.signIn()
            }
            let providerRaw = (provider == .apple) ? "apple" : "google"
            try await sessionStore.loginWithOAuth(provider: providerRaw, idToken: token)
            onAuthenticated?()
        } catch {
            messageText = error.localizedDescription
            showMessage = true
        }
    }

    private func normalizedDisplayName(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "" : value.uppercased()
    }
}
