import SwiftUI
import Combine
@_spi(Restricted) import MapboxMaps
import Turf
import CoreLocation
import UIKit

typealias MBMapView = MapboxMaps.MapView

/// Per-(journey, day) build artefacts. Same day-bucket with same content-hash
/// produces the same artefacts; we cache keyed by `(journeyId, dayKey)` and
/// avoid rebuilding anything that hasn't changed since the last refresh. This
/// matches the granularity of `LifelogRenderSnapshotBuilder.mergeDaySnapshot`:
/// a passive country run spanning a year is split into ~365 day buckets, and
/// adding a single point today only invalidates today's bucket.
struct GlobeJourneyArtefact: Sendable {
    let hash: String
    let solids: [Solid]
    let arcs: [Turf.LineString]
    let footprints: [Turf.Feature]
    let distanceKm: Double
    let memoryCount: Double

    struct Solid: Sendable {
        let signature: String
        let line: Turf.LineString
    }
}

struct GlobeCacheKey: Hashable, Sendable {
    let journeyId: String
    let dayKey: String   // UTC day index, or "no-time" for legacy points
}

/// Shared across MapboxGlobeView instances so re-entering the Globe screen
/// reuses already-built per-(journeyId, dayKey) artefacts. The cache is keyed
/// by stable journey content hashes, so stale entries are inert: they're
/// either matched (reused) or pruned at the end of each refresh
/// (`cache.filter { seenCacheKeys.contains($0.key) }`).
@MainActor
private enum GlobeArtefactCache {
    static var shared: [GlobeCacheKey: GlobeJourneyArtefact] = [:]
}

private final class GlobeMapViewHolder: ObservableObject {
    let mapView: MBMapView
    @Published var styleLoadRevision: Int = 0
    var renderPayload = GlobeRenderPayload()

