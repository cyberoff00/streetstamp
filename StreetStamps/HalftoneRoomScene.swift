import SwiftUI

/// Inventory snapshot that drives the data-aware decorations of `HalftoneRoomScene`.
/// All counts are visually capped inside the renderer; passing very large numbers is safe.
struct RoomInventory: Equatable {
    let journeyCount: Int
    let cityCount: Int
    let countryCount: Int
    let postcardCount: Int
    let levelCount: Int

    init(
        journeyCount: Int,
        cityCount: Int,
        countryCount: Int,
        postcardCount: Int,
        levelCount: Int = 0
    ) {
        self.journeyCount = journeyCount
        self.cityCount = cityCount
        self.countryCount = countryCount
        self.postcardCount = postcardCount
        self.levelCount = levelCount
    }

    static let empty   = RoomInventory(journeyCount: 0,  cityCount: 0,  countryCount: 0, postcardCount: 0, levelCount: 0)
    static let preview = RoomInventory(journeyCount: 47, cityCount: 23, countryCount: 8, postcardCount: 9, levelCount: 5)
}

/// A halftone / dot-matrix backdrop for the profile scene.
/// Designed to sit behind `SofaProfileSceneView`'s avatar layer — does not draw any character.
/// Pure SwiftUI Canvas, no external assets.
struct HalftoneRoomScene: View {
    let inventory: RoomInventory

    init(inventory: RoomInventory = .empty) {
        self.inventory = inventory
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            HalftoneRoomRenderer.render(into: &ctx, size: size, inventory: inventory)
        }
        .background(WorldoPalette.parchment)
        .accessibilityHidden(true)
    }
}

// MARK: - Geometry

private struct RoomGeometry {
    let size: CGSize

    var spacing: CGFloat { max(3.5, min(size.width, size.height) / 50.0) }
    var dotMax: CGFloat { spacing * 0.62 }

    // Back wall vs floor split
    var backWall: CGRect { CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.66) }
    var floor: CGRect    { CGRect(x: 0, y: size.height * 0.66, width: size.width, height: size.height * 0.34) }

    // Wall items — wide-and-short bookshelf centered horizontally, small
    // window on the right. No center decoration.
    var window: CGRect {
        CGRect(x: size.width * 0.64, y: size.height * 0.12,
               width: size.width * 0.26, height: size.height * 0.30)
    }
    // TEMP: bookshelf disabled while exploring a floor-lamp variant.
    // var bookshelf: CGRect {
    //     CGRect(x: size.width * 0.04, y: size.height * 0.20,
    //            width: size.width * 0.12, height: size.height * 0.55)
    // }

    /// Floor lamp standing on the floor, just left of the sofa.
    /// Composed of three sub-rects (shade, pole, base) — see `floorLampPaths`.
    /// Height tuned so the base ends at y ≈ 0.922 — flush with the plant's
    /// pot bottom (`plantPaths` puts the pot bottom at rect.maxY - 5%).
    var floorLamp: CGRect {
        CGRect(x: size.width * 0.05, y: size.height * 0.30,
               width: size.width * 0.12, height: size.height * 0.68)
    }

    // Foreground items
    var sofa: CGRect {
        let w = size.width * 0.64
        return CGRect(x: (size.width - w) / 2, y: size.height * 0.60,
                      width: w, height: size.height * 0.34)
    }
    var plant: CGRect {
        CGRect(x: size.width * 0.85, y: size.height * 0.58,
               width: size.width * 0.11, height: size.height * 0.36)
    }
}

// MARK: - Dot primitives

