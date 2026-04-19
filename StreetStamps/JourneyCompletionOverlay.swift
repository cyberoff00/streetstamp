import SwiftUI
import CoreLocation

/// Full-screen celebration overlay matching the Worldo splash screen aesthetic:
/// brand green background, W logo, pixel runner, dashed map lines.
struct JourneyCompletionOverlay: View {
    let distance: Double
    let startTime: Date?
    let endTime: Date?
    let coordinates: [CoordinateCodable]

    // MARK: - Brand colors (same as AppSplashView)

    private let brandGreen = Color(red: 0.0, green: 182.0 / 255.0, blue: 122.0 / 255.0)


    // MARK: - Animation state

    @State private var wDrawProgress: CGFloat = 0
    @State private var showTitle = false
    @State private var showStats = false
    @State private var showSaving = false
    @State private var runnerStart = Date()

    // MARK: - Body

    var body: some View {
        GeometryReader { _ in
            ZStack {
                brandGreen.ignoresSafeArea()

                // Background dashed map lines (same as splash)
                CompletionMapLines(coordinates: effectiveCoords)
                    .opacity(0.1)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // W logo with mascot avatar
                    ZStack {
                        CompletionWShape()
                            .trim(from: 0, to: wDrawProgress)
                            .stroke(
                                Color.white,
                                style: StrokeStyle(
                                    lineWidth: 18,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .frame(width: 140, height: 140)
                            .shadow(color: Color.black.opacity(0.05), radius: 2, y: 4)

                        // Same mascot as Live Activity
                        if wDrawProgress >= 1.0 {
                            Image("LiveActivityAvatar")
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 56, height: 56)
                                .offset(x: 0, y: -60)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
                    .frame(width: 140, height: 140)
                    .padding(.bottom, 28)

                    // Title
                    Text(L10n.t("journey_complete_title"))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(-1)
                        .opacity(showTitle ? 1 : 0)
                        .offset(y: showTitle ? 0 : 20)
                        .padding(.bottom, 8)

                    // Saving label
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white.opacity(0.7))
                            .scaleEffect(0.7)
                        Text(L10n.t("journey_finalizing"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .opacity(showSaving ? 1 : 0)
                    .padding(.bottom, 32)

                    // Stats card
                    if showStats {
                        statsCard
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .allowsHitTesting(true)
        .onAppear { runEntrance() }
    }

    // MARK: - Stats card

    private var statsCard: some View {
        HStack(spacing: 0) {
            statColumn(value: formattedDistance, label: L10n.t("journey_stat_distance"))

            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 32)

            statColumn(value: formattedDuration, label: L10n.t("journey_stat_duration"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 50)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Formatters

    private var formattedDistance: String {
        let km = distance / 1000
        return km >= 1
            ? String(format: "%.1f km", km)
            : String(format: "%.0f m", distance)
    }

    private var formattedDuration: String {
        guard let s = startTime, let e = endTime else { return "--" }
        let secs = Int(e.timeIntervalSince(s))
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0
            ? String(format: "%dh %02dm", h, m)
            : String(format: "%d min", max(m, 1))
    }

    // MARK: - Effective coords for background lines

    private var effectiveCoords: [CoordinateCodable] {
        let raw = coordinates
        guard raw.count >= 2 else { return raw }
        let maxPts = 80
        if raw.count <= maxPts { return raw }
        let step = Double(raw.count) / Double(maxPts)
        var result: [CoordinateCodable] = []
        var i: Double = 0
        while Int(i) < raw.count {
            result.append(raw[Int(i)])
            i += step
        }
        if let last = raw.last {
            result.append(last)
        }
        return result
    }

    // MARK: - Animation sequence

    private func runEntrance() {
        Haptics.success()

        // 1. W logo draws in (matching splash timing)
        withAnimation(.easeInOut(duration: 0.8)) {
            wDrawProgress = 1.0
        }

        // 2. Title bounces up (same timingCurve as splash)
        withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.8).delay(0.5)) {
            showTitle = true
        }

        // 3. Saving indicator
        withAnimation(.easeIn(duration: 0.4).delay(0.8)) {
            showSaving = true
        }

        // 4. Stats card slides up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                showStats = true
            }
        }
    }
}

// MARK: - W Shape (same as SplashWShape)

private struct CompletionWShape: Shape {
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

// MARK: - Background map lines using actual route

private struct CompletionMapLines: View {
    let coordinates: [CoordinateCodable]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            // If we have real route coordinates, draw them as dashed background lines
            if coordinates.count >= 2 {
                let points = mapToScreen(coords: coordinates, size: proxy.size)
                Path { path in
                    path.move(to: points[0])
                    for i in 1..<points.count {
                        path.addLine(to: points[i])
                    }
                }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [10, 10]))
                .foregroundColor(.white)
            } else {
                // Fallback: decorative lines like splash
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
            }

            // Dot accents
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

    private func mapToScreen(coords: [CoordinateCodable], size: CGSize) -> [CGPoint] {
        let lats = coords.map(\.lat)
        let lons = coords.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return [] }

        let latRange = max(maxLat - minLat, 1e-5)
        let lonRange = max(maxLon - minLon, 1e-5)

        let inset: CGFloat = 30
        let drawW = size.width - inset * 2
        let drawH = size.height - inset * 2

        let aspect = drawW / drawH
        let coordAspect = CGFloat(lonRange / latRange)

        let scaleX: CGFloat, scaleY: CGFloat, offsetX: CGFloat, offsetY: CGFloat
        if coordAspect > aspect {
            scaleX = drawW
            scaleY = drawW / coordAspect
            offsetX = inset
            offsetY = (drawH - scaleY) / 2 + inset
        } else {
            scaleY = drawH
            scaleX = drawH * coordAspect
            offsetX = (drawW - scaleX) / 2 + inset
            offsetY = inset
        }

        return coords.map { c in
            let nx = CGFloat((c.lon - minLon) / lonRange)
            let ny = CGFloat(1.0 - (c.lat - minLat) / latRange)
            return CGPoint(x: offsetX + nx * scaleX, y: offsetY + ny * scaleY)
        }
    }
}
