import Foundation
import CoreLocation
import UIKit
import MapKit

// =======================================================
// MARK: - Shared route rendering pipeline
// =======================================================

/// A lightweight, shared representation used by MapView / SharingCard / City & Intercity deep views / thumbnails.
struct RenderRouteSegment: Identifiable, Equatable, Sendable {
    enum Style: String, Codable, Equatable, Sendable { case solid, dashed }
    let id: String
    let style: Style
    let coords: [CLLocationCoordinate2D]
}

enum RouteRenderSurface {
    /// MapKit surfaces (MapView, SharingCard snapshot, thumbnails)
    case mapKit
    /// Canvas surfaces in app UI (deep views) — we still return WGS/GCJ adapted coords; drawing happens elsewhere.
    case canvas
    /// Mapbox surfaces — always WGS84, no GCJ-02 offset (Mapbox handles its own China tile offsets).
    case mapbox
}

/// Centralized style tokens so every surface uses the same dash cadence.
enum RouteRenderStyleTokens {
    /// Standard dash used across the app.
    static let dashLengths: [CGFloat] = [10, 10]
    /// Slightly longer dash for "flight" (only used when we intentionally compress a far route to two points).
    static let flightDashLengths: [CGFloat] = [18, 12]
}

/// Shared logic that decides:
/// 1) Whether to compress route into a 2-point "flight-like" segment
/// 2) Which segments are solid vs dashed
/// 3) How to adapt coordinates (WGS->MapKit / WGS->GCJ when needed)
enum RouteRenderingPipeline {

    struct Input {
        var coordsWGS84: [CLLocationCoordinate2D]
        /// Optional country context (authoritative) used to decide GCJ application.
        var countryISO2: String?
        /// Optional canonical city key ("<City>|<ISO2>") used as a fallback.
        var cityKey: String?
        /// If true, apply China GCJ offset for *non-MapKit* surfaces.
        /// MapKit surfaces should use `MapCoordAdapter.forMapKit`.
        var applyGCJForChina: Bool
        /// Conservative gap thresholds. Keep consistent everywhere.
        var gapDistanceMeters: Double

        init(
            coordsWGS84: [CLLocationCoordinate2D],
            applyGCJForChina: Bool,
            gapDistanceMeters: Double = 8_000,
            countryISO2: String? = nil,
            cityKey: String? = nil
        ) {
            self.coordsWGS84 = coordsWGS84
            self.applyGCJForChina = applyGCJForChina
            self.gapDistanceMeters = gapDistanceMeters
            self.countryISO2 = countryISO2
            self.cityKey = cityKey
        }
    }