private enum DotField {
    /// Build a path of small square dots filling `rect`, sized by per-point `density` (0…1).
    static func path(
        in rect: CGRect,
        spacing: CGFloat,
        maxDot: CGFloat,
        density: (CGFloat, CGFloat) -> CGFloat
    ) -> Path {
        var p = Path()
        guard rect.width > 0, rect.height > 0, spacing > 0 else { return p }
        let cols = Int(ceil(rect.width / spacing))
        let rows = Int(ceil(rect.height / spacing))
        for r in 0..<rows {
            for c in 0..<cols {
                let x = rect.minX + (CGFloat(c) + 0.5) * spacing
                let y = rect.minY + (CGFloat(r) + 0.5) * spacing
                let d = max(0, min(1, density(x, y)))
                let s = maxDot * d
                if s > 0.5 {
                    p.addRect(CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s))
                }
            }
        }
        return p
    }

    /// Append a dotted straight line from `a` to `b` to `path`.
    static func dottedLine(
        from a: CGPoint, to b: CGPoint,
        spacing: CGFloat, dot: CGFloat,
        into path: inout Path
    ) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return }
        let count = max(2, Int(len / spacing))
        for i in 0...count {
            let t = CGFloat(i) / CGFloat(count)
            let x = a.x + dx * t
            let y = a.y + dy * t
            path.addRect(CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
        }
    }

    /// Append a dotted rectangle outline to `path`.
    static func dottedRect(
        _ rect: CGRect,
        spacing: CGFloat, dot: CGFloat,
        into path: inout Path
    ) {
        dottedLine(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.minY),
                   spacing: spacing, dot: dot, into: &path)
        dottedLine(from: CGPoint(x: rect.maxX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY),
                   spacing: spacing, dot: dot, into: &path)
        dottedLine(from: CGPoint(x: rect.maxX, y: rect.maxY), to: CGPoint(x: rect.minX, y: rect.maxY),
                   spacing: spacing, dot: dot, into: &path)
        dottedLine(from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.minX, y: rect.minY),
                   spacing: spacing, dot: dot, into: &path)
    }
}

// MARK: - Renderer

private enum HalftoneRoomRenderer {
    static func render(into ctx: inout GraphicsContext, size: CGSize, inventory: RoomInventory) {
        let geo = RoomGeometry(size: size)

        // 1. Back wall — very faint atmosphere
        ctx.fill(backWallField(geo), with: .color(WorldoPalette.inkPrimary.opacity(0.08)))

        // 2. Window — sun glow + frame (drawn before furniture so glow sits behind everything)
        ctx.fill(windowGlow(geo), with: .color(WorldoPalette.lime.opacity(0.55)))
        ctx.fill(windowFrame(geo), with: .color(WorldoPalette.inkPrimary.opacity(0.55)))

        // 3. Floor — perspective halftone
        ctx.fill(floorField(geo), with: .color(WorldoPalette.inkPrimary.opacity(0.16)))

        // 4. Floor lamp (temporarily replacing bookshelf)
        let lamp = floorLampPaths(geo)
        ctx.fill(lamp.glow, with: .color(WorldoPalette.amber.opacity(0.40)))
        ctx.fill(lamp.shade, with: .color(WorldoPalette.terracotta.opacity(0.85)))
        ctx.fill(lamp.pole, with: .color(WorldoPalette.inkPrimary.opacity(0.65)))
        ctx.fill(lamp.base, with: .color(WorldoPalette.inkPrimary.opacity(0.75)))

        // 4-alt. Bookshelf (disabled while exploring floor-lamp variant)
        // let shelf = bookshelfPaths(geo, levelCount: inventory.levelCount)
        // ctx.fill(shelf.frame, with: .color(WorldoPalette.inkPrimary.opacity(0.55)))
        // ctx.fill(shelf.shelves, with: .color(WorldoPalette.inkPrimary.opacity(0.45)))
        // ctx.fill(shelf.books, with: .color(WorldoPalette.signal.opacity(0.85)))

        // 5. Sofa
        let sofa = sofaPaths(geo)
        ctx.fill(sofa.shadow, with: .color(WorldoPalette.inkPrimary.opacity(0.18)))
        ctx.fill(sofa.body, with: .color(WorldoPalette.signal.opacity(0.72)))
        ctx.fill(sofa.cushion, with: .color(WorldoPalette.signal.opacity(0.92)))
        ctx.fill(sofa.outline, with: .color(WorldoPalette.inkPrimary.opacity(0.85)))
        ctx.fill(sofa.pillows, with: .color(WorldoPalette.terracotta.opacity(0.85)))

        // 7. Plant
        let plant = plantPaths(geo)
        ctx.fill(plant.leaves, with: .color(WorldoPalette.signal.opacity(0.7)))
        ctx.fill(plant.pot, with: .color(WorldoPalette.terracotta.opacity(0.85)))
    }

