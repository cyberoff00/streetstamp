import SwiftUI
import MapKit

// MARK: - Prepared Route (pre-converted to MKMapPoints for fast rendering)

struct PreparedRoute {
    let mapPoints: [MKMapPoint]
}

// MARK: - Overlay

/// Covers the entire world. The renderer draws fog + destinationOut holes for routes.
final class FogOfWarOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world

    var preparedRoutes: [PreparedRoute] = []

    /// Convert journey coordinates to MKMapPoints (including GCJ-02 for CN).
    /// Call off the main thread; result is read-only in the renderer.
    func prepare(journeys: [JourneyRoute]) {
        var result: [PreparedRoute] = []
        result.reserveCapacity(journeys.count)

        for journey in journeys {
            let src = journey.thumbnailCoordinates.isEmpty
                ? journey.coordinates
                : journey.thumbnailCoordinates
            guard src.count >= 2 else { continue }

            let applyGCJ = ChinaCoordinateTransform.shouldApplyGCJ(
                countryISO2: journey.countryISO2,
                cityKey: journey.startCityKey ?? journey.cityKey
            )

            let pts: [MKMapPoint] = src.map { c in
                var coord = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
                if applyGCJ { coord = ChinaCoordinateTransform.wgs84ToGcj02(coord) }
                return MKMapPoint(coord)
            }
            result.append(PreparedRoute(mapPoints: pts))
        }

        preparedRoutes = result
    }
}

// MARK: - Renderer

/// Draws fog via a transparency layer, then punches route corridors with .destinationOut.
/// Two passes (glow + core) give soft frosted edges.
final class FogOfWarRenderer: MKOverlayRenderer {

    // Fog darkens the whole world.
    private let fogColor = UIColor(white: 0.04, alpha: 0.82)

    // Core reveal: 8 screen-px wide, capped at ~150 km (so it's visible at globe scale
    // but doesn't swallow entire continents).
    private let corePixelWidth: CGFloat = 8
    private let coreMaxMapPoints: CGFloat = 1_005_000   // ≈150 km

    // Soft outer glow: 22 px, capped at ~350 km.
    private let glowPixelWidth: CGFloat = 22
    private let glowMaxMapPoints: CGFloat = 2_345_000   // ≈350 km
    private let glowAlpha: CGFloat = 0.32

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        guard let fog = overlay as? FogOfWarOverlay else { return }

        let drawRect = rect(for: mapRect)

        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)   // isolated compositing group

        // ── 1. Fill fog ──────────────────────────────────────────────────────────
        ctx.setFillColor(fogColor.cgColor)
        ctx.fill(drawRect)

        // ── 2. Punch holes with destinationOut ───────────────────────────────────
        ctx.setBlendMode(.destinationOut)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let routes = fog.preparedRoutes
        guard !routes.isEmpty else {
            ctx.endTransparencyLayer()
            ctx.restoreGState()
            return
        }

        let coreW  = min(corePixelWidth  / zoomScale, coreMaxMapPoints)
        let glowW  = min(glowPixelWidth  / zoomScale, glowMaxMapPoints)

        // Glow pass – wide, faint → soft frosted edge
        ctx.setAlpha(glowAlpha)
        ctx.setLineWidth(glowW)
        for route in routes {
            if let path = buildPath(route) {
                ctx.addPath(path); ctx.strokePath()
            }
        }

        // Core pass – narrower, fully opaque → clean reveal
        ctx.setAlpha(1.0)
        ctx.setLineWidth(coreW)
        for route in routes {
            if let path = buildPath(route) {
                ctx.addPath(path); ctx.strokePath()
            }
        }

        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func buildPath(_ route: PreparedRoute) -> CGPath? {
        guard route.mapPoints.count >= 2 else { return nil }
        let path = CGMutablePath()
        path.move(to: point(for: route.mapPoints[0]))
        for pt in route.mapPoints.dropFirst() {
            path.addLine(to: point(for: pt))
        }
        return path
    }
}

