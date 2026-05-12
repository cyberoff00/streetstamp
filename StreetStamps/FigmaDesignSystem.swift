import SwiftUI

enum FigmaTheme {
    /// Global canvas color, aligned with `WorldoPalette.parchment` so every
    /// screen using `figmaScreenBackground()` gets the warm dot-matrix base.
    static let background = Color(red: 249.0 / 255.0, green: 251.0 / 255.0, blue: 249.0 / 255.0) // #F9FBF9
    static let mutedBackground = Color(red: 249.0 / 255.0, green: 251.0 / 255.0, blue: 249.0 / 255.0) // #F9FBF9
    static let card = Color.white
    static let primary = Color(red: 82.0 / 255.0, green: 183.0 / 255.0, blue: 136.0 / 255.0) // #52B788 — HEAD original
    static let accent = Color(red: 116.0 / 255.0, green: 198.0 / 255.0, blue: 157.0 / 255.0) // #74C69D — HEAD original lit
    static let secondary = Color(red: 212.0 / 255.0, green: 165.0 / 255.0, blue: 116.0 / 255.0) // #D4A574
    static let text = Color(red: 26.0 / 255.0, green: 46.0 / 255.0, blue: 34.0 / 255.0) // #1A2E22 deep moss ink
    static let subtext = Color(red: 74.0 / 255.0, green: 92.0 / 255.0, blue: 80.0 / 255.0) // #4A5C50
    static let border = Color(red: 201.0 / 255.0, green: 205.0 / 255.0, blue: 184.0 / 255.0).opacity(0.55) // hairline
    static let softShadow = Color(red: 26.0 / 255.0, green: 46.0 / 255.0, blue: 34.0 / 255.0).opacity(0.05)
}

/// Worldo green-forward palette aligned with the dot-matrix / halftone aesthetic.
/// Coexists with `FigmaTheme`; new surfaces should prefer these tokens.
enum WorldoPalette {
    // Canvas
    static let parchment   = Color(red: 249.0 / 255.0, green: 251.0 / 255.0, blue: 249.0 / 255.0) // #F9FBF9
    static let paper       = Color.white
    static let moss        = Color(red:  14.0 / 255.0, green:  32.0 / 255.0, blue:  24.0 / 255.0) // #0E2018

    // Ink
    static let inkPrimary  = Color(red:  26.0 / 255.0, green:  46.0 / 255.0, blue:  34.0 / 255.0) // #1A2E22
    static let inkSecondary = Color(red:  74.0 / 255.0, green:  92.0 / 255.0, blue:  80.0 / 255.0) // #4A5C50
    static let hairline    = Color(red: 201.0 / 255.0, green: 205.0 / 255.0, blue: 184.0 / 255.0) // #C9CDB8

    // Brand greens (aligned with HEAD original)
    static let signal      = Color(red:  82.0 / 255.0, green: 183.0 / 255.0, blue: 136.0 / 255.0) // #52B788 — primary CTA
    static let signalLit   = Color(red: 116.0 / 255.0, green: 198.0 / 255.0, blue: 157.0 / 255.0) // #74C69D — lit/highlight
    static let lime        = Color(red: 221.0 / 255.0, green: 247.0 / 255.0, blue: 161.0 / 255.0) // #DDF7A1

    // Warm accents (sparingly)
    static let terracotta  = Color(red: 198.0 / 255.0, green: 106.0 / 255.0, blue:  74.0 / 255.0) // #C66A4A
    static let amber       = Color(red: 212.0 / 255.0, green: 165.0 / 255.0, blue: 116.0 / 255.0) // #D4A574
}

enum AppTypography {
    static let headerSize: CGFloat = 24
    static let titleSize: CGFloat = 20
    static let bodySize: CGFloat = 14
    static let bodyStrongSize: CGFloat = 16
    static let captionSize: CGFloat = 12
    static let footnoteSize: CGFloat = 11
}

// MARK: - Card chrome

