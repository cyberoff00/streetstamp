import SwiftUI

struct OnboardingCoachCard: View {
    let message: String
    let actionTitle: String
    let onAction: () -> Void
    let onLater: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)

            Button(action: onAction) {
                Text(actionTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .appFullSurfaceTapTarget(.roundedRect(14))
            }
            .buttonStyle(.plain)

            HStack(spacing: 16) {
                Button(action: onLater) {
                    Text(L10n.key("onboarding_continue_later"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black.opacity(0.64))
                        .padding(.vertical, 4)
                        .appFullSurfaceTapTarget(.rectangle)
                }
                    .buttonStyle(.plain)

                Button(action: onSkip) {
                    Text(L10n.key("onboarding_skip_guide"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black.opacity(0.45))
                        .padding(.vertical, 4)
                        .appFullSurfaceTapTarget(.rectangle)
                }
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 6)
    }
}
