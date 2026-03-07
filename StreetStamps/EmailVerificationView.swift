import SwiftUI

struct EmailVerificationView: View {
    let email: String?
    let onResend: () async throws -> Void
    let onRefresh: () async throws -> Bool
    let onCancel: () -> Void

    @State private var isSubmitting = false
    @State private var messageText = ""
    @State private var showMessage = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Verify Your Email")
                    .appHeaderStyle()

                Text(descriptionText)
                    .appBodyStrongStyle()
                    .foregroundColor(FigmaTheme.subtext)

                Button(isSubmitting ? L10n.t("processing") : "Resend Verification Email") {
                    Task { await resend() }
                }
                .disabled(isSubmitting)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(FigmaTheme.primary)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Button(isSubmitting ? L10n.t("processing") : "I've Verified My Email") {
                    Task { await refreshVerification() }
                }
                .disabled(isSubmitting)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.white)
                .foregroundColor(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Spacer()
            }
            .padding(20)
            .background(FigmaTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("cancel"), action: onCancel)
                }
            }
        }
        .alert(L10n.t("prompt"), isPresented: $showMessage) {
            Button(L10n.t("ok"), role: .cancel) {}
        } message: {
            Text(messageText)
        }
    }

    private var descriptionText: String {
        if let email, !email.isEmpty {
            return "We sent a verification link to \(email). Verify it first, then come back here to continue."
        }
        return "We sent a verification link to your email. Verify it first, then come back here to continue."
    }

    private func resend() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await onResend()
            messageText = "Verification email sent."
        } catch {
            messageText = error.localizedDescription
        }
        showMessage = true
    }

    private func refreshVerification() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let verified = try await onRefresh()
            if !verified {
                messageText = "This email is still unverified."
                showMessage = true
            }
        } catch {
            messageText = error.localizedDescription
            showMessage = true
        }
    }
}
