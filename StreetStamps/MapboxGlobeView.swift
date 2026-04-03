import SwiftUI
import MapboxMaps
import Turf
import CoreLocation
import UIKit

typealias MBMapView = MapboxMaps.MapView

private final class GlobeMapViewHolder: ObservableObject {
    let mapView: MBMapView
    @Published var styleLoadRevision: Int = 0
    var renderPayload = GlobeRenderPayload()
    init() {
        self.mapView = MBMapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func syncRenderPayload(journeys: [JourneyRoute], cachedCities: [CachedCity]) {
        renderPayload = GlobeRenderPayload(journeys: journeys, cachedCities: cachedCities)
    }
}

struct GlobeRenderPayload {
    var journeys: [JourneyRoute] = []
    var cachedCities: [CachedCity] = []
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
    var visitedCountryISO2Override: [String]? = nil
    var showsCloseButton: Bool = true

    @StateObject private var mapHolder = GlobeMapViewHolder()
    @State private var didSetup = false

    @EnvironmentObject private var cityCache: CityCache

    // ====== IDs ======
    private let countriesSourceId = "ss-countries-source"
    private let countriesLayerId  = "ss-countries-fill"
    private let countriesBorderLayerId = "ss-countries-border"

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
    private var renderInputSignature: String { "\(journeysRefreshToken)||\(cityRefreshToken)" }

    private var journeysRefreshToken: String {
        journeys.map {
            let end = $0.endTime?.timeIntervalSince1970 ?? 0
            let iso = ($0.countryISO2 ?? "").uppercased()
            return "\($0.id)|\(Int(end))|\($0.coordinates.count)|\($0.thumbnailCoordinates.count)|\(iso)|\($0.distance)"
        }
        .joined(separator: "||")
    }

    private var cityRefreshToken: String {
        cityCache.cachedCities
            .sorted { $0.id < $1.id }
            .map { city in
                let anchorLat = city.anchor?.lat ?? 0
                let anchorLon = city.anchor?.lon ?? 0
                let iso = (city.countryISO2 ?? "").uppercased()
                let isTemporary = city.isTemporary == true ? "1" : "0"
                return "\(city.id)|\(iso)|\(isTemporary)|\(anchorLat)|\(anchorLon)"
            }
            .joined(separator: "||")
    }

