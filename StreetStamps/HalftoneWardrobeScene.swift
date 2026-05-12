import SwiftUI

/// Halftone backdrop for the equipment view.
/// Same dot-matrix language as `HalftoneRoomScene`, intentionally minimal:
/// just back wall + floor + a soft floor rug. The avatar is the focus —
/// no clothes-rack / mirror / hanger decorations (those proved hard to render
/// well with pure Canvas geometry, and a clean backdrop reads better against
/// the colorful avatar layered on top).
/// Pure SwiftUI Canvas, no external assets.
struct HalftoneWardrobeScene: View {
    let inventory: RoomInventory

    init(inventory: RoomInventory = .empty) {
        self.inventory = inventory
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            HalftoneWardrobeRenderer.render(into: &ctx, size: size, inventory: inventory)
        }
        .background(WorldoPalette.parchment)
        .accessibilityHidden(true)
    }
}

// MARK: - Geometry

private struct WardrobeGeometry {
    let size: CGSize

    var spacing: CGFloat { max(3.5, min(size.width, size.height) / 50.0) }
    var dotMax: CGFloat { spacing * 0.62 }

    // Back wall vs floor split (same proportion as HalftoneRoomScene for visual parity).
    var backWall: CGRect { CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.66) }
    var floor: CGRect    { CGRect(x: 0, y: size.height * 0.66, width: size.width, height: size.height * 0.34) }

    // Floor rug: horizontal ellipse band centered under the avatar.
    var rug: CGRect {
        CGRect(x: size.width * 0.18, y: size.height * 0.82,
               width: size.width * 0.64, height: size.height * 0.12)
    }
}

// MARK: - Renderer

private enum HalftoneWardrobeRenderer {
    static func render(into ctx: inout GraphicsContext, size: CGSize, inventory: RoomInventory) {
        let geo = WardrobeGeometry(size: size)

        // 1. Back wall — faint atmospheric gradient (matches HalftoneRoomScene)
        ctx.fill(backWallField(geo), with: .color(WorldoPalette.inkPrimary.opacity(0.08)))

        // 2. Floor — perspective halftone (matches HalftoneRoomScene)
        ctx.fill(floorField(geo), with: .color(WorldoPalette.inkPrimary.opacity(0.16)))

        // 3. Floor rug — ellipse halftone, anchors the avatar visually.
        ctx.fill(rugPaths(geo), with: .color(WorldoPalette.terracotta.opacity(0.55)))
    }

    private static func backWallField(_ geo: WardrobeGeometry) -> Path {
        DotField.path(in: geo.backWall, spacing: geo.spacing * 1.5, maxDot: geo.dotMax * 0.55) { _, y in
            let v = (y - geo.backWall.minY) / geo.backWall.height
            return 0.35 + 0.45 * v
        }
    }

    private static func floorField(_ geo: WardrobeGeometry) -> Path {
        DotField.path(in: geo.floor, spacing: geo.spacing * 1.05, maxDot: geo.dotMax * 0.85) { _, y in
            let v = 1.0 - (y - geo.floor.minY) / geo.floor.height
            return 0.25 + 0.55 * v
        }
    }

    private static func rugPaths(_ geo: WardrobeGeometry) -> Path {
        let rect = geo.rug
        return DotField.path(in: rect, spacing: geo.spacing * 0.85, maxDot: geo.dotMax * 0.9) { x, y in
            let dx = (x - rect.midX) / (rect.width / 2)
            let dy = (y - rect.midY) / (rect.height / 2)
            let r2 = dx * dx + dy * dy
            return max(0, 1 - r2)
        }
    }
}

// MARK: - DotField shim
//
// DotField helpers live in HalftoneRoomScene.swift but are file-private there.
// Mirror just enough surface here to keep this file self-contained.

private enum DotField {
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
}

// MARK: - Preview

#Preview("Wardrobe") {
    HalftoneWardrobeScene(inventory: .preview)
        .aspectRatio(340.0 / 210.0, contentMode: .fit)
        .frame(width: 340)
        .padding(20)
        .background(WorldoPalette.parchment)
}
