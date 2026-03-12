import SwiftUI

struct ProfileHeroStatItem: Identifiable, Equatable {
    let id: String
    let value: String
    let title: String
}

struct ProfileHeroTopBackdrop<Content: View>: View {
    let topCornerRadius: CGFloat
    let content: Content

    init(topCornerRadius: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.topCornerRadius = topCornerRadius
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    FigmaTheme.accent.opacity(0.20),
                    FigmaTheme.primary.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 128)
            .frame(maxHeight: .infinity, alignment: .top)

            RoundedRectangle(cornerRadius: max(topCornerRadius, 40), style: .continuous)
                .fill(FigmaTheme.primary.opacity(0.17))
                .frame(width: 360, height: 260)
                .blur(radius: 36)
                .offset(y: 28)

            content
        }
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: topCornerRadius,
                    bottomLeading: 0,
                    bottomTrailing: 0,
                    topTrailing: topCornerRadius
                ),
                style: .continuous
            )
        )
    }
}

struct ProfileHeroLevelPill: View {
    let level: Int

    var body: some View {
        Text(String(format: L10n.t("level_format"), level))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(Color(red: 15.0 / 255.0, green: 118.0 / 255.0, blue: 110.0 / 255.0))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color(red: 204.0 / 255.0, green: 251.0 / 255.0, blue: 241.0 / 255.0))
            .clipShape(Capsule())
    }
}

struct ProfileHeroStatsCard: View {
    let items: [ProfileHeroStatItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 4) {
                    Text(item.value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 31.0 / 255.0, green: 41.0 / 255.0, blue: 55.0 / 255.0))

                    Text(item.title)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(Color(red: 156.0 / 255.0, green: 163.0 / 255.0, blue: 175.0 / 255.0))
                }
                .frame(maxWidth: .infinity)

                if index < items.count - 1 {
                    Rectangle()
                        .fill(Color(red: 249.0 / 255.0, green: 250.0 / 255.0, blue: 251.0 / 255.0))
                        .frame(width: 1, height: 44)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .background(Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 243.0 / 255.0, green: 244.0 / 255.0, blue: 246.0 / 255.0), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct ProfileHeroGlassCircleLabel: View {
    let systemImage: String
    let iconWeight: Font.Weight

    init(systemImage: String, iconWeight: Font.Weight = .semibold) {
        self.systemImage = systemImage
        self.iconWeight = iconWeight
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.18))

            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)

            Image(systemName: systemImage)
                .font(.system(size: 17, weight: iconWeight))
                .foregroundColor(.white)
        }
        .frame(width: 40, height: 40)
        .background(.ultraThinMaterial, in: Circle())
    }
}