    var body: some View {
        ZStack {
            MapboxViewContainer(mapView: mapHolder.mapView)
                .ignoresSafeArea()
                .onAppear {
                    guard !didSetup else { return }
                    didSetup = true
                    setup()
                }
                .task(id: renderInputSignature) {
                    print("🔵 [Globe] task renderInputSignature: \(renderInputSignature.prefix(80))...")
                    mapHolder.syncRenderPayload(
                        journeys: journeys,
                        cachedCities: cityCache.cachedCities
                    )
                    refreshData()
                    updateCountryGlow()
                }
                .onChange(of: mapHolder.styleLoadRevision) { rev in
                    print("🔵 [Globe] onChange styleLoadRevision: \(rev)")
                    refreshData()
                    updateCountryGlow()
                    flyToJourneysIfPossible()
                }

            // Top bar
            VStack {
                HStack {
                    if showsCloseButton {
                        AppCloseButton(style: .circleDark) {
                            isPresented = false
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

        let holder = mapHolder
        mapView.mapboxMap.loadStyleURI(.dark) { _ in
            // far view camera (globe)
            holder.mapView.mapboxMap.setCamera(
                to: CameraOptions(center: CLLocationCoordinate2D(latitude: 20, longitude: 0), zoom: 1.1)
            )

            // globe projection (enable if available)
            do {
                try holder.mapView.mapboxMap.style.setProjection(StyleProjection(name: .globe))
            } catch {
                print("⚠️ projection not available:", error)
            }

            // gestures
            holder.mapView.gestures.options.rotateEnabled = true
            let canZoom = MembershipStore.shared.globeViewEnabled
            holder.mapView.gestures.options.pinchEnabled = canZoom
            holder.mapView.gestures.options.doubleTapToZoomInEnabled = canZoom
            holder.mapView.gestures.options.panEnabled = true

            addFallbackBackground()
            addSourcesAndLayers()

            // Signal style readiness via reference type — onChange will
            // call refreshData() with the CURRENT (non-captured) journeys.
            DispatchQueue.main.async {
                holder.styleLoadRevision += 1
            }
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
                0;  0.30
                2;  0.28
                6;  0.26
                10; 0.24
                14; 0.22
            })
            fill.fillOutlineColor = .constant(StyleColor(UIColor.cyan.withAlphaComponent(0.45)))

            try? style.addLayer(fill)
        }

        // --- Country boundary stroke (always visible) ---
        if !style.layerExists(withId: countriesBorderLayerId) {
            var border = LineLayer(id: countriesBorderLayerId)
            border.source = countriesSourceId
            border.sourceLayer = "country_boundaries"
            border.lineColor = .constant(StyleColor(UIColor.cyan.withAlphaComponent(0.95)))
            border.lineCap = .constant(.round)
            border.lineJoin = .constant(.round)
            border.lineOpacity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                0;  0.85
                2;  0.82
                8;  0.80
                14; 0.78
            })
            border.lineWidth = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                0;  0.8
                3;  1.0
                8;  1.5
                14; 2.2
            })
            try? style.addLayer(border)
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
            line.minZoom = 1.0

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

        // --- Cities glow + pin (always visible, and kept above routes) ---
        if !style.layerExists(withId: citiesGlowLayerId) {
            var glow = CircleLayer(id: citiesGlowLayerId)
            glow.source = citiesSourceId

            glow.circleColor = .constant(StyleColor(UIColor.cyan))
            glow.circleBlur  = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 0.95
                4.0; 0.88
                8.0; 0.82
                14.0; 0.76
            })
            glow.circleRadius = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 10
                3.0; 14
                8.0; 17
                14.0; 19
            })
            glow.circleOpacity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 0.36
                5.0; 0.34
                10.0; 0.32
                14.0; 0.30
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
                3.0; 0.82
                8.0; 0.76
                14.0; 0.72
            })

            sym.iconOpacity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 0.95
                8.0; 0.92
                14.0; 0.90
            })

            sym.iconHaloColor = .constant(StyleColor(UIColor.cyan.withAlphaComponent(0.9)))
            sym.iconHaloWidth = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 1.6
                8.0; 1.4
                14.0; 1.3
            })
            sym.iconHaloBlur = .constant(0.8)

            try? style.addLayer(sym)
        }
    }

    // MARK: - Country Filter (iso2)

    private func updateCountryGlow() {
        let overrideISO2 = (visitedCountryISO2Override ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { $0.count == 2 }
        let iso2 = overrideISO2.isEmpty ? visitedISO2FromJourneys(journeys) : overrideISO2

        let style = mapView.mapboxMap.style
        guard style.layerExists(withId: countriesLayerId) else { return }

        do {
            let worldview = resolvedWorldviewCode()
            let disputedGet = MapboxMaps.Expression(operator: .get, arguments: [.string("disputed")])
            let worldviewGet = MapboxMaps.Expression(operator: .get, arguments: [.string("worldview")])

            let disputedFalse = MapboxMaps.Expression(
                operator: .eq,
                arguments: [.expression(disputedGet), .string("false")]
            )
            let worldviewFilter = MapboxMaps.Expression(
                operator: .any,
                arguments: [
                    .expression(MapboxMaps.Expression(operator: .eq, arguments: [.string("all"), .expression(worldviewGet)])),
                    .expression(MapboxMaps.Expression(operator: .inExpression, arguments: [.string(worldview), .expression(worldviewGet)]))
                ]
            )

            var allFilters: [MapboxMaps.Expression.Argument] = [
                .expression(disputedFalse),
                .expression(worldviewFilter)
            ]
            let isoGet = MapboxMaps.Expression(operator: .get, arguments: [.string("iso_3166_1")])
            if !iso2.isEmpty {
                var args: [MapboxMaps.Expression.Argument] = [.expression(isoGet)]
                for code in iso2 {
                    args.append(.string(code))
                    args.append(.boolean(true))
                }
                args.append(.boolean(false))
                let isoMatch = MapboxMaps.Expression(operator: .match, arguments: args)
                allFilters.append(.expression(isoMatch))
            }
            let filterExpr = MapboxMaps.Expression(operator: .all, arguments: allFilters)

            try style.updateLayer(withId: countriesLayerId, type: FillLayer.self) { layer in
                layer.filter = filterExpr
            }
            if style.layerExists(withId: countriesBorderLayerId) {
                try style.updateLayer(withId: countriesBorderLayerId, type: LineLayer.self) { layer in
                    layer.filter = filterExpr
                }
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
            if let iso = isoFromCityKey(j.startCityKey) {
                set.insert(iso)
            }
            if let iso = isoFromCityKey(j.cityKey) {
                set.insert(iso)
            }
            if let iso = isoFromCityKey(j.endCityKey) {
                set.insert(iso)
            }
        }
        for city in cityCache.cachedCities where city.isTemporary != true {
            if let iso = city.countryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
               iso.count == 2 {
                set.insert(iso)
            }
        }
        return Array(set).sorted()
    }

    private func resolvedWorldviewCode() -> String {
        let supported: Set<String> = ["AR", "CN", "IN", "JP", "MA", "RS", "RU", "TR", "US"]
        let region = Locale.current.region?.identifier.uppercased() ?? "US"
        return supported.contains(region) ? region : "US"
    }

    private func isoFromCityKey(_ cityKey: String?) -> String? {
        guard let cityKey else { return nil }
        let parts = cityKey.split(separator: "|", omittingEmptySubsequences: false)
        guard let raw = parts.last else { return nil }
        let iso = String(raw).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return iso.count == 2 ? iso : nil
    }

    // MARK: - Data

    private func refreshData() {
        guard mapHolder.styleLoadRevision > 0,
              mapView.mapboxMap.style.sourceExists(withId: footprintsSourceId),
              mapView.mapboxMap.style.sourceExists(withId: citiesSourceId) else {
            print("🔴 [Globe] refreshData SKIPPED: styleRev=\(mapHolder.styleLoadRevision) footprintsSrc=\(mapView.mapboxMap.style.sourceExists(withId: footprintsSourceId)) citiesSrc=\(mapView.mapboxMap.style.sourceExists(withId: citiesSourceId))")
            return
        }

        let payload = mapHolder.renderPayload
        let footprintsFC = makeFootprintsFC(journeys: payload.journeys)
        let routesFC = makeRoutesFC(journeys: payload.journeys)
        let citiesFC = makeCitiesFC(from: payload.cachedCities)

        print("🟢 [Globe] refreshData: journeys=\(payload.journeys.count) footprints=\(footprintsFC.features.count) routes=\(routesFC.features.count) cities=\(citiesFC.features.count)")

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

    // MARK: - Route helpers

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

    private func greatCircleArc(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D, points: Int = 32) -> [CLLocationCoordinate2D] {
        let total = max(2, points)

        func toVec(_ c: CLLocationCoordinate2D) -> (Double, Double, Double) {
            let lat = c.latitude * .pi / 180
            let lon = c.longitude * .pi / 180
            let x = cos(lat) * cos(lon)
            let y = cos(lat) * sin(lon)
            let z = sin(lat)
            return (x, y, z)
        }

        func toCoord(_ v: (Double, Double, Double)) -> CLLocationCoordinate2D {
            let lon = atan2(v.1, v.0)
            let hyp = sqrt(v.0 * v.0 + v.1 * v.1)
            let lat = atan2(v.2, hyp)
            return CLLocationCoordinate2D(latitude: lat * 180 / .pi, longitude: lon * 180 / .pi)
        }

        let a = toVec(start)
        let b = toVec(end)
        let dotRaw = a.0 * b.0 + a.1 * b.1 + a.2 * b.2
        let dot = min(1.0, max(-1.0, dotRaw))
        let omega = acos(dot)

        if omega < 1e-6 {
            return [start, end]
        }

        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(total)
        for idx in 0..<total {
            let t = Double(idx) / Double(total - 1)
            let sinOmega = sin(omega)
            let s0 = sin((1 - t) * omega) / sinOmega
            let s1 = sin(t * omega) / sinOmega
            let v = (
                s0 * a.0 + s1 * b.0,
                s0 * a.1 + s1 * b.1,
                s0 * a.2 + s1 * b.2
            )
            out.append(toCoord(v))
        }
        return out
    }

private func makeRoutesFC(journeys: [JourneyRoute]) -> Turf.FeatureCollection {
        var feats: [Turf.Feature] = []
        var seen = Set<String>()
        var solidCounts: [String: Int] = [:]

        struct PendingRouteFeature {
            let line: Turf.LineString
            let journeyId: String
            let isDashed: Bool
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

            let src = (!j.coordinates.isEmpty ? j.coordinates : j.thumbnailCoordinates)
            guard src.count >= 2 else { continue }

            let coords = src.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            let built = RouteRenderingPipeline.buildSegments(
                .init(
                    coordsWGS84: coords,
                    applyGCJForChina: false,
                    gapDistanceMeters: 2_200,
                    countryISO2: j.countryISO2,
                    cityKey: j.startCityKey ?? j.cityKey
                ),
                surface: .canvas
            )

            for seg in built.segments where seg.coords.count >= 2 {
                let isDashed = seg.style == .dashed
                // Flight: dashed segment spanning >= 120km → render as great-circle arc.
                // Short gap (tunnel, brief GPS loss): dashed segment < 120km → render as straight line.
                // Both are rendered; only tiny noise gaps (< gapDistanceMeters) never reach here.
                let spanMeters: Double = {
                    guard let a = seg.coords.first, let b = seg.coords.last else { return 0 }
                    return CLLocation(latitude: a.latitude, longitude: a.longitude)
                        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                }()
                let isFlight = isDashed && spanMeters >= 120_000
                let lineCoords: [CLLocationCoordinate2D]
                if isFlight, let a = seg.coords.first, let b = seg.coords.last {
                    lineCoords = greatCircleArc(a, b)
                } else {
                    lineCoords = seg.coords
                }
                guard lineCoords.count >= 2 else { continue }

                let sig: String? = isDashed ? nil : routeSignature(lineCoords)
                if let sig {
                    solidCounts[sig, default: 0] += 1
                }

                pending.append(
                    PendingRouteFeature(
                        line: Turf.LineString(lineCoords),
                        journeyId: j.id,
                        isDashed: isDashed,
                        isFlight: isFlight,
                        distanceKm: max(0, j.distance / 1000.0),
                        memoryCount: Double(j.memories.count),
                        signature: sig
                    )
                )
            }
        }

        let p95 = max(1.0, quantile(Array(solidCounts.values), p: 0.95))

        for item in pending {
            let repeatWeight: Double = {
                guard let sig = item.signature else { return 0.40 }
                let n = Double(solidCounts[sig, default: 1])
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
                "name": .string(c.displayTitle),
                "iso2": .string(c.countryISO2 ?? "")
            ]
            feats.append(f)
        }

        return Turf.FeatureCollection(features: feats)
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
        for j in mapHolder.renderPayload.journeys {
            let src = (!j.coordinates.isEmpty ? j.coordinates : j.thumbnailCoordinates)
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
