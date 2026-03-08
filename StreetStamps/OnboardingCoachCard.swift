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
            }
            .buttonStyle(.plain)

            HStack(spacing: 16) {
                Button("稍后继续", action: onLater)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.64))
                    .buttonStyle(.plain)

                Button("跳过引导", action: onSkip)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.45))
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
