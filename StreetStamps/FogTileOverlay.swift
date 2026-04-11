//
//  FogTileOverlay.swift
//  StreetStamps
//
//  Fog-of-war overlay using a pre-rendered bitmap.
//  MKOverlayRenderer.draw() is synchronous — MapKit blocks until it returns,
//  so there are NO loading artifacts or tile-pop flicker.
//

import MapKit
import CoreGraphics
import UIKit

// MARK: - Overlay (declares world coverage)

final class FogMapOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 0, longitude: 0) }
    var boundingMapRect: MKMapRect { .world }
}

// MARK: - Renderer (blits pre-rendered bitmap, always synchronous)

final class FogOverlayRenderer: MKOverlayRenderer {
    private let fogBitmap: CGImage
    private let fogColor: CGColor
    private let bw: Double
    private let bh: Double

    init(overlay: MKOverlay, fogBitmap: CGImage, fogColor: UIColor) {
        self.fogBitmap = fogBitmap
        self.fogColor = fogColor.cgColor
        self.bw = Double(fogBitmap.width)
        self.bh = Double(fogBitmap.height)
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let drawRect = self.rect(for: mapRect)

        let worldW = MKMapSize.world.width
        let worldH = MKMapSize.world.height

        // Source rect in bitmap pixel coordinates
        let srcX = floor(mapRect.origin.x / worldW * bw)
        let srcY = floor(mapRect.origin.y / worldH * bh)
        let srcW = ceil(mapRect.size.width / worldW * bw) + 1
        let srcH = ceil(mapRect.size.height / worldH * bh) + 1

        let clampedX = max(0, min(srcX, bw - 1))
        let clampedY = max(0, min(srcY, bh - 1))
        let clampedW = min(srcW, bw - clampedX)
        let clampedH = min(srcH, bh - clampedY)

        guard clampedW > 0, clampedH > 0,
              let cropped = fogBitmap.cropping(to: CGRect(x: clampedX, y: clampedY,
                                                          width: clampedW, height: clampedH))
        else {
            // Fallback: solid fog
            context.setFillColor(fogColor)
            context.fill(drawRect)
            return
        }

        // MKOverlayRenderer context is UIKit-oriented (origin top-left),
        // but CGContext.draw() places images with origin at bottom-left. Flip.
        context.saveGState()
        context.translateBy(x: drawRect.minX, y: drawRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cropped, in: CGRect(x: 0, y: 0,
                                          width: drawRect.width, height: drawRect.height))
        context.restoreGState()
    }
}

// MARK: - Bitmap Generation

enum FogBitmapGenerator {
    /// Default bitmap size. 4096×4096 ≈ 64MB; ~10km per pixel at equator.
    static let defaultSize = 4096

    static let defaultFogColor = UIColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 0.75)

    /// Pre-render the full-world fog bitmap with routes cleared.
    /// Call on a background thread — takes ~50–200ms depending on data volume.
    static func render(
        coordRuns: [[CLLocationCoordinate2D]],
        fogColor: UIColor = defaultFogColor,
        size: Int = defaultSize
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size, height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip to top-left origin so MKMapPoint Y maps directly to pixel Y.
        // MKMapPoint: Y=0 is top of world. CGContext default: Y=0 is bottom.
        // After this transform, drawing at (px, py) with py=0 → top of image.
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)

        // 1. Fill solid fog
        ctx.setFillColor(fogColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        guard !coordRuns.isEmpty else { return ctx.makeImage() }

        // 2. Erase along routes
        ctx.setBlendMode(.clear)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Brush width in pixels. At 4096 bitmap, 1px ≈ 10km at equator.
        // 0.6px ≈ 6km corridors — thin enough to show individual paths,
        // dense areas still merge naturally via overlapping strokes.
        ctx.setLineWidth(0.6)

        let worldW = MKMapSize.world.width
        let worldH = MKMapSize.world.height
        let s = Double(size)

        for run in coordRuns {
            guard run.count >= 2 else { continue }
            ctx.beginPath()
            for (i, c) in run.enumerated() {
                let mp = MKMapPoint(c)
                let px = mp.x / worldW * s
                let py = mp.y / worldH * s
                if i == 0 {
                    ctx.move(to: CGPoint(x: px, y: py))
                } else {
                    ctx.addLine(to: CGPoint(x: px, y: py))
                }
            }
            ctx.strokePath()
        }

        return ctx.makeImage()
    }
}