// MARK: - UIViewRepresentable

struct FogWorldView: View {
    @Binding var isPresented: Bool
    let journeys: [JourneyRoute]
    var showsCloseButton: Bool = true

    @StateObject private var mapHolder = FogMapHolder()

    var body: some View {
        ZStack {
            FogMapContainer(mapHolder: mapHolder)
                .ignoresSafeArea()
                .task(id: journeyToken) {
                    await mapHolder.update(journeys: journeys)
                }
        }
    }

    /// Cheap token for change detection – avoids recomputing on unrelated state updates.
    private var journeyToken: String {
        journeys.map { "\($0.id)|\($0.coordinates.count)|\($0.thumbnailCoordinates.count)" }
            .joined(separator: "||")
    }
}

// MARK: - Map holder (reference type, survives SwiftUI re-renders)

@MainActor
private final class FogMapHolder: NSObject, ObservableObject, MKMapViewDelegate {

    let mapView: MKMapView
    private var activeOverlay: FogOfWarOverlay?

    override init() {
        mapView = MKMapView()
        super.init()
        mapView.delegate = self
        mapView.overrideUserInterfaceStyle = .dark
        mapView.mapType = .mutedStandard
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .excludingAll

        // Show the whole world initially
        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 155, longitudeDelta: 340)
            ),
            animated: false
        )
    }

    func update(journeys: [JourneyRoute]) async {
        // Create fresh overlay and build map points off main thread.
        // The overlay is mutated only before being added to the map,
        // so there's no concurrent read/write between threads.
        let newOverlay = FogOfWarOverlay()
        await Task.detached(priority: .userInitiated) {
            newOverlay.prepare(journeys: journeys)
        }.value

        // Swap overlays on main thread
        if let old = activeOverlay {
            mapView.removeOverlay(old)
        }
        mapView.addOverlay(newOverlay, level: .aboveLabels)
        activeOverlay = newOverlay

        flyToJourneys(journeys)
    }

    private func flyToJourneys(_ journeys: [JourneyRoute]) {
        var allPts: [MKMapPoint] = []
        for j in journeys {
            let src = j.thumbnailCoordinates.isEmpty ? j.coordinates : j.thumbnailCoordinates
            for c in src {
                var coord = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
                if ChinaCoordinateTransform.shouldApplyGCJ(countryISO2: j.countryISO2, cityKey: j.startCityKey ?? j.cityKey) {
                    coord = ChinaCoordinateTransform.wgs84ToGcj02(coord)
                }
                allPts.append(MKMapPoint(coord))
            }
        }
        guard !allPts.isEmpty else { return }

        var rect = MKMapRect(origin: allPts[0], size: MKMapSize(width: 0, height: 0))
        for pt in allPts { rect = rect.union(MKMapRect(origin: pt, size: MKMapSize(width: 0, height: 0))) }

        // Pad and clamp to a "world view feel"
        let padded = rect.insetBy(dx: -rect.size.width * 0.3, dy: -rect.size.height * 0.3)
        let fittedRect = mapView.mapRectThatFits(padded, edgePadding: UIEdgeInsets(top: 60, left: 30, bottom: 80, right: 30))
        let region = MKCoordinateRegion(fittedRect)
        // Keep the "far view" feel — don't zoom in too close (span at least 40°)
        let clampedSpan = MKCoordinateSpan(
            latitudeDelta: max(region.span.latitudeDelta, 40),
            longitudeDelta: max(region.span.longitudeDelta, 80)
        )
        mapView.setRegion(MKCoordinateRegion(center: region.center, span: clampedSpan), animated: true)
    }

    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let fog = overlay as? FogOfWarOverlay {
            return FogOfWarRenderer(overlay: fog)
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

// MARK: - UIViewRepresentable bridge

private struct FogMapContainer: UIViewRepresentable {
    let mapHolder: FogMapHolder

    func makeUIView(context: Context) -> MKMapView { mapHolder.mapView }
    func updateUIView(_ uiView: MKMapView, context: Context) {}
}
