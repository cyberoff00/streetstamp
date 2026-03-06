import SwiftUI

struct AppSplashView: View {
    private let brandGreen = Color(red: 0.0, green: 182.0 / 255.0, blue: 122.0 / 255.0)
    private let brandRed = Color(red: 1.0, green: 92.0 / 255.0, blue: 92.0 / 255.0)

    @State private var drawProgress: CGFloat = 1
    @State private var animationStart = Date()
    @State private var showWordmark = false
    @State private var showTagline = false

    var body: some View {
        GeometryReader { _ in
            ZStack {
                brandGreen.ignoresSafeArea()
                SplashMapLines()
                    .opacity(0.1)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ZStack {
                        SplashWShape()
                            .trim(from: 0, to: drawProgress)
                            .stroke(
                                Color.white,
                                style: StrokeStyle(
                                    lineWidth: 18,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .frame(width: 180, height: 180)
                            .shadow(color: Color.black.opacity(0.05), radius: 2, y: 4)

                        TimelineView(.animation) { timeline in
                            let progress = runnerProgress(at: timeline.date)
                            SplashPixelRunner(accent: brandRed)
                                .frame(width: 44, height: 44)
                                .offset(pixelOffset(progress: progress))
                                .opacity(pixelOpacity(progress: progress))
                        }
                        .frame(width: 44, height: 44)
                    }
                    .frame(width: 180, height: 180)

                    Text("worldo")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(-1.5)
                        .padding(.top, 32)
                        .opacity(showWordmark ? 1 : 0)
                        .offset(y: showWordmark ? 0 : 20)

                    Text("Log your life. Map your memories.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.9))
                        .padding(.top, 12)
                        .opacity(showTagline ? 1 : 0)
                        .offset(y: showTagline ? 0 : 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            drawProgress = 1
            animationStart = Date()
            withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.8).delay(0.5)) {
                showWordmark = true
            }
            withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.8).delay(0.7)) {
                showTagline = true
            }
        }
    }

    private func runnerProgress(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(animationStart)
        return CGFloat(min(max(elapsed / 3.0, 0), 1))
    }

    private func pixelOffset(progress: CGFloat) -> CGSize {
        let keyframes: [(t: CGFloat, x: CGFloat, y: CGFloat)] = [
            (0.00, 0, 0),
            (0.15, 25, 60),
            (0.30, 50, 20),
            (0.45, 75, 60),
            (0.60, 100, 0),
            (0.70, 100, -10),
            (0.80, 100, 0),
            (1.00, 0, 0)
        ]

        let movement = interpolate(progress: progress, keyframes: keyframes)
        return CGSize(width: -48 + movement.width, height: -48 + movement.height)
    }

    private func pixelOpacity(progress: CGFloat) -> Double {
        _ = progress
        return 1
    }

    private func interpolate(
        progress: CGFloat,
        keyframes: [(t: CGFloat, x: CGFloat, y: CGFloat)]
    ) -> CGSize {
        let p = min(max(progress, 0), 1)
        for idx in 0..<(keyframes.count - 1) {
            let a = keyframes[idx]
            let b = keyframes[idx + 1]
            guard p >= a.t && p <= b.t else { continue }
            let segmentT = (p - a.t) / (b.t - a.t)
            let x = a.x + (b.x - a.x) * segmentT
            let y = a.y + (b.y - a.y) * segmentT
            return CGSize(width: x, height: y)
        }
        return .zero
    }
}

private struct SplashMapLines: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            Path { path in
                path.move(to: CGPoint(x: -0.125 * w, y: 0.125 * h))
                path.addQuadCurve(
                    to: CGPoint(x: 0.50 * w, y: 0.1875 * h),
                    control: CGPoint(x: 0.25 * w, y: 0.0625 * h)
                )
                path.addQuadCurve(
                    to: CGPoint(x: 1.125 * w, y: 0.25 * h),
                    control: CGPoint(x: 0.75 * w, y: 0.3125 * h)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [10, 10]))
            .foregroundColor(.white)

            Path { path in
                path.move(to: CGPoint(x: -0.125 * w, y: 0.75 * h))
                path.addQuadCurve(
                    to: CGPoint(x: 0.625 * w, y: 0.6875 * h),
                    control: CGPoint(x: 0.375 * w, y: 0.8125 * h)
                )
                path.addQuadCurve(
                    to: CGPoint(x: 1.125 * w, y: 0.875 * h),
                    control: CGPoint(x: 0.875 * w, y: 0.5625 * h)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [10, 10]))
            .foregroundColor(.white)

            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .position(x: 0.125 * w, y: 0.0625 * h)

            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .position(x: 0.875 * w, y: 0.9375 * h)
        }
    }
}

private struct SplashWShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 180
        let sy = rect.height / 180

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        path.move(to: p(40, 50))
        path.addLine(to: p(40, 110))
        path.addArc(
            center: p(60, 110),
            radius: 20 * min(sx, sy),
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: p(80, 80))
        path.addArc(
            center: p(90, 80),
            radius: 10 * min(sx, sy),
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: p(100, 110))
        path.addArc(
            center: p(120, 110),
            radius: 20 * min(sx, sy),
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: p(140, 50))

        return path
    }
}

private struct SplashPixelRunner: View {
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let u = proxy.size.width / 12

            ZStack(alignment: .topLeading) {
                // Hair
                Rectangle().fill(accent).frame(width: 6 * u, height: 2 * u).offset(x: 3 * u, y: 1 * u)
                Rectangle().fill(accent).frame(width: 1 * u, height: 3 * u).offset(x: 2 * u, y: 2 * u)
                Rectangle().fill(accent).frame(width: 1 * u, height: 3 * u).offset(x: 9 * u, y: 2 * u)

                // Body and legs
                Rectangle().fill(.white).frame(width: 6 * u, height: 5 * u).offset(x: 3 * u, y: 3 * u)
                Rectangle().fill(.white).frame(width: 1 * u, height: 2 * u).offset(x: 4 * u, y: 8 * u)
                Rectangle().fill(.white).frame(width: 1 * u, height: 2 * u).offset(x: 7 * u, y: 8 * u)

                // Eyes
                Rectangle().fill(brandGreen).frame(width: 1 * u, height: 1 * u).offset(x: 4 * u, y: 4 * u)
                Rectangle().fill(brandGreen).frame(width: 1 * u, height: 1 * u).offset(x: 7 * u, y: 4 * u)
            }
        }
    }

    private let brandGreen = Color(red: 0.0, green: 182.0 / 255.0, blue: 122.0 / 255.0)
}
