import SwiftUI

struct ProfileHeroStatCardItem: Identifiable, Equatable {
    let id: String
    let systemImage: String
    let iconColor: Color
    let iconBackground: Color
    let value: String
    let valueSuffix: String?
    let title: String
}

struct ProfileHeroInfoStatsSection<HeaderContent: View, TrailingContent: View>: View {
    let stats: [ProfileHeroStatCardItem]
    let headerContent: HeaderContent
    let trailingContent: TrailingContent

    init(
        stats: [ProfileHeroStatCardItem],
        @ViewBuilder headerContent: () -> HeaderContent,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.stats = stats
        self.headerContent = headerContent()
        self.trailingContent = trailingContent()
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                headerContent
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailingContent
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, stats.isEmpty ? 22 : 0)

            if !stats.isEmpty {
                Rectangle()
                    .fill(Color.gray.opacity(0.10))
                    .frame(height: 1)
                    .padding(.horizontal, 22)

                HStack(spacing: 14) {
                    ForEach(stats) { item in
                        statCard(item)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .heroSurfaceCard(cornerRadius: 28)
    }

    private func statCard(_ item: ProfileHeroStatCardItem) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(item.iconBackground)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(item.iconColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(item.value)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let valueSuffix = item.valueSuffix, !valueSuffix.isEmpty {
                        Text(valueSuffix)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                }

                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(FigmaTheme.subtext)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 84)
    }
}

private extension View {
    func heroSurfaceCard(cornerRadius: CGFloat) -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }
}
