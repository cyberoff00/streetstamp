import SwiftUI

enum AppFullSurfaceTapTargetShape: Equatable {
    case rectangle
    case roundedRect(CGFloat)
    case capsule
    case circle

    var debugName: String {
        switch self {
        case .rectangle:
            return "rectangle"
        case .roundedRect:
            return "roundedRect"
        case .capsule:
            return "capsule"
        case .circle:
            return "circle"
        }
    }
}

private struct AppFullSurfaceTapTargetModifier: ViewModifier {
    let shape: AppFullSurfaceTapTargetShape

    @ViewBuilder
    func body(content: Content) -> some View {
        switch shape {
        case .rectangle:
            content.contentShape(Rectangle())
        case .roundedRect(let cornerRadius):
            content.contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .capsule:
            content.contentShape(Capsule())
        case .circle:
            content.contentShape(Circle())
        }
    }
}

extension View {
    func appFullSurfaceTapTarget(_ shape: AppFullSurfaceTapTargetShape) -> some View {
        modifier(AppFullSurfaceTapTargetModifier(shape: shape))
    }
}