    // MARK: Fields

    private static func backWallField(_ geo: RoomGeometry) -> Path {
        DotField.path(in: geo.backWall, spacing: geo.spacing * 1.5, maxDot: geo.dotMax * 0.55) { _, y in
            let v = (y - geo.backWall.minY) / geo.backWall.height
            return 0.35 + 0.45 * v
        }
    }

    private static func floorField(_ geo: RoomGeometry) -> Path {
        DotField.path(in: geo.floor, spacing: geo.spacing * 1.05, maxDot: geo.dotMax * 0.85) { _, y in
            // Denser at the back (top of the floor strip), sparser at the front
            let v = 1.0 - (y - geo.floor.minY) / geo.floor.height
            return 0.25 + 0.55 * v
        }
    }

    // MARK: Window

    private static func windowGlow(_ geo: RoomGeometry) -> Path {
        let w = geo.window
        let glow = w.insetBy(dx: -w.width * 0.5, dy: -w.height * 0.35)
        return DotField.path(in: glow, spacing: geo.spacing * 0.95, maxDot: geo.dotMax) { x, y in
            let dx = (x - w.midX) / (w.width * 0.85)
            let dy = (y - w.midY) / (w.height * 0.85)
            let r2 = dx * dx + dy * dy
            return max(0, 1 - r2 * 0.85)
        }
    }

    private static func windowFrame(_ geo: RoomGeometry) -> Path {
        var p = Path()
        let w = geo.window
        let s = geo.spacing * 0.85
        let dot = geo.dotMax * 0.95
        DotField.dottedRect(w, spacing: s, dot: dot, into: &p)
        // 2×2 panes
        DotField.dottedLine(from: CGPoint(x: w.midX, y: w.minY), to: CGPoint(x: w.midX, y: w.maxY),
                            spacing: s, dot: dot, into: &p)
        DotField.dottedLine(from: CGPoint(x: w.minX, y: w.midY), to: CGPoint(x: w.maxX, y: w.midY),
                            spacing: s, dot: dot, into: &p)
        return p
    }

    // MARK: Floor Lamp

    private struct FloorLampPaths {
        let shade: Path  // trapezoidal lamp shade at the top
        let pole: Path   // dotted vertical pole
        let base: Path   // flat ellipse on the floor
        let glow: Path   // diffuse light radiating from below the shade
    }

