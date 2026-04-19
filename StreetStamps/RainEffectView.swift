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
    var lightBackground: Bool = false

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
                    if lightBackground {
                        // Dark blue-gray rain on light maps
                        switch drop.layer {
                        case 0:
                            color = Color(red: 0.35, green: 0.40, blue: 0.50).opacity(drop.opacity * 0.8)
                        case 1:
                            color = Color(red: 0.30, green: 0.35, blue: 0.48).opacity(drop.opacity * 1.1)
                        default:
                            color = Color(red: 0.25, green: 0.30, blue: 0.45).opacity(drop.opacity * 1.2)
                        }
                    } else {
                        switch drop.layer {
                        case 0:
                            color = Color.white.opacity(drop.opacity * 0.7)
                        case 1:
                            color = Color(white: 0.85).opacity(drop.opacity)
                        default:
                            color = Color(white: 0.9).opacity(drop.opacity)
                        }
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

                    let splashColor = lightBackground
                        ? Color(red: 0.30, green: 0.35, blue: 0.48).opacity(alpha)
                        : Color.white.opacity(alpha)

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

// MARK: - Snow Particle

private struct Snowflake {
    var x: CGFloat       // 0...1 normalized
    var y: CGFloat       // 0...1 normalized
    let speed: CGFloat   // fall speed (points/sec)
    let size: CGFloat    // diameter
    let opacity: CGFloat
    let wobblePhase: CGFloat   // unique per flake
    let wobbleSpeed: CGFloat   // horizontal sway frequency
    let wobbleAmp: CGFloat     // horizontal sway amplitude
    let layer: Int       // 0=far, 1=mid, 2=near
    let rotation: CGFloat
    let rotationSpeed: CGFloat
}

// MARK: - Snow Engine

private final class SnowEngine {
    var flakes: [Snowflake] = []
    var intensity: CGFloat = 0.5
    var windOffset: CGFloat = 0
    var lastUpdate: CFTimeInterval = 0

    private let maxFlakes = 200

    func update(time: CFTimeInterval, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let dt: CGFloat
        if lastUpdate == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = CGFloat(min(time - lastUpdate, 0.05))
        }
        lastUpdate = time

        // Update existing flakes
        flakes = flakes.compactMap { flake in
            var f = flake
            f.y += (f.speed * dt) / size.height

            // Gentle horizontal wobble (sinusoidal sway)
            let wobble = sin(CGFloat(time) * f.wobbleSpeed + f.wobblePhase) * f.wobbleAmp
            f.x += (wobble * dt + windOffset * dt) / size.width

            if f.y > 1.05 { return nil }
            if f.x < -0.1 || f.x > 1.1 { return nil }
            return f
        }

        // Spawn new flakes
        let targetCount = Int(CGFloat(maxFlakes) * intensity)
        let spawnRate = max(1, Int(CGFloat(targetCount) * dt * 2.5))
        let deficit = targetCount - flakes.count
        if deficit > 0 {
            let toSpawn = min(deficit, spawnRate)
            for _ in 0..<toSpawn {
                flakes.append(makeRandomFlake())
            }
        }
    }

    private func makeRandomFlake() -> Snowflake {
        let layer = weightedLayer()
        let config = layerConfig(layer)

        return Snowflake(
            x: CGFloat.random(in: -0.05...1.05),
            y: CGFloat.random(in: -0.2...0.0),
            speed: CGFloat.random(in: config.speedRange),
            size: CGFloat.random(in: config.sizeRange),
            opacity: CGFloat.random(in: config.opacityRange),
            wobblePhase: CGFloat.random(in: 0...(.pi * 2)),
            wobbleSpeed: CGFloat.random(in: 1.5...3.5),
            wobbleAmp: CGFloat.random(in: config.wobbleRange),
            layer: layer,
            rotation: CGFloat.random(in: 0...(.pi * 2)),
            rotationSpeed: CGFloat.random(in: -2...2)
        )
    }

    private func weightedLayer() -> Int {
        let r = CGFloat.random(in: 0...1)
        if r < 0.3 { return 0 }
        if r < 0.7 { return 1 }
        return 2
    }

    private struct LayerConfig {
        let speedRange: ClosedRange<CGFloat>
        let sizeRange: ClosedRange<CGFloat>
        let opacityRange: ClosedRange<CGFloat>
        let wobbleRange: ClosedRange<CGFloat>
    }

    private func layerConfig(_ layer: Int) -> LayerConfig {
        switch layer {
        case 0: // far
            return LayerConfig(
                speedRange: 25...45,
                sizeRange: 2...4,
                opacityRange: 0.15...0.3,
                wobbleRange: 8...15
            )
        case 1: // mid
            return LayerConfig(
                speedRange: 40...70,
                sizeRange: 4...7,
                opacityRange: 0.3...0.55,
                wobbleRange: 12...25
            )
        default: // near
            return LayerConfig(
                speedRange: 60...100,
                sizeRange: 6...11,
                opacityRange: 0.5...0.8,
                wobbleRange: 18...35
            )
        }
    }
}

