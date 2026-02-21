import SwiftUI

enum FigmaTheme {
    static let background = Color(red: 251.0 / 255.0, green: 251.0 / 255.0, blue: 249.0 / 255.0) // #FBFBF9
    static let mutedBackground = Color(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 243.0 / 255.0) // #F5F5F3
    static let card = Color.white
    static let primary = Color(red: 82.0 / 255.0, green: 183.0 / 255.0, blue: 136.0 / 255.0) // #52B788
    static let accent = Color(red: 116.0 / 255.0, green: 198.0 / 255.0, blue: 157.0 / 255.0) // #74C69D
    static let secondary = Color(red: 212.0 / 255.0, green: 165.0 / 255.0, blue: 116.0 / 255.0) // #D4A574
    static let text = Color.black
    static let subtext = Color(red: 107.0 / 255.0, green: 107.0 / 255.0, blue: 107.0 / 255.0) // #6B6B6B
    static let border = Color.black.opacity(0.06)
    static let softShadow = Color.black.opacity(0.04)
}

enum AppTypography {
    static let headerSize: CGFloat = 24
    static let titleSize: CGFloat = 20
    static let bodySize: CGFloat = 14
    static let bodyStrongSize: CGFloat = 16
    static let captionSize: CGFloat = 12
    static let footnoteSize: CGFloat = 11
}

extension View {
    func figmaSurfaceCard(radius: CGFloat = 32) -> some View {
        self
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(FigmaTheme.border, lineWidth: 1)
            )
            .shadow(color: FigmaTheme.softShadow, radius: 20, x: 0, y: 8)
    }

    func figmaScreenBackground() -> some View {
        self.background(FigmaTheme.background.ignoresSafeArea())
    }

    func appHeaderStyle() -> some View {
        self
            .font(.system(size: AppTypography.headerSize, weight: .bold))
            .foregroundColor(FigmaTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    func appTitleStyle() -> some View {
        self
            .font(.system(size: AppTypography.titleSize, weight: .semibold))
            .foregroundColor(FigmaTheme.text)
    }

    func appBodyStyle() -> some View {
        self
            .font(.system(size: AppTypography.bodySize, weight: .regular))
            .foregroundColor(FigmaTheme.text)
    }

    func appBodyStrongStyle() -> some View {
        self
            .font(.system(size: AppTypography.bodyStrongSize, weight: .semibold))
            .foregroundColor(FigmaTheme.text)
    }

    func appCaptionStyle() -> some View {
        self
            .font(.system(size: AppTypography.captionSize, weight: .medium))
            .foregroundColor(FigmaTheme.subtext)
    }

    func appFootnoteStyle() -> some View {
        self
            .font(.system(size: AppTypography.footnoteSize, weight: .medium))
            .foregroundColor(FigmaTheme.subtext)
    }
}
