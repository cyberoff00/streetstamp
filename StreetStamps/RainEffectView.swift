import SwiftUI

// MARK: - Raindrop Particle

private struct Raindrop {
    var x: CGFloat          // 0...1 normalized
    var y: CGFloat          // 0...1 normalized
    let speed: CGFloat      // points per second
    let length: CGFloat     // visual length
    let opacity: CGFloat
    let thickness: CGFloat
    let windOffset: CGFloat // horizontal drift per second
    let layer: Int          // 0=far, 1=mid, 2=near

    var isSplashing = false
    var splashAge: CGFloat = 0
    var splashX: CGFloat = 0
    var splashY: CGFloat = 0
}

// MARK: - Storm Engine

private final class StormEngine {
    var drops: [Raindrop] = []
    var splashes: [Raindrop] = []
    var intensity: CGFloat = 0.5  // 0...1
    var windAngle: CGFloat = 10   // degrees from vertical
    var lastUpdate: CFTimeInterval = 0

    private let maxDrops = 300

    func update(time: CFTimeInterval, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let dt: CGFloat
        if lastUpdate == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = CGFloat(min(time - lastUpdate, 0.05))
        }
        lastUpdate = time

        let windRad = windAngle * .pi / 180
        let windDx = sin(windRad)

        // Update existing drops
        var newSplashes: [Raindrop] = []
        drops = drops.compactMap { drop in
            var d = drop
            d.y += (d.speed * dt) / size.height
            d.x += (d.windOffset * windDx * dt) / size.width

            if d.y > 1.0 {
                // Spawn splash for near-layer drops
                if d.layer >= 1 && intensity > 0.3 {
                    var splash = d
                    splash.isSplashing = true
                    splash.splashAge = 0
                    splash.splashX = d.x * size.width
                    splash.splashY = size.height - CGFloat.random(in: 0...20)
                    newSplashes.append(splash)
                }
                return nil
            }
            if d.x < -0.05 || d.x > 1.05 { return nil }
            return d
        }

        // Update splashes
        splashes = (splashes + newSplashes).compactMap { splash in
            var s = splash
            s.splashAge += dt
            return s.splashAge < 0.25 ? s : nil
        }

        // Spawn new drops
        let targetCount = Int(CGFloat(maxDrops) * intensity)
        let spawnRate = max(1, Int(CGFloat(targetCount) * dt * 3))
        let deficit = targetCount - drops.count
        if deficit > 0 {
            let toSpawn = min(deficit, spawnRate)
            for _ in 0..<toSpawn {
                drops.append(makeRandomDrop())
            }
        }
    }

    private func makeRandomDrop() -> Raindrop {
        let layer = weightedRandomLayer()
        let config = layerConfig(layer)

        return Raindrop(
            x: CGFloat.random(in: -0.1...1.1),
            y: CGFloat.random(in: -0.3...0.0),
            speed: CGFloat.random(in: config.speedRange),
            length: CGFloat.random(in: config.lengthRange),
            opacity: CGFloat.random(in: config.opacityRange),
            thickness: config.thickness,
            windOffset: CGFloat.random(in: config.windRange),
            layer: layer
        )
    }

    private func weightedRandomLayer() -> Int {
        let r = CGFloat.random(in: 0...1)
        if r < 0.35 { return 0 }      // far (35%)
        if r < 0.75 { return 1 }      // mid (40%)
        return 2                        // near (25%)
    }

    private struct LayerConfig {
        let speedRange: ClosedRange<CGFloat>
        let lengthRange: ClosedRange<CGFloat>
        let opacityRange: ClosedRange<CGFloat>
        let thickness: CGFloat
        let windRange: ClosedRange<CGFloat>
    }

    private func layerConfig(_ layer: Int) -> LayerConfig {
        switch layer {
        case 0: // far — small, slow, faint
            return LayerConfig(
                speedRange: 280...400,
                lengthRange: 6...12,
                opacityRange: 0.08...0.18,
                thickness: 0.5,
                windRange: 15...30
            )
        case 1: // mid
            return LayerConfig(
                speedRange: 450...650,
                lengthRange: 14...22,
                opacityRange: 0.15...0.30,
                thickness: 1.0,
                windRange: 25...50
            )
        default: // near — large, fast, vivid
            return LayerConfig(
                speedRange: 700...950,
                lengthRange: 22...38,
                opacityRange: 0.25...0.45,
                thickness: 1.5,
                windRange: 35...70
            )
        }
    }
}