// MARK: - Snow Effect View

struct SnowEffectView: View {
    let intensity: CGFloat  // 0...1
    let windAngle: CGFloat
    var lightBackground: Bool = false

    @State private var engine = SnowEngine()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                engine.intensity = intensity
                engine.windOffset = sin(windAngle * .pi / 180) * 30
                engine.update(time: time, size: size)

                for flake in engine.flakes {
                    let x = flake.x * size.width
                    let y = flake.y * size.height
                    let r = flake.size / 2.0

                    // Draw a soft circle snowflake with glow
                    let center = CGPoint(x: x, y: y)

                    if lightBackground {
                        // Light map: dark outline ring for visibility, pale blue-gray core
                        let outlineRect = CGRect(
                            x: center.x - r * 1.4,
                            y: center.y - r * 1.4,
                            width: r * 2.8,
                            height: r * 2.8
                        )
                        context.fill(
                            Path(ellipseIn: outlineRect),
                            with: .color(Color(red: 0.55, green: 0.60, blue: 0.70).opacity(flake.opacity * 0.35))
                        )

                        let coreRect = CGRect(
                            x: center.x - r,
                            y: center.y - r,
                            width: flake.size,
                            height: flake.size
                        )
                        context.fill(
                            Path(ellipseIn: coreRect),
                            with: .color(Color(red: 0.75, green: 0.80, blue: 0.88).opacity(flake.opacity * 0.9))
                        )

                        if flake.layer == 2 {
                            let dotR = r * 0.4
                            let dotRect = CGRect(
                                x: center.x - dotR,
                                y: center.y - dotR,
                                width: dotR * 2,
                                height: dotR * 2
                            )
                            context.fill(
                                Path(ellipseIn: dotRect),
                                with: .color(Color(red: 0.65, green: 0.70, blue: 0.80).opacity(min(flake.opacity + 0.15, 1.0)))
                            )
                        }
                    } else {
                        // Dark map: original white particles
                        let glowRect = CGRect(
                            x: center.x - r * 1.5,
                            y: center.y - r * 1.5,
                            width: r * 3,
                            height: r * 3
                        )
                        context.fill(
                            Path(ellipseIn: glowRect),
                            with: .color(Color.white.opacity(flake.opacity * 0.15))
                        )

                        let coreRect = CGRect(
                            x: center.x - r,
                            y: center.y - r,
                            width: flake.size,
                            height: flake.size
                        )
                        context.fill(
                            Path(ellipseIn: coreRect),
                            with: .color(Color.white.opacity(flake.opacity))
                        )

                        if flake.layer == 2 {
                            let dotR = r * 0.4
                            let dotRect = CGRect(
                                x: center.x - dotR,
                                y: center.y - dotR,
                                width: dotR * 2,
                                height: dotR * 2
                            )
                            context.fill(
                                Path(ellipseIn: dotRect),
                                with: .color(Color.white.opacity(min(flake.opacity + 0.2, 1.0)))
                            )
                        }
                    }
                }
            }
        }
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
