import SwiftUI

struct MemoryPin: View {
    static let annotationWidth: CGFloat = 36
    static let annotationHeight: CGFloat = 38
    private static let headDiameter: CGFloat = 28
    private static let tipWidth: CGFloat = 12
    private static let tipHeight: CGFloat = 10

    static var annotationCenterOffset: CGPoint {
        CGPoint(x: 0, y: -(annotationHeight / 2))
    }

    let cluster: [JourneyMemory]

    var body: some View {
        let hasPhoto = cluster.contains { !$0.imagePaths.isEmpty }
        let hasNote = cluster.contains { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let count = cluster.count

        ZStack(alignment: .top) {
            VStack(spacing: -1) {
                Circle()
                    .fill(UITheme.accent)
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .frame(width: Self.headDiameter, height: Self.headDiameter)

                MemoryPinTipShape()
                    .fill(UITheme.accent)
                    .frame(width: Self.tipWidth, height: Self.tipHeight)
                    .overlay(
                        MemoryPinTipShape().stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
            .shadow(color: .black.opacity(0.12), radius: 5, y: 3)

            ZStack {
                if hasPhoto && hasNote {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .offset(x: 5, y: 0)

                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .offset(x: -5, y: 0)
                } else if hasPhoto {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundColor(.black.opacity(0.75))
            .offset(y: 8)

            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Circle().fill(Color.black))
                    .offset(x: 11, y: -2)
            }
        }
        .frame(width: Self.annotationWidth, height: Self.annotationHeight)
    }
}

private struct MemoryPinTipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