    private static func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Build solid/dashed segments based on distance only (time isn't always available for cached routes).
    private static func segmentByDistance(coords: [CLLocationCoordinate2D], gapDistanceMeters: Double) -> [RenderRouteSegment] {
        guard coords.count >= 2 else {
            if let c = coords.first {
                return [RenderRouteSegment(id: UUID().uuidString, style: .solid, coords: [c])]
            }
            return []
        }

        var out: [RenderRouteSegment] = []
        var current: [CLLocationCoordinate2D] = [coords[0]]
        var currentStyle: RenderRouteSegment.Style = .solid

        for i in 1..<coords.count {
            let prev = coords[i-1]
            let cur = coords[i]
            let d = distanceMeters(prev, cur)

            let gapLike = d >= gapDistanceMeters

            // If style changes, flush current polyline and start a new segment.
            let newStyle: RenderRouteSegment.Style = gapLike ? .dashed : .solid
            if newStyle != currentStyle, current.count >= 2 {
                out.append(RenderRouteSegment(id: UUID().uuidString, style: currentStyle, coords: current))
                current = [prev]
            }
            currentStyle = newStyle
            current.append(cur)
        }

        if current.count >= 2 {
            out.append(RenderRouteSegment(id: UUID().uuidString, style: currentStyle, coords: current))
        }
        return out
    }

    /// Public entry: returns segments in the coordinate system suitable for the surface.
    static func buildSegments(_ input: Input, surface: RouteRenderSurface) -> (segments: [RenderRouteSegment], isFlightLike: Bool) {
        let clean = input.coordsWGS84.filter { $0.isValid }
        guard clean.count >= 1 else { return ([], false) }

        // Gap detection in segmentByDistance already renders long gaps as dashed.
        // No need for special "flight-like" compression — all surfaces use the same logic.
        let segs = segmentByDistance(coords: clean, gapDistanceMeters: input.gapDistanceMeters)

        // Adapt coordinates per surface.
        let adapted: [RenderRouteSegment] = segs.map { seg in
            let adaptedCoords: [CLLocationCoordinate2D]
            switch surface {
            case .mapKit:
                adaptedCoords = MapCoordAdapter.forMapKit(seg.coords, countryISO2: input.countryISO2, cityKey: input.cityKey)
            case .canvas:
                let shouldApply = input.applyGCJForChina || ChinaCoordinateTransform.shouldApplyGCJ(countryISO2: input.countryISO2, cityKey: input.cityKey)
                adaptedCoords = shouldApply ? seg.coords.map { $0.wgs2gcj } : seg.coords
            case .mapbox:
                // Mapbox uses WGS84 natively — no coordinate adaptation needed.
                adaptedCoords = seg.coords
            }
            return RenderRouteSegment(id: seg.id, style: seg.style, coords: adaptedCoords)
        }

        return (adapted, false)
    }
}


// =======================================================
// MARK: - Shared drawing helpers (MapKit snapshots)
// =======================================================

enum RouteSnapshotDrawer {
    struct Stroke {
        var coreWidth: CGFloat
        init(coreWidth: CGFloat) { self.coreWidth = coreWidth }
    }

    static func draw(
        segments: [RenderRouteSegment],
        isFlightLike: Bool,
        snapshot: MKMapSnapshotter.Snapshot,
        ctx: CGContext,
        coreColor: UIColor,
        stroke: Stroke,
        glowColor: UIColor? = nil,
        isDarkMap: Bool = false
    ) {
        guard segments.count > 0 else { return }

        let glowTint = glowColor ?? coreColor
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for seg in segments {
            guard seg.coords.count >= 2 else { continue }
            let path = UIBezierPath()
            for (i, c) in seg.coords.enumerated() {
                let p = snapshot.point(for: c)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }

            let isGap = seg.style == .dashed
            let mainWidth: CGFloat = isGap ? max(1.0, stroke.coreWidth * 0.45) : stroke.coreWidth
            let glowWidth: CGFloat = mainWidth * (isGap ? 2.2 : 2.5)

            // dash setup
            let dashPattern: [CGFloat]? = isGap ? RouteRenderStyleTokens.dashLengths : nil

            // 1) Glow with shadow blur
            ctx.saveGState()
            if let dp = dashPattern { ctx.setLineDash(phase: 0, lengths: dp) } else { ctx.setLineDash(phase: 0, lengths: []) }
            ctx.setShadow(
                offset: .zero,
                blur: isDarkMap ? 5.0 : 2.0,
                color: glowTint.withAlphaComponent(isDarkMap ? 0.50 : 0.30).cgColor
            )
            ctx.setStrokeColor(glowTint.withAlphaComponent(isGap ? 0.08 : (isDarkMap ? 0.30 : 0.15)).cgColor)
            ctx.setLineWidth(glowWidth)
            ctx.addPath(path.cgPath)
            ctx.strokePath()
            ctx.restoreGState()

            // 2) Main line
            if let dp = dashPattern { ctx.setLineDash(phase: 0, lengths: dp) } else { ctx.setLineDash(phase: 0, lengths: []) }
            ctx.setStrokeColor(coreColor.withAlphaComponent(isGap ? 0.50 : 1.0).cgColor)
            ctx.setLineWidth(mainWidth)
            ctx.addPath(path.cgPath)
            ctx.strokePath()

            // 3) Highlight
            if !isGap {
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.setStrokeColor(UIColor.white.withAlphaComponent(isDarkMap ? 0.45 : 0.25).cgColor)
                ctx.setLineWidth(mainWidth * 0.35)
                ctx.addPath(path.cgPath)
                ctx.strokePath()
            }
        }

        ctx.restoreGState()
    }

