import SwiftUI

// MARK: - Minimum Tap Target

extension View {
    /// Ensures minimum 44x44 pt tap target per Apple HIG.
    /// Visual content stays centered; only the hit area expands.
    func appMinTapTarget(_ size: CGFloat = 44) -> some View {
        self
            .frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

// MARK: - Standardized Back Button

/// Unified chevron.left back button. Calls dismiss() by default.
struct AppBackButton: View {
    private let customAction: (() -> Void)?
    var foreground: Color = FigmaTheme.text

    @Environment(\.dismiss) private var dismiss

    init(foreground: Color = FigmaTheme.text, action: (() -> Void)? = nil) {
        self.foreground = foreground
        self.customAction = action
    }

    var body: some View {
        Button {
            if let customAction { customAction() } else { dismiss() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(foreground)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Standardized Close Button

/// Unified xmark close button with visual style variants.
struct AppCloseButton: View {
    private let customAction: (() -> Void)?
    let style: Style

    @Environment(\.dismiss) private var dismiss

    enum Style {
        /// Bare xmark icon, no background.
        case plain
        /// Small circle with faint background (sheets/panels).
        case circleSubtle
        /// Dark translucent circle (overlays on images/maps).
        case circleDark
        /// SF Symbol xmark.circle.fill (compact dismiss).
        case filled
    }

    init(style: Style = .plain, action: (() -> Void)? = nil) {
        self.style = style
        self.customAction = action
    }

    var body: some View {
        Button {
            if let customAction { customAction() } else { dismiss() }
        } label: {
            iconContent
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconContent: some View {
        switch style {
        case .plain:
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(FigmaTheme.text)
        case .circleSubtle:
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FigmaTheme.text.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.05))
                .clipShape(Circle())
        case .circleDark:
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.35))
                .clipShape(Circle())
        case .filled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.gray)
        }
    }
}