    private static func floorLampPaths(_ geo: RoomGeometry) -> FloorLampPaths {
        let rect = geo.floorLamp
        let centerX = rect.midX

        // Shade — trapezoid (narrow at top, wider at bottom).
        let shadeTopY = rect.minY
        let shadeBottomY = rect.minY + rect.height * 0.20
        let shadeRect = CGRect(x: rect.minX, y: shadeTopY,
                               width: rect.width, height: shadeBottomY - shadeTopY)
        let topInset = rect.width * 0.20
        let shade = DotField.path(in: shadeRect, spacing: geo.spacing * 0.7, maxDot: geo.dotMax * 0.95) { x, y in
            let v = (y - shadeRect.minY) / shadeRect.height
            let inset = topInset * (1 - v)
            return (x >= shadeRect.minX + inset && x <= shadeRect.maxX - inset) ? 1 : 0
        }

        // Pole — dotted vertical line from shade bottom down to base top.
        let baseTopY = rect.minY + rect.height * 0.86
        var pole = Path()
        DotField.dottedLine(
            from: CGPoint(x: centerX, y: shadeBottomY),
            to:   CGPoint(x: centerX, y: baseTopY),
            spacing: geo.spacing * 0.65, dot: geo.dotMax * 0.85, into: &pole
        )

        // Base — flat ellipse sitting on the floor.
        let baseW = rect.width * 0.70
        let baseH = rect.height * 0.06
        let baseRect = CGRect(x: centerX - baseW / 2, y: baseTopY, width: baseW, height: baseH)
        let base = DotField.path(in: baseRect, spacing: geo.spacing * 0.6, maxDot: geo.dotMax) { x, y in
            let dx = (x - baseRect.midX) / (baseRect.width / 2)
            let dy = (y - baseRect.midY) / (baseRect.height / 2)
            return dx * dx + dy * dy <= 1 ? 1 : 0
        }

        // Glow — radial falloff just below the shade.
        let glowCenter = CGPoint(x: centerX, y: shadeBottomY + rect.height * 0.04)
        let glowR = rect.width * 1.3
        let glowRect = CGRect(x: glowCenter.x - glowR, y: glowCenter.y - glowR,
                              width: glowR * 2, height: glowR * 2)
        let glow = DotField.path(in: glowRect, spacing: geo.spacing * 1.0, maxDot: geo.dotMax * 0.75) { x, y in
            let dx = (x - glowCenter.x) / glowR
            let dy = (y - glowCenter.y) / glowR
            let r2 = dx * dx + dy * dy
            return max(0, 1 - r2 * 1.2)
        }

        return FloorLampPaths(shade: shade, pole: pole, base: base, glow: glow)
    }

    // MARK: Bookshelf (disabled while exploring floor-lamp variant)
    /*
    private struct BookshelfPaths { let frame: Path; let shelves: Path; let books: Path }

    private static func bookshelfPaths(_ geo: RoomGeometry, levelCount: Int) -> BookshelfPaths {
        let rect = geo.bookshelf
        let s = geo.spacing * 0.85
        let dot = geo.dotMax * 0.9

        var frame = Path()
        DotField.dottedRect(rect, spacing: s, dot: dot, into: &frame)

        // Tall standing shelf: 5 rows separated by 4 horizontal dividers.
        // Each row is one display slot — future decoration items go here.
        var shelves = Path()
        let rowCount = 5
        let rowH = rect.height / CGFloat(rowCount)
        for i in 1..<rowCount {
            let y = rect.minY + rowH * CGFloat(i)
            DotField.dottedLine(from: CGPoint(x: rect.minX, y: y),
                                to: CGPoint(x: rect.maxX, y: y),
                                spacing: s, dot: dot, into: &shelves)
        }

        // Vertical books on the top 3 rows only (bottom 2 rows reserved for
        // future decoration items). 1 book per user level, filled left-to-right,
        // top-to-bottom. Books are spine-out (tall narrow rectangles) with gaps.
        var books = Path()
        let booksPerRow = 4
        let bookRows = 3                                  // only top 3 rows hold books
        let capacity = booksPerRow * bookRows             // 12 books = level cap
        let bookCount = max(0, min(levelCount, capacity))

        // Narrower spines + larger gaps so the row reads as a few standing
        // books rather than a packed wall of color.
        let bookW = rect.width * 0.09
        let gap = (rect.width - bookW * CGFloat(booksPerRow)) / CGFloat(booksPerRow + 1)

        for i in 0..<bookCount {
            let row = i / booksPerRow                     // 0, 1, 2
            let col = i % booksPerRow                     // 0..3
            let rowBottom = rect.minY + rowH * CGFloat(row + 1)

            // Vertical book: shorter than the row so spines look slim, not stout.
            let seed = (row * 31 + col * 17) % 7
            let bookH = rowH * (0.45 + CGFloat(seed) * 0.04)
            let bx = rect.minX + gap + (bookW + gap) * CGFloat(col)
            let by = rowBottom - bookH - dot * 0.3
            let bookRect = CGRect(x: bx, y: by, width: bookW, height: bookH)
            books.addPath(
                DotField.path(in: bookRect, spacing: geo.spacing * 0.85, maxDot: geo.dotMax * 0.80) { _, _ in 0.95 }
            )
        }

        return BookshelfPaths(frame: frame, shelves: shelves, books: books)
    }
    */

