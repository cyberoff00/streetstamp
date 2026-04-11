import SwiftUI

struct ProfilePostcardEntryCard: View {
    let systemImage: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let subtitle: String?
    let badges: [String]

    init(
        systemImage: String = "envelope",
        iconColor: Color = FigmaTheme.primary,
        iconBackground: Color = FigmaTheme.primary.opacity(0.10),
        title: String,
        subtitle: String?,
        badges: [String] = []
    ) {
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.iconBackground = iconBackground
        self.title = title
        self.subtitle = subtitle
        self.badges = badges
    }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(iconBackground)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(iconColor)
                }

            VStack(alignment: .leading, spacing: badges.isEmpty ? 3 : 8) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)

                if !badges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(badges, id: \.self) { badge in
                                Text(badge)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(FigmaTheme.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(FigmaTheme.primary.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .scrollDisabled(true)
                } else if let subtitle, !subtitle.isEmpty {
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
