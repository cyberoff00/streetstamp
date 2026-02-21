import SwiftUI
import MapboxMaps
import Turf
import CoreLocation
import UIKit

typealias MBMapView = MapboxMaps.MapView

private final class GlobeMapViewHolder: ObservableObject {
    let mapView: MBMapView
    init() {
        self.mapView = MBMapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

// MARK: - MapboxGlobeView (FULL, no city boundary)
// Features:
// - Countries glow (cyan) stays visible when zoom in (never fully disappears)
// - Region highlight uses footprints heatmap (light red)
// - Routes always rendered: far zoom shows very faint route + glow, zoom in becomes clearer
// - No CLGeocoder / no Tilequery / no city boundary polygon

struct MapboxGlobeView: View {
    @Binding var isPresented: Bool
    let journeys: [JourneyRoute]
    var showsCloseButton: Bool = true

    @StateObject private var mapHolder = GlobeMapViewHolder()
    @State private var didSetup = false

    @EnvironmentObject private var cityCache: CityCache

    /// 0...1 → map to Mapbox zoom
    /// default far view: 0
    @State private var zoom01: Double = 0.0

    // ====== IDs ======
    private let countriesSourceId = "ss-countries-source"
    private let countriesLayerId  = "ss-countries-fill"

    private let footprintsSourceId = "ss-footprints-source"
    private let footprintsLayerId  = "ss-footprints-heat"

    private let routesSourceId     = "ss-routes-source"
    private let routesGlowLayerId  = "ss-routes-glow"     // ✅ new (faint glow at far zoom)
    private let routesLayerId      = "ss-routes-line"     // main route
    private let routesFlightLayerId = "ss-routes-flight"  // dashed flight (start→end)
    private let routesFlightGlowLayerId = "ss-routes-flight-glow" // glow under dashed flight

    private let citiesSourceId     = "ss-cities-source"
    private let citiesGlowLayerId  = "ss-cities-glow"
    private let citiesLayerId      = "ss-cities-symbol"
    private let cityIconId         = "ss-city-pin"

    var body: some View {
        ZStack {
            MapboxViewContainer(mapView: mapHolder.mapView)
                .ignoresSafeArea()
                .onAppear {
                    guard !didSetup else { return }
                    didSetup = true
                    setup()
                }
                .onChange(of: journeys.count) { newCount in
                    print("📍 onChange: journeys.count changed to \(newCount)")
                    refreshData()
                    updateCountryGlow()
                }
                .onChange(of: cityCache.cachedCities.count) { _ in
                    print("📍 onChange: cachedCities.count changed")
                    refreshData()
                }

            // Top bar
            VStack {
                HStack {
                    if showsCloseButton {
                        Button { isPresented = false } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.black.opacity(0.28))
                                .clipShape(Circle())
                        }
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }

                    Spacer()

                    Text(L10n.key("globe"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Spacer()
            }

            // Bottom zoom slider
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundColor(.white.opacity(0.7))

                    Slider(value: $zoom01, in: 0...1) { _ in
                        applyZoom(animated: true)
                    }

                    Image(systemName: "plus.magnifyingglass")
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .background(Color.black)
    }

    private var mapView: MBMapView { mapHolder.mapView }

    // MARK: - Setup

    private func setup() {
        mapView.mapboxMap.onEvery(event: .mapLoadingError) { evt in
            print("❌ Map loading error:", evt)
        }
        mapView.mapboxMap.onEvery(event: .styleLoaded) { _ in
            print("✅ styleLoaded")
        }

        mapView.mapboxMap.loadStyleURI(.dark) { _ in
            // far view camera (globe)
            mapView.mapboxMap.setCamera(
                to: CameraOptions(center: CLLocationCoordinate2D(latitude: 20, longitude: 0), zoom: 1.1)
            )

            // globe projection (enable if available)
            do {
                try mapView.mapboxMap.style.setProjection(StyleProjection(name: .globe))
            } catch {
                print("⚠️ projection not available:", error)
            }

            // gestures
            mapView.gestures.options.rotateEnabled = true
            mapView.gestures.options.pinchEnabled = true
            mapView.gestures.options.panEnabled = true

            addFallbackBackground()

            addSourcesAndLayers()
            refreshData()
            updateCountryGlow()

            // default far zoom (zoom01 = 0)
            applyZoom(animated: false)

            // if has data, fly to bounds (still keep far feel)
            flyToJourneysIfPossible()
        }
    }

    private func addFallbackBackground() {
        let style = mapView.mapboxMap.style
        do {
            if !style.layerExists(withId: "ss-bg") {
                var bg = BackgroundLayer(id: "ss-bg")
                bg.backgroundColor = .constant(StyleColor(.black))
                bg.backgroundOpacity = .constant(1.0)
                try style.addLayer(bg, layerPosition: .at(0))
            }
        } catch {
            print("⚠️ add background failed:", error)
        }
    }

    // MARK: - Sources & Layers

    private func addSourcesAndLayers() {
        let style = mapView.mapboxMap.style

        // --- Country vector source ---
        if !style.sourceExists(withId: countriesSourceId) {
            var v = VectorSource()
            v.url = "mapbox://mapbox.country-boundaries-v1"
            try? style.addSource(v, id: countriesSourceId)
        }

        // --- GeoJSON sources ---
        if !style.sourceExists(withId: footprintsSourceId) {
            var src = GeoJSONSource()
            src.data = .featureCollection(Turf.FeatureCollection(features: []))
            try? style.addSource(src, id: footprintsSourceId)
        }

        if !style.sourceExists(withId: routesSourceId) {
            var src = GeoJSONSource()
            src.data = .featureCollection(Turf.FeatureCollection(features: []))
            try? style.addSource(src, id: routesSourceId)
        }
        if !style.sourceExists(withId: citiesSourceId) {
            var src = GeoJSONSource()
            src.data = .featureCollection(Turf.FeatureCollection(features: []))
            try? style.addSource(src, id: citiesSourceId)
        }

        // --- City pin icon ---
        do {
            if style.image(withId: cityIconId) == nil {
                let img = UIImage(systemName: "mappin.circle.fill")?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                if let img {
                    try style.addImage(img, id: cityIconId, sdf: false)
                }
            }
        } catch {
            print("⚠️ add city icon failed:", error)
        }


        // --- Country fill layer (cyan; keep visible when zooming in) ---
        if !style.layerExists(withId: countriesLayerId) {
            var fill = FillLayer(id: countriesLayerId)
            fill.source = countriesSourceId
            fill.sourceLayer = "country_boundaries"
            // ✅ do NOT set maxZoom; we want it to remain visible

            fill.fillColor = .constant(StyleColor(.cyan))
            fill.fillOpacity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                0;  0.22
                2;  0.18
                6;  0.10
                10; 0.06
                14; 0.05
            })
            fill.fillOutlineColor = .constant(StyleColor(UIColor.cyan.withAlphaComponent(0.45)))

            try? style.addLayer(fill)
        }

        // --- Footprints heatmap (region highlight: light red; never disappears) ---
        if !style.layerExists(withId: footprintsLayerId) {
            var heat = HeatmapLayer(id: footprintsLayerId)
            heat.source = footprintsSourceId

            heat.minZoom = 1.8
            heat.maxZoom = 24.0

            // ✅ light red region glow
            heat.heatmapColor = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.heatmapDensity)
                0; UIColor.clear
                0.15; UIColor.systemRed.withAlphaComponent(0.06)
                0.45; UIColor.systemRed.withAlphaComponent(0.16)
                0.75; UIColor.systemRed.withAlphaComponent(0.28)
                1.0; UIColor.systemRed.withAlphaComponent(0.42)
            })

            // ✅ remove red overlay per request
            heat.heatmapOpacity = .constant(0.0)
            // ✅ far view shows soft glow; zoom in becomes slightly stronger but never 0
            heat.heatmapIntensity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.8;  0.70
                4.0;  1.00
                8.0;  1.15
                12.0; 1.05
                16.0; 0.95
            })

            heat.heatmapRadius = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.8;  22
                4.0;  34
                8.0;  46
                12.0; 52
                16.0; 56
            })

            try? style.addLayer(heat)
        }

        
        // --- Cities glow + pin (visible only at far zoom; zoom in fades out) ---
        if !style.layerExists(withId: citiesGlowLayerId) {
            var glow = CircleLayer(id: citiesGlowLayerId)
            glow.source = citiesSourceId

            glow.circleColor = .constant(StyleColor(UIColor.cyan))
            glow.circleBlur  = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 0.95
                4.0; 0.85
                6.0; 0.75
            })
            glow.circleRadius = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 10
                3.0; 14
                5.5; 18
                6.2; 18
            })
            glow.circleOpacity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 0.35
                4.5; 0.24
                5.8; 0.12
                6.2; 0.00
            })

            try? style.addLayer(glow)
        }

        if !style.layerExists(withId: citiesLayerId) {
            var sym = SymbolLayer(id: citiesLayerId)
            sym.source = citiesSourceId

            sym.iconImage = .constant(.name(cityIconId))
            sym.iconAllowOverlap = .constant(true)
            sym.iconIgnorePlacement = .constant(true)

            sym.iconSize = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 0.85
                3.0; 0.80
                5.5; 0.72
                6.2; 0.65
            })

            sym.iconOpacity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 0.95
                4.8; 0.75
                5.9; 0.30
                6.2; 0.00
            })

            sym.iconHaloColor = .constant(StyleColor(UIColor.cyan.withAlphaComponent(0.9)))
            sym.iconHaloWidth = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 1.6
                5.5; 1.2
                6.2; 0.0
            })
            sym.iconHaloBlur = .constant(0.8)

            try? style.addLayer(sym)
        }

        // --- Routes glow (far zoom MUST be visible) ---
        if !style.layerExists(withId: routesGlowLayerId) {
            var glow = LineLayer(id: routesGlowLayerId)
            glow.source = routesSourceId
            glow.minZoom = 1.0

            // Solid routes only (exclude flight dashed)
            glow.filter = Exp(.eq) { Exp(.get) { "isFlight" }; false }

            glow.lineColor = .constant(StyleColor(UIColor(red: 221.0 / 255.0, green: 247.0 / 255.0, blue: 161.0 / 255.0, alpha: 1.0)))
            glow.lineCap = .constant(.round)
            glow.lineJoin = .constant(.round)

            // ✅ boost far-view visibility
            glow.lineOpacity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0;  0.12
                2.5;  0.14
                5.0;  0.12
                9.0;  0.10
                12.0; 0.08
                16.0; 0.06
            })

            glow.lineWidth = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0;  2.0
                5.0;  3.2
                10.0; 7.0
                14.0; 11.0
            })

            glow.lineBlur = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0;  1.4
                5.0;  1.8
                10.0; 2.4
                14.0; 3.2
            })

            try? style.addLayer(glow)
        }

        // --- Flight glow (make dashed flight visible at far zoom) ---
        if !style.layerExists(withId: routesFlightGlowLayerId) {
            var fglow = LineLayer(id: routesFlightGlowLayerId)
            fglow.source = routesSourceId
            fglow.minZoom = 1.0

            fglow.filter = Exp(.eq) { Exp(.get) { "isFlight" }; true }

            fglow.lineColor = .constant(StyleColor(UIColor(red: 221.0 / 255.0, green: 247.0 / 255.0, blue: 161.0 / 255.0, alpha: 1.0)))
            fglow.lineCap = .constant(.round)
            fglow.lineJoin = .constant(.round)

            // Stronger at far zoom so the dashed line doesn't disappear on dark globe
            fglow.lineOpacity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0;  0.16
                3.0;  0.16
                7.0;  0.14
                10.0; 0.11
                14.0; 0.08
            })

            fglow.lineWidth = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0;  2.6
                5.0;  3.8
                10.0; 7.8
                14.0; 11.0
            })

            fglow.lineBlur = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0;  1.6
                5.0;  2.0
                10.0; 2.6
                14.0; 3.4
            })

            try? style.addLayer(fglow)
        }

        // --- Flight routes: ONLY start→end, dashed ---
        if !style.layerExists(withId: routesFlightLayerId) {
            var flight = LineLayer(id: routesFlightLayerId)
            flight.source = routesSourceId
            flight.minZoom = 1.0

            flight.filter = Exp(.eq) { Exp(.get) { "isFlight" }; true }

            flight.lineColor = .constant(StyleColor(UIColor(red: 221.0 / 255.0, green: 247.0 / 255.0, blue: 161.0 / 255.0, alpha: 1.0)))
            flight.lineCap = .constant(.round)
            flight.lineJoin = .constant(.round)

            // Visible at far zoom; zoom in becomes crisp
            flight.lineOpacity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0;  0.62
                3.0;  0.62
                7.0;  0.66
                10.0; 0.76
                14.0; 0.84
            })

            // Dash pattern (flight)
            // Denser dash reads brighter at far zoom
            flight.lineDasharray = .constant([6, 4])

            flight.lineWidth = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0;  1.5
                5.0;  2.0
                10.0; 3.2
                14.0; 5.4
            })

            // A bit of blur to read on globe (still dashed)
            flight.lineBlur = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0;  0.7
                8.0;  0.6
                14.0; 0.5
            })

            try? style.addLayer(flight)
        }


        // --- Routes main (always visible; zoom in becomes clearer; never disappears) ---
        if !style.layerExists(withId: routesLayerId) {
            var line = LineLayer(id: routesLayerId)
            line.source = routesSourceId
            line.minZoom = 1.8

            // Solid routes only (exclude flight dashed)
            line.filter = Exp(.eq) { Exp(.get) { "isFlight" }; false }

            line.lineColor = .constant(StyleColor(UIColor(red: 221.0 / 255.0, green: 247.0 / 255.0, blue: 161.0 / 255.0, alpha: 1.0)))
            line.lineCap = .constant(.round)
            line.lineJoin = .constant(.round)

            line.lineOpacity = .expression(Exp(.interpolate) {
                Exp(.linear)
                Exp(.get) { "repeatWeight" }
                0.0; 0.56
                1.0; 0.90
            })

            line.lineWidth = .expression(Exp(.interpolate) {
                Exp(.linear)
                Exp(.get) { "repeatWeight" }
                0.0; 1.2
                1.0; 2.6
            })

            line.lineBlur = .expression(Exp(.interpolate) {
                Exp(.linear)
                Exp(.get) { "repeatWeight" }
                0.0; 0.35
                1.0; 0.55
            })

            try? style.addLayer(line)
        }
    }

    // MARK: - Country Filter (iso2)

    private func updateCountryGlow() {
        let iso2 = visitedISO2FromJourneys(journeys)

        let style = mapView.mapboxMap.style
        guard style.layerExists(withId: countriesLayerId) else { return }

        let disputedFalse = MapboxMaps.Expression(
            operator: .eq,
            arguments: [
                .expression(.init(operator: .get, arguments: [.string("disputed")])),
                .string("false")
            ]
        )

        let worldviewOK = MapboxMaps.Expression(
            operator: .any,
            arguments: [
                .expression(
                    MapboxMaps.Expression(operator: .eq, arguments: [
                        .expression(MapboxMaps.Expression(operator: .get, arguments: [.string("worldview")])),
                        .string("all")
                    ])
                ),
                .expression(
                    MapboxMaps.Expression(operator: .eq, arguments: [
                        .expression(MapboxMaps.Expression(operator: .get, arguments: [.string("worldview")])),
                        .string("CN")
                    ])
                )
            ]
        )

        let isoGet = MapboxMaps.Expression(operator: .get, arguments: [.string("iso_3166_1")])

        let isoMatch: MapboxMaps.Expression = {
            guard !iso2.isEmpty else {
                return MapboxMaps.Expression(operator: .literal, arguments: [.boolean(false)])
            }
            var args: [MapboxMaps.Expression.Argument] = [.expression(isoGet)]
            for code in iso2 {
                args.append(.string(code))
                args.append(.boolean(true))
            }
            args.append(.boolean(false))
            return MapboxMaps.Expression(operator: .match, arguments: args)
        }()

        let filterExpr = MapboxMaps.Expression(
            operator: .all,
            arguments: [
                .expression(disputedFalse),
                .expression(worldviewOK),
                .expression(isoMatch)
            ]
        )

        do {
            try style.updateLayer(withId: countriesLayerId, type: FillLayer.self) { layer in
                layer.filter = filterExpr
            }
        } catch {
            print("⚠️ updateCountryGlow failed:", error)
        }
    }

    private func visitedISO2FromJourneys(_ journeys: [JourneyRoute]) -> [String] {
        var set = Set<String>()
        for j in journeys {
            if let iso = j.countryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
               iso.count == 2 {
                set.insert(iso)
            }
        }
        return Array(set).sorted()
    }

    // MARK: - Data

    private func refreshData() {
        guard mapView.mapboxMap.style.sourceExists(withId: footprintsSourceId),
              mapView.mapboxMap.style.sourceExists(withId: citiesSourceId) else { return }

        let footprintsFC = makeFootprintsFC(journeys: journeys)
        let routesFC = makeRoutesFC(journeys: journeys)
        let citiesFC = makeCitiesFC(from: cityCache.cachedCities)

        print("✅ footprints:", footprintsFC.features.count,
              "routes:", routesFC.features.count,
              "cities:", citiesFC.features.count)

        updateGeoJSONSource(id: footprintsSourceId, fc: footprintsFC)
        updateGeoJSONSource(id: routesSourceId, fc: routesFC)
        updateGeoJSONSource(id: citiesSourceId, fc: citiesFC)
    }

    private func updateGeoJSONSource(id: String, fc: Turf.FeatureCollection) {
        do {
            try mapView.mapboxMap.style.updateGeoJSONSource(withId: id, geoJSON: .featureCollection(fc))
        } catch {
            do {
                var src = try mapView.mapboxMap.style.source(withId: id, type: GeoJSONSource.self)
                src.data = .featureCollection(fc)
                try mapView.mapboxMap.style.removeSource(withId: id)
                try mapView.mapboxMap.style.addSource(src, id: id)
            } catch {
                print("❌ update source \(id) failed:", error)
            }
        }
    }

    private func makeFootprintsFC(journeys: [JourneyRoute]) -> Turf.FeatureCollection {
        var feats: [Turf.Feature] = []

        for j in journeys {
            let coords = (j.thumbnailCoordinates.isEmpty ? j.coordinates : j.thumbnailCoordinates)
            guard !coords.isEmpty else { continue }

            // Globe only needs ambience; keep sampling
            let step = max(1, coords.count / 180)

            var i = 0
            while i < coords.count {
                let c = coords[i]
                let p = Turf.Point(CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon))
                var f = Turf.Feature(geometry: .point(p))
                f.properties = [
                    "journeyId": .string(j.id)
                ]
                feats.append(f)
                i += step
            }
        }

        return Turf.FeatureCollection(features: feats)
    }

    // MARK: - Route helpers (avoid "teleport" lines)

    private func haversineKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R = 6371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let x = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(x), sqrt(1 - x))
        return R * c
    }

    private func splitByJumps(_ coords: [CLLocationCoordinate2D], maxStepKm: Double) -> [[CLLocationCoordinate2D]] {
        guard coords.count >= 2 else { return [] }
        var parts: [[CLLocationCoordinate2D]] = []
        var cur: [CLLocationCoordinate2D] = [coords[0]]

        for i in 1..<coords.count {
            let prev = coords[i - 1]
            let now = coords[i]
            if haversineKm(prev, now) > maxStepKm {
                if cur.count >= 2 { parts.append(cur) }
                cur = [now]
            } else {
                cur.append(now)
            }
        }

        if cur.count >= 2 { parts.append(cur) }
        return parts
    }

    private func routeSignature(_ coords: [CLLocationCoordinate2D]) -> String {
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
            let lat = Int((c.latitude * 2_000).rounded()) // ~55m
            let lon = Int((c.longitude * 2_000).rounded())
            return "\(lat):\(lon)"
        }

        let forward = samples.map(q).joined(separator: "|")
        let backward = samples.reversed().map(q).joined(separator: "|")
        return min(forward, backward)
    }

    private func quantile(_ values: [Int], p: Double) -> Double {
        guard !values.isEmpty else { return 1.0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return Double(sorted[max(0, min(sorted.count - 1, index))])
    }

    
    private func isLikelyFlightRoute(_ j: JourneyRoute, coords: [CLLocationCoordinate2D]) -> Bool {
        // If the route has different start/end city keys, treat it as flight.
        // (Distance can be 0 or noisy depending on how the journey was recorded.)
        let distKm = max(0, j.distance / 1000.0)

        if let s = j.startCityKey, let e = j.endCityKey,
           !s.isEmpty, !e.isEmpty, s != e {
            return true
        }

        // Heuristics: long distance + sparse points (common for flights)
        if distKm >= 500, coords.count <= 25 {
            return true
        }

        // Heuristics: large step jumps inside points (teleport-like sampling)
        if coords.count >= 2, distKm >= 300 {
            var maxStep = 0.0
            for i in 1..<coords.count {
                maxStep = max(maxStep, haversineKm(coords[i - 1], coords[i]))
            }
            if maxStep >= 120 { // 120km jump between adjacent samples
                return true
            }
        }

        return false
    }

private func makeRoutesFC(journeys: [JourneyRoute]) -> Turf.FeatureCollection {
        var feats: [Turf.Feature] = []
        var seen = Set<String>()
        var nonFlightCounts: [String: Int] = [:]

        struct PendingRouteFeature {
            let line: Turf.LineString
            let journeyId: String
            let isFlight: Bool
            let distanceKm: Double
            let memoryCount: Double
            let signature: String?
        }

        var pending: [PendingRouteFeature] = []

        for j in journeys {
            // Avoid duplicate rendering if the same route appears multiple times in the array.
            guard !seen.contains(j.id) else { continue }
            seen.insert(j.id)

            let src = (j.thumbnailCoordinates.isEmpty ? j.coordinates : j.thumbnailCoordinates)
            guard src.count >= 2 else { continue }

            let coords = src.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            let isFlight = isLikelyFlightRoute(j, coords: coords)

            // ✅ Flight: only start→end, dashed layer will render it.
            if isFlight, let a = coords.first, let b = coords.last {
                pending.append(
                    PendingRouteFeature(
                        line: Turf.LineString([a, b]),
                        journeyId: j.id,
                        isFlight: true,
                        distanceKm: max(0, j.distance / 1000.0),
                        memoryCount: Double(j.memories.count),
                        signature: nil
                    )
                )
                continue
            }

            // ✅ Non-flight: split away "teleport" jumps so we don't draw weird stray lines.
            let parts = splitByJumps(coords, maxStepKm: 180) // tweak if needed
            for p in parts {
                let sig = routeSignature(p)
                nonFlightCounts[sig, default: 0] += 1
                pending.append(
                    PendingRouteFeature(
                        line: Turf.LineString(p),
                        journeyId: j.id,
                        isFlight: false,
                        distanceKm: max(0, j.distance / 1000.0),
                        memoryCount: Double(j.memories.count),
                        signature: sig
                    )
                )
            }
        }

        let p95 = max(1.0, quantile(Array(nonFlightCounts.values), p: 0.95))

        for item in pending {
            let repeatWeight: Double = {
                guard let sig = item.signature else { return 0.12 }
                let n = Double(nonFlightCounts[sig, default: 1])
                return min(1.0, log(1.0 + n) / log(1.0 + p95))
            }()

            var f = Turf.Feature(geometry: .lineString(item.line))
            f.properties = [
                "journeyId": .string(item.journeyId),
                "isFlight": .boolean(item.isFlight),
                "distanceKm": .number(item.distanceKm),
                "memoryCount": .number(item.memoryCount),
                "repeatWeight": .number(repeatWeight)
            ]
            feats.append(f)
        }

        return Turf.FeatureCollection(features: feats)
    }

    private func makeCitiesFC(from cached: [CachedCity]) -> Turf.FeatureCollection {
        var feats: [Turf.Feature] = []
        var seen = Set<String>()

        for c in cached {
            if c.isTemporary == true { continue }
            guard let anchor = c.anchor?.cl else { continue }

            // light de-dupe (adjust precision if needed)
            let key = "\(round(anchor.latitude * 200)/200)-\(round(anchor.longitude * 200)/200)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let p = Turf.Point(anchor)
            var f = Turf.Feature(geometry: .point(p))
            f.properties = [
                "cityId": .string(c.id),
                "name": .string(c.name),
                "iso2": .string(c.countryISO2 ?? "")
            ]
            feats.append(f)
        }

        return Turf.FeatureCollection(features: feats)
    }



    // MARK: - Zoom

    private func applyZoom(animated: Bool) {
        let z = 1.1 + zoom01 * 12.0
        let opts = CameraOptions(zoom: z)

        if animated {
            mapView.camera.ease(to: opts, duration: 0.18)
        } else {
            mapView.mapboxMap.setCamera(to: opts)
        }
    }

    // MARK: - Fit camera to journeys

    private func flyToJourneysIfPossible(attempt: Int = 0) {
        let size = mapView.bounds.size
        let hasValidMapSize = size.width.isFinite && size.height.isFinite && size.width > 1 && size.height > 1
        if !hasValidMapSize {
            guard attempt < 12 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                flyToJourneysIfPossible(attempt: attempt + 1)
            }
            return
        }

        var all: [CLLocationCoordinate2D] = []
        for j in journeys {
            let src = (j.thumbnailCoordinates.isEmpty ? j.coordinates : j.thumbnailCoordinates)
            all.append(contentsOf: src.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
        }
        guard !all.isEmpty else { return }

        var minLat = all[0].latitude, maxLat = all[0].latitude
        var minLon = all[0].longitude, maxLon = all[0].longitude

        for c in all {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }

        let sw = CLLocationCoordinate2D(latitude: minLat, longitude: minLon)
        let ne = CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
        let bounds = CoordinateBounds(southwest: sw, northeast: ne)

        let padding = UIEdgeInsets(top: 120, left: 60, bottom: 140, right: 60)
        var cam = mapView.mapboxMap.camera(for: bounds, padding: padding, bearing: 0, pitch: 0)

        // keep "far view feel"
        if let z = cam.zoom {
            cam.zoom = min(z, 2.2)
        }

        mapView.camera.ease(to: cam, duration: 0.7)
    }
}

// MARK: - UIViewRepresentable

private struct MapboxViewContainer: UIViewRepresentable {
    let mapView: MBMapView
    func makeUIView(context: Context) -> MBMapView { mapView }
    func updateUIView(_ uiView: MBMapView, context: Context) {}
}