    // MARK: Sofa

    private struct SofaPaths {
        let shadow: Path
        let body: Path
        let cushion: Path
        let outline: Path
        let pillows: Path
    }

    private static func sofaPaths(_ geo: RoomGeometry) -> SofaPaths {
        let rect = geo.sofa
        let dotS = geo.spacing * 0.55
        let dotMax = geo.dotMax * 1.15

        // Shadow under sofa
        let shadowRect = CGRect(x: rect.minX - rect.width * 0.04,
                                y: rect.maxY - rect.height * 0.10,
                                width: rect.width * 1.08, height: rect.height * 0.18)
        let shadow = DotField.path(in: shadowRect, spacing: geo.spacing * 1.1, maxDot: geo.dotMax) { x, y in
            let dx = (x - shadowRect.midX) / (shadowRect.width / 2)
            let dy = (y - shadowRect.midY) / (shadowRect.height / 2)
            return max(0, 1 - dx * dx - dy * dy * 0.5)
        }

        // Body (the rounded back / chassis): top 60% of sofa rect
        let bodyRect = CGRect(x: rect.minX, y: rect.minY,
                              width: rect.width, height: rect.height * 0.62)
        let body = DotField.path(in: bodyRect, spacing: dotS, maxDot: dotMax) { x, y in
            // Round the top corners by softening density near corners
            let cornerR = bodyRect.height * 0.4
            let dx = max(0, max(bodyRect.minX + cornerR - x, x - (bodyRect.maxX - cornerR)))
            let dy = max(0, bodyRect.minY + cornerR - y)
            let cd = (dx * dx + dy * dy).squareRoot()
            if cd > cornerR { return 0 }
            return 1.0
        }

        // Cushion (seat): bottom 50% overlapping body, slightly more saturated
        let cushionRect = CGRect(x: rect.minX - rect.width * 0.02,
                                 y: rect.minY + rect.height * 0.42,
                                 width: rect.width * 1.04,
                                 height: rect.height * 0.36)
        let cushion = DotField.path(in: cushionRect, spacing: dotS, maxDot: dotMax) { x, y in
            let cornerR = cushionRect.height * 0.45
            let dx = max(0,
                         max(cushionRect.minX + cornerR - x,
                             x - (cushionRect.maxX - cornerR)))
            let dy = max(0, cushionRect.minY + cornerR - y)
            let cd = (dx * dx + dy * dy).squareRoot()
            if cd > cornerR { return 0 }
            return 1.0
        }

        // Outline along the top of the body
        var outline = Path()
        DotField.dottedLine(from: CGPoint(x: bodyRect.minX + bodyRect.height * 0.3, y: bodyRect.minY),
                            to:   CGPoint(x: bodyRect.maxX - bodyRect.height * 0.3, y: bodyRect.minY),
                            spacing: geo.spacing * 0.7, dot: geo.dotMax * 0.85, into: &outline)

        // Two pillows
        var pillows = Path()
        let pillowH = rect.height * 0.18
        let pillowW = rect.width * 0.14
        let pillowY = bodyRect.minY + bodyRect.height * 0.18
        let leftPillow = CGRect(x: bodyRect.minX + bodyRect.width * 0.10,
                                y: pillowY, width: pillowW, height: pillowH)
        let rightPillow = CGRect(x: bodyRect.maxX - bodyRect.width * 0.10 - pillowW,
                                 y: pillowY, width: pillowW, height: pillowH)
        for pr in [leftPillow, rightPillow] {
            pillows.addPath(
                DotField.path(in: pr, spacing: geo.spacing * 0.65, maxDot: geo.dotMax * 1.0) { x, y in
                    let cornerR = pr.height * 0.5
                    let dx = max(0, max(pr.minX + cornerR - x, x - (pr.maxX - cornerR)))
                    let dy = max(0, max(pr.minY + cornerR - y, y - (pr.maxY - cornerR)))
                    let cd = (dx * dx + dy * dy).squareRoot()
                    return cd > cornerR ? 0 : 1
                }
            )
        }

        return SofaPaths(shadow: shadow, body: body, cushion: cushion, outline: outline, pillows: pillows)
    }