    /// Overload accepting a generic coordinate-to-point mapper (used by Mapbox overlay drawing).
    static func draw(
        segments: [RenderRouteSegment],
        isFlightLike: Bool,
        pointForCoordinate: (CLLocationCoordinate2D) -> CGPoint,
        ctx: CGContext,
        coreColor: UIColor,
        stroke: Stroke,
        glowColor: UIColor? = nil,
        isDarkMap: Bool = false
    ) {
        guard segments.count > 0 else { return }

        let glowTint = glowColor ?? coreColor
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for seg in segments {
            guard seg.coords.count >= 2 else { continue }
            let path = UIBezierPath()
            for (i, c) in seg.coords.enumerated() {
                let p = pointForCoordinate(c)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }

            let isGap = seg.style == .dashed
            let mainWidth: CGFloat = isGap ? max(1.0, stroke.coreWidth * 0.45) : stroke.coreWidth
            let glowWidth: CGFloat = mainWidth * (isGap ? 2.2 : 2.5)

            let dashPattern: [CGFloat]? = isGap ? RouteRenderStyleTokens.dashLengths : nil

            ctx.saveGState()
            if let dp = dashPattern { ctx.setLineDash(phase: 0, lengths: dp) } else { ctx.setLineDash(phase: 0, lengths: []) }
            ctx.setShadow(
                offset: .zero,
                blur: isDarkMap ? 5.0 : 2.0,
                color: glowTint.withAlphaComponent(isDarkMap ? 0.50 : 0.30).cgColor
            )
            ctx.setStrokeColor(glowTint.withAlphaComponent(isGap ? 0.08 : (isDarkMap ? 0.30 : 0.15)).cgColor)
            ctx.setLineWidth(glowWidth)
            ctx.addPath(path.cgPath)
            ctx.strokePath()
            ctx.restoreGState()

            if let dp = dashPattern { ctx.setLineDash(phase: 0, lengths: dp) } else { ctx.setLineDash(phase: 0, lengths: []) }
            ctx.setStrokeColor(coreColor.withAlphaComponent(isGap ? 0.50 : 1.0).cgColor)
            ctx.setLineWidth(mainWidth)
            ctx.addPath(path.cgPath)
            ctx.strokePath()

            if !isGap {
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.setStrokeColor(UIColor.white.withAlphaComponent(isDarkMap ? 0.45 : 0.25).cgColor)
                ctx.setLineWidth(mainWidth * 0.35)
                ctx.addPath(path.cgPath)
                ctx.strokePath()
            }
        }

        ctx.restoreGState()
    }

    private static func signature(_ coords: [CLLocationCoordinate2D]) -> String {
        guard let first = coords.first, let last = coords.last else { return UUID().uuidString }
        let stride = max(1, coords.count / 6)
        var samples: [CLLocationCoordinate2D] = [first]
        if coords.count > 2 {
            var i = stride
            while i < coords.count - 1 {
                samples.append(coords[i])
                i += stride
            }
        }
        samples.append(last)

        func q(_ c: CLLocationCoordinate2D) -> String {
            let lat = Int((c.latitude * 2_000).rounded())
            let lon = Int((c.longitude * 2_000).rounded())
            return "\(lat):\(lon)"
        }

        let forward = samples.map(q).joined(separator: "|")
        let backward = samples.reversed().map(q).joined(separator: "|")
        return min(forward, backward)
    }

    private static func quantile(_ values: [Int], p: Double) -> Double {
        guard !values.isEmpty else { return 1.0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return Double(sorted[max(0, min(sorted.count - 1, index))])
    }
}