/// Stroke style that produces a row of crisp dots when applied to any path.
/// Used as the canonical border for cards, dividers, and decorative frames.
private let dottedBorderStyle = StrokeStyle(
    lineWidth: 1.4,
    lineCap: .round,
    lineJoin: .round,
    dash: [0.001, 5.5]
)

private let dottedBorderStyleHeavy = StrokeStyle(
    lineWidth: 1.8,
    lineCap: .round,
    lineJoin: .round,
    dash: [0.001, 6.0]
)

extension View {
    /// Dot-matrix surface card. Replaces the old solid-line + heavy shadow card.
    /// Pass `radius` to control corner softness (default 16 — sharper than the previous 32
    /// to read as "engineered" rather than "consumer fluffy").
    func figmaSurfaceCard(radius: CGFloat = 16) -> some View {
        self
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: FigmaTheme.softShadow, radius: 14, x: 0, y: 6)
    }

    /// Hero / featured card variant — same surface, slightly larger shadow.
    func figmaSurfaceCardHero(radius: CGFloat = 18) -> some View {
        self
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: FigmaTheme.softShadow, radius: 18, x: 0, y: 8)
    }

    func figmaScreenBackground() -> some View {
        self.background(FigmaTheme.background.ignoresSafeArea())
    }

    /// Hero headline style.
    func appHeaderStyle() -> some View {
        self
            .font(.system(size: AppTypography.headerSize, weight: .semibold))
            .foregroundColor(FigmaTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Section title style — lighter weight for hierarchy.
    func appTitleStyle() -> some View {
        self
            .font(.system(size: AppTypography.titleSize, weight: .medium))
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

    /// Monospace numeric style for stats, distances, coordinates, timestamps.
    /// Use anywhere a "data-driven" feel is wanted — e.g. "47 cities · 128 km".
    func appNumericStyle(size: CGFloat = AppTypography.bodySize, weight: Font.Weight = .medium) -> some View {
        self
            .font(.system(size: size, weight: weight, design: .monospaced))
            .foregroundColor(FigmaTheme.text)
    }

    /// ALL-CAPS monospace label with letter-spacing — for section labels, badges,
    /// stamp serial numbers, blueprint annotations. Pairs with `appHeaderStyle()`.
    func appLabelStyle(size: CGFloat = 11, color: Color = WorldoPalette.inkSecondary) -> some View {
        self
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundColor(color)
    }

    /// Hero title for brand surfaces (profile, postcard, achievements).
    /// Larger and tighter than `appHeaderStyle()`.
    func appHeroStyle(size: CGFloat = 32) -> some View {
        self
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(FigmaTheme.text)
            .tracking(-0.3)
    }

    /// Inline meta info — bracketed mono. Caller passes plain string; modifier formats.
    /// Example use: `Text("EXPLORER · 2026").appMetaStyle()`.
    func appMetaStyle(size: CGFloat = 10) -> some View {
        self
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .tracking(0.6)
            .foregroundColor(WorldoPalette.inkSecondary)
    }
}

// MARK: - Dotted divider

/// Horizontal divider rendered as a row of small dots.
/// Drop-in replacement for `Divider()` on parchment surfaces.
struct AppDottedDivider: View {
    var color: Color = WorldoPalette.inkPrimary.opacity(0.35)
    var spacing: CGFloat = 5
    var dotSize: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let count = max(2, Int(size.width / spacing))
            let stride = size.width / CGFloat(count)
            for i in 0...count {
                let x = stride * CGFloat(i)
                let y = size.height / 2
                path.addRect(CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize))
            }
            ctx.fill(path, with: .color(color))
        }
        .frame(height: dotSize + 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Corner serial label

/// Small monospace serial label, designed to sit in a card corner like a stamp number.
/// Example: `WORLDO · 2026.05 · #047`
struct AppCornerSerial: View {
    let text: String
    var color: Color = WorldoPalette.inkSecondary

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.0)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(WorldoPalette.parchment.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
    }
}