    init() {
        // Keep a small but non-zero initial frame; the SwiftUI wrapper below
        // hosts this view and uses autoresizing so the real size lands before
        // CAMetalLayer renders. Don't read `UIScreen.main.bounds` here — on
        // iOS 26 it can return `.zero` during pre-scene init and crash Mapbox
        // with "invalid reuse after initialization failure".
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
    @State private var preserveCameraOnNextStyleLoad = false

    @EnvironmentObject private var cityCache: CityCache

    /// Selected base-map style. Shared with the picker in GlobeViewScreen via
    /// the same AppStorage key, so changing it there reloads the style here.
    @AppStorage("streetstamps.globe.mapTheme") private var themeID = GlobeMapTheme.defaultID
    private var currentTheme: GlobeMapTheme { GlobeMapTheme.theme(for: themeID) }

    // ====== IDs ======
    private let countriesSourceId = "ss-countries-source"
    private let countriesLayerId  = "ss-countries-fill"
    private let countriesBorderLayerId = "ss-countries-border"

    private let footprintsSourceId = "ss-footprints-source"
    private let footprintsLayerId  = "ss-footprints-heat"

    private let routesSourceId     = "ss-routes-source"
    private let routesGlowLayerId  = "ss-routes-glow"     // faint glow under routes
    private let routesLayerId      = "ss-routes-line"     // main route (solid + cross-city arcs)

    private let citiesSourceId     = "ss-cities-source"
    private let citiesGlowLayerId  = "ss-cities-glow"
    private let citiesLayerId      = "ss-cities-symbol"
    private let cityIconId         = "ss-city-pin"

    /// O(1) render signature — SwiftUI evaluates this each render pass and
    /// `.task(id:)` re-fires whenever the value changes. Captures journey
    /// count/identity changes and city count changes without O(n) string building.
    private var renderInputSignature: String {
        let last = journeys.last
        let jSig = "\(journeys.count)|\(last?.id ?? "")|\(last?.coordinates.count ?? 0)|\(last?.endTime?.timeIntervalSince1970 ?? 0)"
        return "\(jSig)||\(cityCache.cachedCities.count)"
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
                    print("🔵 [Globe] task sig: \(renderInputSignature)")
                    mapHolder.syncRenderPayload(
                        journeys: journeys,
                        cachedCities: cityCache.cachedCities
                    )
                    await refreshData()
                    updateCountryGlow()
                }
                .onChange(of: mapHolder.styleLoadRevision) { _, rev in
                    print("🔵 [Globe] onChange styleLoadRevision: \(rev)")
                    Task { await refreshData() }
                    updateCountryGlow()
                    // Don't re-frame on a theme reload — keep the user's view.
                    if preserveCameraOnNextStyleLoad {
                        preserveCameraOnNextStyleLoad = false
                    } else {
                        flyToJourneysIfPossible()
                    }
                }
                .onChange(of: themeID) { _, _ in
                    // Theme switch = full style reload; preserve the camera so
                    // the user stays where they were looking.
                    print("🔵 [Globe] theme changed → \(themeID)")
                    preserveCameraOnNextStyleLoad = true
                    loadGlobeStyle(resetCamera: false)
                }
            // No in-map chrome — GlobeViewScreen owns the header (back + stats).
        }
        // Surround is clean white so the globe floats on white (matching the
        // Profile map card) — crisper than the app's slightly grey off-white.
        .background(Color.white)
    }

    private var mapView: MBMapView { mapHolder.mapView }

    // MARK: - Setup

    private func setup() {
        // Declutter the hero map: hide logo, attribution, scale bar and compass.
        // TRADEOFF: Mapbox's Terms of Service require their attribution/logo to be
        // shown. Hiding them here (per product request) means the required
        // attribution MUST be surfaced elsewhere in the app (Settings/About) to
        // stay compliant. Revisit if Mapbox flags the account.
        mapView.ornaments.options.logo.visibility = .hidden
        mapView.ornaments.options.attributionButton.visibility = .hidden
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .hidden
        loadGlobeStyle(resetCamera: true)
    }

    /// Loads (or reloads) the base style for the active theme, then rebuilds all
    /// overlay layers with that theme's palette. A style reload wipes every
    /// custom layer, so this same path serves the theme-switch case — only the
    /// first setup resets the camera; a theme switch keeps the user's view.
    private func loadGlobeStyle(resetCamera: Bool) {
        let holder = mapHolder
        mapView.mapboxMap.loadStyle(currentTheme.styleURI) { error in
            if let error { print("❌ Map style load error:", error) }

            if resetCamera {
                // far view camera — small globe with white margin around it
                holder.mapView.mapboxMap.setCamera(
                    to: CameraOptions(center: CLLocationCoordinate2D(latitude: 20, longitude: 0), zoom: 0.55)
                )
            }

            // globe projection (enable if available)
            do {
                try holder.mapView.mapboxMap.setProjection(StyleProjection(name: .globe))
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
            applyAppWhiteSpace()
            addSourcesAndLayers()

            // Signal style readiness via reference type — onChange will
            // call refreshData() with the CURRENT (non-captured) journeys.
            DispatchQueue.main.async {
                holder.styleLoadRevision += 1
            }
        }
    }

    /// Paint the globe's surrounding space the app background colour and kill the
    /// star field, so every theme's globe floats on app-white (been-style)
    /// regardless of whether the base style is dark, light or satellite.
    private func applyAppWhiteSpace() {
        let appBG = StyleColor(UIColor.white)
        var atmo = Atmosphere()
        atmo.spaceColor = .constant(appBG)
        atmo.color = .constant(appBG)
        atmo.starIntensity = .constant(0.0)
        // No horizon glow — a clean globe edge with no halo/光晕 around it.
        atmo.horizonBlend = .constant(0.0)
        do {
            try mapView.mapboxMap.setAtmosphere(atmo)
        } catch {
            print("⚠️ setAtmosphere failed:", error)
        }
    }

    private func addFallbackBackground() {
        let map: MapboxMap = mapView.mapboxMap
        do {
            if !map.layerExists(withId: "ss-bg") {
                var bg = BackgroundLayer(id: "ss-bg")
                bg.backgroundColor = .constant(StyleColor(UIColor.white))
                bg.backgroundOpacity = .constant(1.0)
                try map.addLayer(bg, layerPosition: .at(0))
            }
        } catch {
            print("⚠️ add background failed:", error)
        }
    }

    // MARK: - Sources & Layers

    private func addSourcesAndLayers() {
        let map: MapboxMap = mapView.mapboxMap

        // --- Country vector source ---
        if !map.sourceExists(withId: countriesSourceId) {
            var v = VectorSource(id: countriesSourceId)
            v.url = "mapbox://mapbox.country-boundaries-v1"
            try? map.addSource(v)
        }

        // --- GeoJSON sources ---
        if !map.sourceExists(withId: footprintsSourceId) {
            var src = GeoJSONSource(id: footprintsSourceId)
            src.data = .featureCollection(Turf.FeatureCollection(features: []))
            try? map.addSource(src)
        }

        if !map.sourceExists(withId: routesSourceId) {
            var src = GeoJSONSource(id: routesSourceId)
            src.data = .featureCollection(Turf.FeatureCollection(features: []))
            try? map.addSource(src)
        }
        if !map.sourceExists(withId: citiesSourceId) {
            var src = GeoJSONSource(id: citiesSourceId)
            src.data = .featureCollection(Turf.FeatureCollection(features: []))
            try? map.addSource(src)
        }



        // --- Country fill layer (cyan; keep visible when zooming in) ---
        if !map.layerExists(withId: countriesLayerId) {
            var fill = FillLayer(id: countriesLayerId, source: countriesSourceId)
            fill.sourceLayer = "country_boundaries"
            // ✅ do NOT set maxZoom; we want it to remain visible

            fill.fillColor = .constant(StyleColor(currentTheme.countryFill))
            // Peak opacity is per-theme so busy bases (satellite) get a strong
            // enough tint to be obvious, while clean bases stay subtle.
            let maxOp = currentTheme.countryFillMaxOpacity
            fill.fillOpacity = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                0;  maxOp
                2;  maxOp * 0.93
                6;  maxOp * 0.87
                10; maxOp * 0.80
                14; maxOp * 0.73
            })
            fill.fillOutlineColor = .constant(StyleColor(currentTheme.countryFill.withAlphaComponent(0.45)))

            try? map.addLayer(fill)
        }

        // --- Country boundary stroke (always visible) ---
        if !map.layerExists(withId: countriesBorderLayerId) {
            var border = LineLayer(id: countriesBorderLayerId, source: countriesSourceId)
            border.sourceLayer = "country_boundaries"
            border.lineColor = .constant(StyleColor(currentTheme.countryBorder))
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
            try? map.addLayer(border)
        }

        // --- Footprints heatmap (region highlight: light red; never disappears) ---
        if !map.layerExists(withId: footprintsLayerId) {
            var heat = HeatmapLayer(id: footprintsLayerId, source: footprintsSourceId)

            heat.minZoom = 1.8
            heat.maxZoom = 24.0

            // ✅ light red region glow
            heat.heatmapColor = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.heatmapDensity)
                0; UIColor.clear
                0.15; currentTheme.heatTint.withAlphaComponent(0.06)
                0.45; currentTheme.heatTint.withAlphaComponent(0.16)
                0.75; currentTheme.heatTint.withAlphaComponent(0.28)
                1.0; currentTheme.heatTint.withAlphaComponent(0.42)
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

            try? map.addLayer(heat)
        }

        // --- Routes glow (far zoom MUST be visible) ---
        if !map.layerExists(withId: routesGlowLayerId) {
            var glow = LineLayer(id: routesGlowLayerId, source: routesSourceId)
            glow.minZoom = 1.0

            glow.lineColor = .constant(StyleColor(currentTheme.routeColor))
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

            try? map.addLayer(glow)
        }

        // --- Routes main (always visible; zoom in becomes clearer; never disappears) ---
        if !map.layerExists(withId: routesLayerId) {
            var line = LineLayer(id: routesLayerId, source: routesSourceId)
            line.minZoom = 1.0

            line.lineColor = .constant(StyleColor(currentTheme.routeColor))
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

            try? map.addLayer(line)
        }

        // --- City markers: a friendly balloon pin in the theme colour, tip
        // anchored at the city. Re-generated per theme (style reload clears
        // images), so the pin always matches the active highlight colour. ---
        if map.image(withId: cityIconId) == nil {
            try? map.addImage(currentTheme.cityPinImage(), id: cityIconId, sdf: false)
        }
        if !map.layerExists(withId: citiesLayerId) {
            var sym = SymbolLayer(id: citiesLayerId, source: citiesSourceId)
            sym.iconImage = .constant(.name(cityIconId))
            sym.iconAnchor = .constant(.bottom)
            sym.iconAllowOverlap = .constant(true)
            sym.iconIgnorePlacement = .constant(true)
            sym.iconSize = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                1.0; 0.55
                4.0; 0.66
                10.0; 0.82
                14.0; 0.92
            })
            try? map.addLayer(sym)
        }
    }

    // MARK: - Country Filter (iso2)

    private func updateCountryGlow() {
        let overrideISO2 = (visitedCountryISO2Override ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { $0.count == 2 }
        let iso2 = overrideISO2.isEmpty ? visitedISO2FromJourneys(journeys) : overrideISO2

        let map: MapboxMap = mapView.mapboxMap
        guard map.layerExists(withId: countriesLayerId) else { return }

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

            try map.updateLayer(withId: countriesLayerId, type: FillLayer.self) { layer in
                layer.filter = filterExpr
            }
            if map.layerExists(withId: countriesBorderLayerId) {
                try map.updateLayer(withId: countriesBorderLayerId, type: LineLayer.self) { layer in
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
        // ALWAYS the China worldview, regardless of device region. As a
        // China-domiciled app, the map must render Taiwan / disputed borders per
        // the PRC viewpoint for every user — a device-locale-based worldview
        // (e.g. "US") would show Taiwan separate from China, which is not allowed.
        return "CN"
    }

    private func isoFromCityKey(_ cityKey: String?) -> String? {
        guard let cityKey else { return nil }
        let parts = cityKey.split(separator: "|", omittingEmptySubsequences: false)
        guard let raw = parts.last else { return nil }
        let iso = String(raw).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return iso.count == 2 ? iso : nil
    }

    // MARK: - Data

    private func refreshData() async {
        let map: MapboxMap = mapView.mapboxMap
        guard mapHolder.styleLoadRevision > 0,
              map.sourceExists(withId: footprintsSourceId),
              map.sourceExists(withId: citiesSourceId) else {
            print("🔴 [Globe] refreshData SKIPPED: styleRev=\(mapHolder.styleLoadRevision)")
            return
        }

        let payload = mapHolder.renderPayload
        let cacheSnapshot = GlobeArtefactCache.shared

        // True per-day incremental: each (journeyId, dayKey) bucket is
        // independently hashed. Adding a single point today only rebuilds
        // today's bucket; every other day for that same journey is reused.
        let result: (fcs: (Turf.FeatureCollection, Turf.FeatureCollection, Turf.FeatureCollection), cache: [GlobeCacheKey: GlobeJourneyArtefact], stats: (reused: Int, rebuilt: Int)) = await Task.detached(priority: .userInitiated) {
            var cache = cacheSnapshot
            var reused = 0
            var rebuilt = 0

            var seenJourneyIds = Set<String>()
            var seenCacheKeys = Set<GlobeCacheKey>()
            var allFootprints: [Turf.Feature] = []
            var allArcs: [(journeyId: String, distanceKm: Double, memoryCount: Double, line: Turf.LineString)] = []

            struct SolidBucket {
                var line: Turf.LineString
                var count: Int
                var journeyId: String
                var distanceKm: Double
                var memoryCount: Double
            }
            var solidsBySig: [String: SolidBucket] = [:]

            for j in payload.journeys {
                guard !seenJourneyIds.contains(j.id) else { continue }
                seenJourneyIds.insert(j.id)

                let pts = (!j.coordinates.isEmpty ? j.coordinates : j.thumbnailCoordinates)
                guard !pts.isEmpty else { continue }

                let dayBuckets = MapboxGlobeView.partitionCoordsByDay(pts)
                let distanceKm = max(0, j.distance / 1000.0)
                let memoryCount = Double(j.memories.count)

                for (dayKey, dayCoords) in dayBuckets {
                    let key = GlobeCacheKey(journeyId: j.id, dayKey: dayKey)
                    seenCacheKeys.insert(key)

                    let hash = MapboxGlobeView.dayContentHash(dayCoords)
                    let artefact: GlobeJourneyArtefact
                    if let cached = cache[key], cached.hash == hash {
                        artefact = cached
                        reused += 1
                    } else {
                        artefact = MapboxGlobeView.buildArtefactForDay(
                            journeyId: j.id,
                            coords: dayCoords,
                            distanceKm: distanceKm,
                            memoryCount: memoryCount,
                            hash: hash
                        )
                        cache[key] = artefact
                        rebuilt += 1
                    }

                    for fp in artefact.footprints { allFootprints.append(fp) }
                    for arc in artefact.arcs {
                        allArcs.append((j.id, artefact.distanceKm, artefact.memoryCount, arc))
                    }
                    for s in artefact.solids {
                        if var bucket = solidsBySig[s.signature] {
                            bucket.count += 1
                            solidsBySig[s.signature] = bucket
                        } else {
                            solidsBySig[s.signature] = SolidBucket(
                                line: s.line,
                                count: 1,
                                journeyId: j.id,
                                distanceKm: artefact.distanceKm,
                                memoryCount: artefact.memoryCount
                            )
                        }
                    }
                }
            }

            // Drop cache entries for (journey, day) buckets no longer present.
            cache = cache.filter { seenCacheKeys.contains($0.key) }

            // Compute repeat weight across the deduped solid set.
            let p95 = max(1.0, MapboxGlobeView.quantile(solidsBySig.values.map { $0.count }, p: 0.95))

            var routeFeats: [Turf.Feature] = []
            routeFeats.reserveCapacity(solidsBySig.count + allArcs.count)
            for (_, bucket) in solidsBySig {
                let w = min(1.0, log(1.0 + Double(bucket.count)) / log(1.0 + p95))
                var f = Turf.Feature(geometry: .lineString(bucket.line))
                f.properties = [
                    "journeyId": .string(bucket.journeyId),
                    "distanceKm": .number(bucket.distanceKm),
                    "memoryCount": .number(bucket.memoryCount),
                    "repeatWeight": .number(w)
                ]
                routeFeats.append(f)
            }
            for arc in allArcs {
                var f = Turf.Feature(geometry: .lineString(arc.line))
                f.properties = [
                    "journeyId": .string(arc.journeyId),
                    "distanceKm": .number(arc.distanceKm),
                    "memoryCount": .number(arc.memoryCount),
                    "repeatWeight": .number(0.5)
                ]
                routeFeats.append(f)
            }

            let routesFC = Turf.FeatureCollection(features: routeFeats)
            let footprintsFC = Turf.FeatureCollection(features: allFootprints)
            let citiesFC = MapboxGlobeView.makeCitiesFC(from: payload.cachedCities)

            return ((footprintsFC, routesFC, citiesFC), cache, (reused, rebuilt))
        }.value

        guard !Task.isCancelled else { return }

        print("🟢 [Globe] refreshData: journeys=\(payload.journeys.count) reused=\(result.stats.reused) rebuilt=\(result.stats.rebuilt) footprints=\(result.fcs.0.features.count) routes=\(result.fcs.1.features.count) cities=\(result.fcs.2.features.count)")

        GlobeArtefactCache.shared = result.cache
        updateGeoJSONSource(id: footprintsSourceId, fc: result.fcs.0)
        updateGeoJSONSource(id: routesSourceId, fc: result.fcs.1)
        updateGeoJSONSource(id: citiesSourceId, fc: result.fcs.2)
    }

    /// UTC day index since epoch — stable, locale-independent, cheap to compute,
    /// and groups into 24-hour buckets that align with most users' "what did I
    /// do today" mental model.
    nonisolated private static func dayKey(for t: Date) -> String {
        String(Int(t.timeIntervalSince1970 / 86_400))
    }

    /// Partition a coordinate stream into contiguous per-day buckets. Coords
    /// are assumed to be in time order (which is the standard invariant for
    /// recorded GPS streams). Points without `.t` all bucket under "no-time".
    /// Each bucket carries enough overlap for the renderer to draw clean
    /// boundaries — but we accept that a walk crossing midnight will register
    /// as two separate solid runs at the day boundary.
    nonisolated private static func partitionCoordsByDay(_ pts: [CoordinateCodable]) -> [(dayKey: String, coords: [CoordinateCodable])] {
        guard !pts.isEmpty else { return [] }

        var groups: [(String, [CoordinateCodable])] = []
        var currentKey: String = pts[0].t.map { dayKey(for: $0) } ?? "no-time"
        var current: [CoordinateCodable] = [pts[0]]

        for i in 1..<pts.count {
            let p = pts[i]
            let key = p.t.map { dayKey(for: $0) } ?? "no-time"
            if key == currentKey {
                current.append(p)
            } else {
                groups.append((currentKey, current))
                currentKey = key
                current = [p]
            }
        }
        groups.append((currentKey, current))
        return groups
    }

    /// Content hash for a single day's coord slice.
    nonisolated private static func dayContentHash(_ pts: [CoordinateCodable]) -> String {
        guard let first = pts.first, let last = pts.last else { return "empty" }
        let firstT = first.t.map { "\(Int($0.timeIntervalSince1970))" } ?? "nil"
        let lastT = last.t.map { "\(Int($0.timeIntervalSince1970))" } ?? "nil"
        return "\(pts.count)|\(first.lat),\(first.lon),\(firstT)|\(last.lat),\(last.lon),\(lastT)"
    }

    /// Build artefacts for one day's coord slice of one journey. Same expensive
    /// per-point work as before, just scoped to a single bucket so we can cache
    /// stale days indefinitely.
    nonisolated private static func buildArtefactForDay(
        journeyId: String,
        coords pts: [CoordinateCodable],
        distanceKm: Double,
        memoryCount: Double,
        hash: String
    ) -> GlobeJourneyArtefact {
        guard pts.count >= 2 else {
            return GlobeJourneyArtefact(
                hash: hash,
                solids: [],
                arcs: [],
                footprints: [],
                distanceKm: distanceKm,
                memoryCount: memoryCount
            )
        }

        // --- Routes (solids + arcs) via time-aware classifyTransition -----
        var solidRuns: [[CLLocationCoordinate2D]] = []
        var arcPairs: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] = []
        var current: [CLLocationCoordinate2D] = [pts[0].cl]

        for i in 1..<pts.count {
            let prev = pts[i - 1]
            let cur = pts[i]
            let dd = CLLocation(latitude: prev.lat, longitude: prev.lon)
                .distance(from: CLLocation(latitude: cur.lat, longitude: cur.lon))

            switch classifyTransition(prev: prev, cur: cur, distanceMeters: dd) {
            case .continueSolid:
                current.append(cur.cl)
            case .breakSolid:
                if current.count >= 2 { solidRuns.append(current) }
                current = [cur.cl]
            case .arcThenContinue:
                if current.count >= 2 { solidRuns.append(current) }
                arcPairs.append((prev.cl, cur.cl))
                current = [cur.cl]
            }
        }
        if current.count >= 2 { solidRuns.append(current) }

        let solids: [GlobeJourneyArtefact.Solid] = solidRuns.map { run in
            GlobeJourneyArtefact.Solid(signature: routeSignature(run), line: Turf.LineString(run))
        }
        let arcs: [Turf.LineString] = arcPairs.map { (a, b) in
            Turf.LineString(greatCircleArc(a, b))
        }

        // --- Footprints (heatmap ambience) -------------------------------
        var footprints: [Turf.Feature] = []
        let step = max(1, pts.count / 180)
        var i = 0
        while i < pts.count {
            let c = pts[i]
            var f = Turf.Feature(geometry: .point(Turf.Point(CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon))))
            f.properties = ["journeyId": .string(journeyId)]
            footprints.append(f)
            i += step
        }

        return GlobeJourneyArtefact(
            hash: hash,
            solids: solids,
            arcs: arcs,
            footprints: footprints,
            distanceKm: distanceKm,
            memoryCount: memoryCount
        )
    }

    private func updateGeoJSONSource(id: String, fc: Turf.FeatureCollection) {
        let map: MapboxMap = mapView.mapboxMap
        map.updateGeoJSONSource(withId: id, geoJSON: .featureCollection(fc))
    }

    // MARK: - Route helpers

    nonisolated private static func routeSignature(_ coords: [CLLocationCoordinate2D]) -> String {
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
            // ~110m cells: repeated walks of the same street (with GPS variance)
            // collapse to one signature and merge into a single line, instead of
            // stacking into thick parallel "杂线".
            let lat = Int((c.latitude * 1_000).rounded())
            let lon = Int((c.longitude * 1_000).rounded())
            return "\(lat):\(lon)"
        }

        let forward = samples.map(q).joined(separator: "|")
        let backward = samples.reversed().map(q).joined(separator: "|")
        return min(forward, backward)
    }

    nonisolated private static func quantile(_ values: [Int], p: Double) -> Double {
        guard !values.isEmpty else { return 1.0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return Double(sorted[max(0, min(sorted.count - 1, index))])
    }

    /// Great-circle arc between two points, sampled into `points` intermediate coords.
    /// Used to render cross-city jumps as smooth curves along the globe.
    nonisolated private static func greatCircleArc(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D, points: Int = 32) -> [CLLocationCoordinate2D] {
        let total = max(2, points)

        func toVec(_ c: CLLocationCoordinate2D) -> (Double, Double, Double) {
            let lat = c.latitude * .pi / 180
            let lon = c.longitude * .pi / 180
            return (cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
        }
        func toCoord(_ v: (Double, Double, Double)) -> CLLocationCoordinate2D {
            let lon = atan2(v.1, v.0)
            let lat = atan2(v.2, sqrt(v.0 * v.0 + v.1 * v.1))
            return CLLocationCoordinate2D(latitude: lat * 180 / .pi, longitude: lon * 180 / .pi)
        }

        let a = toVec(start); let b = toVec(end)
        let dot = min(1.0, max(-1.0, a.0 * b.0 + a.1 * b.1 + a.2 * b.2))
        let omega = acos(dot)
        if omega < 1e-6 { return [start, end] }
        let sinOmega = sin(omega)

        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(total)
        for idx in 0..<total {
            let t = Double(idx) / Double(total - 1)
            let s0 = sin((1 - t) * omega) / sinOmega
            let s1 = sin(t * omega) / sinOmega
            out.append(toCoord((
                s0 * a.0 + s1 * b.0,
                s0 * a.1 + s1 * b.1,
                s0 * a.2 + s1 * b.2
            )))
        }
        return out
    }

    /// Time-aware gap detection thresholds.
    ///
    /// The key realisation: globe coords are heavily downsampled (RDP via
    /// `TrackRenderAdapter.globeDownsample`). Consecutive kept points can be
    /// minutes apart in time even on a continuously-walked route. So we must NOT
    /// assume "long dt ⇒ gap"; we decide by *velocity*.
    ///
    /// - Any plausible human locomotion speed (slow walk 1 km/h → plane 1000 km/h)
    ///   ⇒ connect (solid) or arc (cross-city), regardless of dt.
    /// - Velocity above plausible max ⇒ GPS error, break.
    /// - Velocity below walking speed with non-trivial dt ⇒ stationary period,
    ///   break so we don't bridge through a coffee-shop sit.
    nonisolated private static let locomotionMinVelocityMps: Double = 0.3      // 1.08 km/h — slower than this ⇒ stationary
    nonisolated private static let implausibleVelocityMps: Double = 280        // 1000 km/h — faster than this ⇒ GPS error
    nonisolated private static let rapidSamplingDtSeconds: Double = 60         // bridge short dt unconditionally
    nonisolated private static let crossCityArcMeters: Double = 50_000         // ≥50 km jump ⇒ render as great-circle arc
    nonisolated private static let fallbackConnectMeters: Double = 2_000       // no-timestamp: connect only if <2km (matches lifelog gapDistanceMeters)

    private enum TransitionDecision {
        case continueSolid    // append cur to current solid run
        case breakSolid       // close current run, start fresh (no connecting line)
        case arcThenContinue  // close current run, emit great-circle arc, start fresh
    }

    /// Decide how to handle the transition from `prev` to `cur`. Uses per-point
    /// timestamps when available; otherwise falls back to a distance heuristic.
    nonisolated private static func classifyTransition(prev: CoordinateCodable, cur: CoordinateCodable, distanceMeters dd: Double) -> TransitionDecision {
        // No timestamp → we can't compute velocity. This is the common case for
        // passive country runs (LifelogAttributedCoordinateRun stores only
        // CLLocationCoordinate2D with no per-point time). Such points are sparse
        // samples with unknown temporal spacing; we must NOT connect them with
        // long straight lines (zigzags across cities). Only connect very close
        // pairs; arc only truly cross-city scale.
        guard let tPrev = prev.t, let tCur = cur.t, tCur > tPrev else {
            if dd < Self.fallbackConnectMeters      { return .continueSolid }
            if dd >= Self.crossCityArcMeters        { return .arcThenContinue }
            // 2–50 km with no timestamps: BREAK. Connecting here (previous
            // attempt) drew spurious "首尾连线" between genuinely separate
            // records that happened to be a few km apart. Better to leave a
            // small gap than invent a line that wasn't walked.
            return .breakSolid
        }

        let dt = tCur.timeIntervalSince(tPrev)
        let v = dd / dt

        // Implausible velocity ⇒ corrupt GPS sample, break.
        if v > Self.implausibleVelocityMps { return .breakSolid }

        // Active locomotion (walking speed up to flight speed) ⇒ user really moved
        // along this pair, regardless of how long dt is. Cross-city scale renders
        // as great-circle arc so the curve looks right on globe.
        if v >= Self.locomotionMinVelocityMps {
            return dd >= Self.crossCityArcMeters ? .arcThenContinue : .continueSolid
        }

        // Very short dt with near-zero motion ⇒ harmless GPS jitter during active
        // tracking. Keep connected.
        if dt < Self.rapidSamplingDtSeconds { return .continueSolid }

        // Long dt + below-walking velocity ⇒ user was stationary (sat somewhere).
        // Don't draw a line bridging the stationary period.
        return .breakSolid
    }

    nonisolated private static func makeCitiesFC(from cached: [CachedCity]) -> Turf.FeatureCollection {
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

        // Generous padding keeps the globe small and floating, with room for
        // the top stats and the bottom style picker.
        let padding = UIEdgeInsets(top: 200, left: 90, bottom: 260, right: 90)
        let mapboxMap: MapboxMap = mapView.mapboxMap
        var cam = mapboxMap.camera(for: bounds, padding: padding, bearing: 0, pitch: 0, maxZoom: nil, offset: nil)

        // keep "far view feel" — cap so the sphere stays small
        if let z = cam.zoom {
            cam.zoom = min(z, 1.5)
        }

        mapView.camera.ease(to: cam, duration: 0.7)
    }
}

// MARK: - UIViewRepresentable

private struct MapboxViewContainer: UIViewRepresentable {
    let mapView: MBMapView

    // Wrap the MapView in a plain UIView with autoresizing so SwiftUI's layout
    // never hands a 0×0 frame directly to the Metal-backed map view. Without
    // this wrapper, iOS 26 logs `CAMetalLayer ignoring invalid setDrawableSize`
    // and the map sometimes never recovers.
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        host.autoresizesSubviews = true
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(mapView)
        return host
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        // If SwiftUI ever resets the bounds to 0×0 mid-flight, restore from the
        // host view's last known non-zero size instead of forwarding 0×0 down to
        // the Metal layer.
        if mapView.bounds.size != uiView.bounds.size,
           uiView.bounds.width > 0, uiView.bounds.height > 0 {
            mapView.frame = uiView.bounds
        }
    }
}
