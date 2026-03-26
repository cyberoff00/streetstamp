import SwiftUI

/// Direction the tooltip arrow points toward (i.e. where the target element is relative to the bubble).
enum TooltipArrowEdge {
    case top, bottom, leading, trailing
}

/// A speech-bubble tooltip with a directional arrow pointing toward a target UI element.
struct TooltipBubble: View {
    let message: String
    var icon: String? = nil
    var arrowEdge: TooltipArrowEdge = .bottom
    var stepLabel: String? = nil  // e.g. "1/3"
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil
    let onDismiss: () -> Void

    private let arrowSize: CGFloat = 10
    private let cornerRadius: CGFloat = 14
    private let bubbleMaxWidth: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            if arrowEdge == .bottom {
                bubbleContent
                arrowShape
                    .rotationEffect(.degrees(180))
                    .frame(width: arrowSize * 2, height: arrowSize)
            } else if arrowEdge == .top {
                arrowShape
                    .frame(width: arrowSize * 2, height: arrowSize)
                bubbleContent
            } else {
                HStack(spacing: 0) {
                    if arrowEdge == .trailing {
                        bubbleContent
                        arrowShape
                            .rotationEffect(.degrees(-90))
                            .frame(width: arrowSize, height: arrowSize * 2)
                    } else {
                        arrowShape
                            .rotationEffect(.degrees(90))
                            .frame(width: arrowSize, height: arrowSize * 2)
                        bubbleContent
                    }
                }
            }
        }
        .frame(maxWidth: bubbleMaxWidth)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(FigmaTheme.primary)
                }

                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }

            if let actionTitle, let onAction {
                HStack {
                    if let stepLabel {
                        Text(stepLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                    Button {
                        onAction()
                    } label: {
                        Text(actionTitle)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(FigmaTheme.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else if let stepLabel {
                Text(stepLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var arrowShape: some View {
        Triangle()
            .fill(Color.black.opacity(0.85))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