    // MARK: Plant

    private struct PlantPaths { let pot: Path; let leaves: Path }

    private static func plantPaths(_ geo: RoomGeometry) -> PlantPaths {
        let rect = geo.plant

        // Pot: trapezoid (wider at top, narrower at bottom)
        let potTopY = rect.minY + rect.height * 0.62
        let potBotY = rect.maxY - rect.height * 0.05
        let potRect = CGRect(x: rect.minX, y: potTopY, width: rect.width, height: potBotY - potTopY)
        let pot = DotField.path(in: potRect, spacing: geo.spacing * 0.6, maxDot: geo.dotMax) { x, y in
            // Trapezoid mask
            let v = (y - potRect.minY) / potRect.height           // 0 top → 1 bottom
            let inset = potRect.width * 0.18 * v
            if x < potRect.minX + inset || x > potRect.maxX - inset { return 0 }
            return 1
        }

        // Leaves: 5 organic teardrops fanning upward
        var leaves = Path()
        let centerX = rect.midX
        let baseY = potTopY - rect.height * 0.02
        let leafSpread = rect.width * 0.55
        let leafHeights: [CGFloat] = [0.55, 0.45, 0.62, 0.48, 0.4]
        let leafAngles: [CGFloat] = [-0.55, -0.25, 0.05, 0.30, 0.55]
        for i in 0..<leafAngles.count {
            let h = rect.height * leafHeights[i]
            let a = leafAngles[i]
            let tipX = centerX + sin(a) * leafSpread
            let tipY = baseY - cos(a) * h
            let leafRect = CGRect(
                x: min(centerX, tipX) - rect.width * 0.06,
                y: min(baseY, tipY) - rect.width * 0.02,
                width: abs(tipX - centerX) + rect.width * 0.12,
                height: abs(baseY - tipY) + rect.width * 0.04
            )
            // Density falls off near the tip of the leaf to give a teardrop feel
            leaves.addPath(
                DotField.path(in: leafRect, spacing: geo.spacing * 0.65, maxDot: geo.dotMax) { x, y in
                    let baseToTipX = tipX - centerX
                    let baseToTipY = tipY - baseY
                    let len2 = baseToTipX * baseToTipX + baseToTipY * baseToTipY
                    guard len2 > 0 else { return 0 }
                    let t = ((x - centerX) * baseToTipX + (y - baseY) * baseToTipY) / len2
                    if t < 0 || t > 1 { return 0 }
                    let projX = centerX + baseToTipX * t
                    let projY = baseY + baseToTipY * t
                    let dist = ((x - projX) * (x - projX) + (y - projY) * (y - projY)).squareRoot()
                    let widthAtT = rect.width * 0.13 * sin(.pi * t)
                    if dist > widthAtT { return 0 }
                    return 1
                }
            )
        }

        return PlantPaths(pot: pot, leaves: leaves)
    }
}

// MARK: - Preview

#Preview("Empty room") {
    HalftoneRoomScene(inventory: .empty)
        .aspectRatio(340.0 / 210.0, contentMode: .fit)
        .frame(width: 340)
        .padding(20)
        .background(WorldoPalette.parchment)
}

#Preview("Lived-in room") {
    HalftoneRoomScene(inventory: .preview)
        .aspectRatio(340.0 / 210.0, contentMode: .fit)
        .frame(width: 340)
        .padding(20)
        .background(WorldoPalette.parchment)
}

#Preview("Heavy traveler") {
    HalftoneRoomScene(inventory: RoomInventory(
        journeyCount: 200, cityCount: 80, countryCount: 28, postcardCount: 50
    ))
    .aspectRatio(340.0 / 210.0, contentMode: .fit)
    .frame(width: 340)
    .padding(20)
    .background(WorldoPalette.parchment)
}