// MARK: - Rain Effect View

struct RainEffectView: View {
    let intensity: CGFloat  // 0...1
    let windAngle: CGFloat  // degrees from vertical (positive = right)

    @State private var engine = StormEngine()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                engine.intensity = intensity
                engine.windAngle = windAngle
                engine.update(time: time, size: size)

                let windRad = windAngle * .pi / 180

                // Draw rain drops
                for drop in engine.drops {
                    let x = drop.x * size.width
                    let y = drop.y * size.height

                    let dx = sin(windRad) * drop.length
                    let dy = cos(windRad) * drop.length

                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - dx, y: y - dy))

                    let color: Color
                    switch drop.layer {
                    case 0:
                        color = Color.white.opacity(drop.opacity * 0.7)
                    case 1:
                        color = Color(white: 0.85).opacity(drop.opacity)
                    default:
                        color = Color(white: 0.9).opacity(drop.opacity)
                    }

                    context.stroke(
                        path,
                        with: .color(color),
                        style: StrokeStyle(lineWidth: drop.thickness, lineCap: .round)
                    )
                }

                // Draw splashes
                for splash in engine.splashes {
                    let progress = splash.splashAge / 0.25
                    let alpha = (1.0 - progress) * 0.4
                    let radius = 2 + progress * 6

                    let splashColor = Color.white.opacity(alpha)

                    // Center splash
                    let center = CGPoint(x: splash.splashX, y: splash.splashY)
                    let splashRect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius * 0.3,
                        width: radius * 2,
                        height: radius * 0.6
                    )
                    context.fill(
                        Path(ellipseIn: splashRect),
                        with: .color(splashColor)
                    )

                    // Side droplets
                    let spread = radius * 2
                    for i in [-1.0, 1.0] as [CGFloat] {
                        let dx = i * spread * (0.5 + progress * 0.5)
                        let dy = -radius * (1.0 - progress * progress) * 3.0
                        let droplet = CGRect(
                            x: center.x + dx - 1.0,
                            y: center.y + dy - 1.0,
                            width: 2.0,
                            height: 2.0
                        )
                        context.fill(
                            Path(ellipseIn: droplet),
                            with: .color(splashColor.opacity(0.6))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Fog/Mist Overlay

struct FogOverlayView: View {
    let opacity: CGFloat // 0...1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                // Soft fog patches drifting
                let patchCount = 6
                for i in 0..<patchCount {
                    let seed = Double(i) * 137.5
                    let phase = time * 0.02 + seed
                    let x = (sin(phase * 0.7 + seed) * 0.3 + 0.5) * size.width
                    let y = size.height * (0.5 + Double(i) * 0.08)
                    let w = size.width * CGFloat.random(in: 0.4...0.8)
                    let h = size.height * 0.15

                    let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
                    let patchOpacity = opacity * 0.12 * (1.0 + sin(phase) * 0.3)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color.white.opacity(patchOpacity))
                    )
                }
            }
        }
        .blur(radius: 40)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Lightning Flash

struct LightningFlashView: View {
    let active: Bool

    @State private var flashOpacity: Double = 0

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(flashOpacity))
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: active) { _, isActive in
                if isActive { scheduleFlashes() }
            }
            .onAppear {
                if active { scheduleFlashes() }
            }
    }

    private func scheduleFlashes() {
        guard active else { return }

        let delay = Double.random(in: 4...12)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard active else { return }

            // Double flash
            withAnimation(.easeIn(duration: 0.05)) { flashOpacity = 0.3 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeOut(duration: 0.1)) { flashOpacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeIn(duration: 0.04)) { flashOpacity = 0.15 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    withAnimation(.easeOut(duration: 0.15)) { flashOpacity = 0 }
                }
            }

            // Schedule next
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                scheduleFlashes()
            }
        }
    }
}
