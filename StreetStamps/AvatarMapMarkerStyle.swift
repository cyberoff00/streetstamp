import SwiftUI

enum AvatarMapMarkerStyle {
    static let visualSize: CGFloat = 96
    static let annotationSize: CGFloat = 112
    static let collapsedSheetPeekHeight: CGFloat = 72
}

struct AvatarHeadlightConeView: View {
    let headingDegrees: Double

    var body: some View {
        let correctedHeading = headingDegrees + HeadlightConeShape.halfSpreadDegrees
        ZStack {
            HeadlightConeShape()
                .fill(
                    LinearGradient(
                        colors: [UITheme.accent.opacity(0.35), UITheme.accent.opacity(0.02)],
                        startPoint: .center,
                        endPoint: .top
                    )
                )
                .frame(width: 126, height: 126)
                .blur(radius: 4)
                .rotationEffect(.degrees(correctedHeading))

            HeadlightConeShape()
                .stroke(UITheme.accent.opacity(0.30), lineWidth: 1)
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(correctedHeading))

            Circle()
                .fill(UITheme.accent.opacity(0.22))
                .frame(width: 14, height: 14)
        }
    }
}

private struct HeadlightConeShape: Shape {
    static let halfSpreadDegrees: Double = 32

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.54
        let spread = Angle.degrees(Self.halfSpreadDegrees)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90) - spread,
            endAngle: .degrees(-90) + spread,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
