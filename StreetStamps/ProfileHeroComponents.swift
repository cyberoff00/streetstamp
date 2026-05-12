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
            // Parchment matches the room scene's own background so there is no
            // visible mint border around the sofa. The hero section reads as one
            // continuous surface; the halftone decorations carry all the visual weight.
            FigmaTheme.background

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
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundColor(WorldoPalette.signal)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(WorldoPalette.lime.opacity(0.55))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
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
                        .fill(WorldoPalette.hairline.opacity(0.6))
                        .frame(width: 1, height: 44)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .background(FigmaTheme.card)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: FigmaTheme.softShadow, radius: 6, x: 0, y: 2)
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
