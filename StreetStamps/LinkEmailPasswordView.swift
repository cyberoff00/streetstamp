import SwiftUI

struct LinkEmailPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: UserSessionStore

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var submitting = false
    @State private var showMessage = false
    @State private var messageText = ""
    @State private var showVerificationSheet = false
    @State private var pendingVerificationEmail: String?
    @FocusState private var focusedField: Field?

    private let accent = FigmaTheme.primary

    private enum Field: Hashable {
        case email, password, confirmPassword
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                headerBlock
                formBlock
                submitButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 22)
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                        Text(L10n.t("back"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(FigmaTheme.text)
                }
            }
            ToolbarItem(placement: .principal) {
                Text(L10n.t("link_email_title"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
            }
        }
        .alert(L10n.t("prompt"), isPresented: $showMessage) {
            Button(L10n.t("ok"), role: .cancel) {}
        } message: {
            Text(messageText)
        }
        .fullScreenCover(isPresented: $showVerificationSheet) {
            EmailVerificationView(
                email: pendingVerificationEmail,
                onResend: {
                    try await resendVerificationEmail()
                },
                onRefresh: {
                    try await refreshVerificationState()
                },
                onCancel: {
                    showVerificationSheet = false
                }
            )
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(.orange)

            Text(L10n.t("link_email_subtitle"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var formBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            fieldContainer(
                icon: "lock.rotation",
                placeholder: L10n.t("link_email_confirm_password"),
                text: $confirmPassword,
                secure: true,
                visible: isConfirmPasswordVisible,
                focused: .confirmPassword,
                onToggleVisibility: { isConfirmPasswordVisible.toggle() }
            )
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            Text(submitting ? L10n.t("processing") : L10n.t("link_email_submit"))
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
        focused: Field,
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
                        .appMinTapTarget()
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

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            messageText = L10n.t("auth_fill_email_password")
            showMessage = true
            return
        }

        guard trimmedPassword == trimmedConfirm else {
            messageText = L10n.t("auth_password_mismatch")
            showMessage = true
            return
        }

        let store = sessionStore
        Task {
            submitting = true
            defer { submitting = false }
            do {
                let result = try await store.linkEmailPassword(
                    email: trimmedEmail,
                    password: trimmedPassword
                )
                pendingVerificationEmail = result.email
                if result.emailVerificationRequired {
                    showVerificationSheet = true
                } else {
                    store.hasEmailPassword = true
                    dismiss()
                }
            } catch {
                messageText = error.localizedDescription
                showMessage = true
            }
        }
    }

    private func resendVerificationEmail() async throws {
        guard let email = pendingVerificationEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            throw BackendAPIError.server("missing email")
        }
        let store = sessionStore
        try await store.resendVerificationEmail(email: email)
    }

    private func refreshVerificationState() async throws -> Bool {
        let store = sessionStore
        guard let token = store.currentAccessToken, !token.isEmpty else {
            return false
        }

        let profile = try await BackendAPIClient.shared.fetchMyProfile(token: token)
        guard profile.hasEmailPassword == true else {
            return false
        }

        store.hasEmailPassword = true
        showVerificationSheet = false
        dismiss()
        return true
    }
}
