import SwiftUI

struct ProfilePostcardEntryCard: View {
    let title: String
    let subtitle: String?

    private let iconBackground = FigmaTheme.primary.opacity(0.10)

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(iconBackground)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: "envelope")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(FigmaTheme.primary)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(Color(red: 0.97, green: 0.97, blue: 0.98))
                    .frame(width: 32, height: 32)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext.opacity(0.75))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }
}
