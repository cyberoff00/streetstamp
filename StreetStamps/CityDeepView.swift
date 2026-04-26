import Foundation
import SwiftUI
import MapKit
import CoreLocation

private enum CityDeepPalette {
    static let headerBg = Color(red: 251.0 / 255.0, green: 251.0 / 255.0, blue: 249.0 / 255.0)
}

enum CityDeepMemoryVisibility {
    static let pinVisibilityThreshold: CLLocationDegrees = 0.03

    static func shouldShowPins(latitudeDelta: CLLocationDegrees) -> Bool {
        latitudeDelta < pinVisibilityThreshold
    }

    static func pinAlpha(shouldShowPins: Bool) -> CGFloat {
        shouldShowPins ? 1.0 : 0.0
    }

    static func dotAlpha(shouldShowPins: Bool) -> CGFloat {
        shouldShowPins ? 0.0 : 1.0
    }
}

struct CityDeepView: View {
    @AppStorage(MapLayerStyle.storageKey) private var layerStyleRaw = MapLayerStyle.current.rawValue
    private let cityFocusRadiusMeters: CLLocationDistance = 80_000
    private let cityFocusWindowMeters: CLLocationDistance = 40_000
    private let cityFocusMinPoints = 2
    private let cityFocusWindowMaxPoints = 80
    private let boundaryTrustMaxDistanceMeters: CLLocationDistance = 120_000
    private let boundaryTrustMaxSpanDegrees: CLLocationDegrees = 3.0
    let city: City
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cache: CityCache
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var renderMaskStore: RenderMaskStore
    @ObservedObject private var languagePreference = LanguagePreference.shared

    init(city: City) {
        self.city = city
        _displayTitle = State(initialValue: city.localizedName)
        _activeCityKey = State(initialValue: city.id)
    }

    @State private var displayTitle: String
    @State private var activeCityKey: String
    @State private var cachedJourneys: [JourneyRoute] = []

    @State private var editingMemory: JourneyMemory? = nil
    @State private var showMemoriesOnMap = true
    @State private var isEditingMask: Bool = false
    @State private var editPointTemplates: [EditPointTemplate] = []

    /// Cached edit-point geometry built once per `(cachedJourneys, engine, city)`
    /// session. Per-brush sample re-uses these without re-running
    /// `MapCoordAdapter.forMapKit` over thousands of points.
    fileprivate struct EditPointTemplate {
        let journeyID: String
        let index: Int
        let coord: CLLocationCoordinate2D
        /// True when the next template (within the same journey) is far
        /// enough away that the polyline would render the connector as a
        /// dashed signal-loss segment. Used to extend brush hit-testing onto
        /// dashed lines so brushing the visible dashes also erases them.
        let isDashedSegmentAfter: Bool
    }

    @State private var fittedRegion: MKCoordinateRegion? = nil
    @State private var initialCameraCommand: MapCameraCommand? = nil
    @State private var fetchedBoundaryPolygon: [CLLocationCoordinate2D]? = nil
    @State private var sidebarHideToken = UUID().uuidString

    private var activeCachedCity: CachedCity? {
        cache.cachedCities.first(where: { $0.id == activeCityKey && !($0.isTemporary ?? false) })
    }

    private var effectiveCountryISO2: String? {
        activeCachedCity?.countryISO2 ?? city.countryISO2
    }

    private var effectiveAnchor: CLLocationCoordinate2D? {
        activeCachedCity?.anchor?.cl ?? city.anchor
    }

    private var effectiveBoundaryPolygon: [CLLocationCoordinate2D]? {
        activeCachedCity?.boundary?.map { $0.cl } ?? city.boundaryPolygon
    }

    private var effectiveCityName: String {
        if let cached = activeCachedCity {
            return cached.displayTitle
        }
        return city.localizedName
    }

    private var cityJourneyIDs: Set<String> {
        if let cached = activeCachedCity, !cached.journeyIds.isEmpty {
            return Set(cached.journeyIds)
        }
        return Set(city.journeys.map { $0.id })
    }

    private func buildCurrentJourneys() -> [JourneyRoute] {
        let byId = Dictionary(store.journeys.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let cachedIDs = Array(cityJourneyIDs)
        if !cachedIDs.isEmpty {
            return cachedIDs.compactMap { byId[$0] }
        }
        return city.journeys.compactMap { byId[$0.id] }
    }

    /// `cachedJourneys` with the user's render mask applied. Each masked
    /// region splits its journey into multiple synthetic journeys so the
    /// polyline renders as a true gap (instead of bridging the erased range
    /// with a straight connector line, which would make the eraser useless).
    private var effectiveJourneys: [JourneyRoute] {
        // Touch maskRevision so SwiftUI re-renders when the mask changes.
        _ = renderMaskStore.maskRevision
        return cachedJourneys.flatMap { j in
            j.applyingRenderMaskSplit(renderMaskStore.mask(for: j.id))
        }
    }

    struct Segment {
        let coords: [CLLocationCoordinate2D]
        let isGap: Bool
        let repeatWeight: Double
    }

    private func unifiedSegments(_ coordsWGS: [CLLocationCoordinate2D]) -> [Segment] {
        let built = RouteRenderingPipeline.buildSegments(
            .init(coordsWGS84: coordsWGS, applyGCJForChina: false, gapDistanceMeters: 2_200, countryISO2: effectiveCountryISO2),
            surface: .mapKit
        )
        return built.segments.map { Segment(coords: $0.coords, isGap: $0.style == .dashed, repeatWeight: 0) }
    }

    private var currentEngine: MapEngineSetting {
        (MapLayerStyle(rawValue: layerStyleRaw) ?? .mutedDark).engine
    }

    private func styledSegments() -> [Segment] {
        let surface: RouteRenderSurface = currentEngine == .mapbox ? .mapbox : .mapKit
        return CityDeepRenderEngine
            .styledSegments(
                journeys: effectiveJourneys,
                countryISO2: effectiveCountryISO2,
                cityKey: activeCityKey,
                surface: surface,
                dedupGranularity: .fine
            )
            .map { seg in
                Segment(coords: seg.coords, isGap: seg.isGap, repeatWeight: seg.repeatWeight)
            }
    }

    private func mapSegments() -> [MapRouteSegment] {
        styledSegments().enumerated().map { (i, seg) in
            MapRouteSegment(id: "cd-\(i)", coordinates: seg.coords, isGap: seg.isGap, repeatWeight: seg.repeatWeight)
        }
    }

    private var mapAnnotations: [MapAnnotationItem] {
        guard !isEditingMask, showMemoriesOnMap, store.hasLoaded, !store.isLoading else { return [] }
        return groupedMemories.map { g in
            MapAnnotationItem(id: g.id, coordinate: g.coordinate, kind: .memoryGroup(key: g.key, items: g.items))
        }
    }

    private var mapCircles: [MapCircleOverlay] {
        guard !isEditingMask, showMemoriesOnMap, store.hasLoaded, !store.isLoading else { return [] }
        return memoryDotCoordinates.enumerated().map { (i, coord) in
            MapCircleOverlay(id: "dot-\(i)", center: coord, radiusMeters: 30)
        }
    }

    /// Brush size in screen points. Fixed at this size regardless of zoom so
    /// the brush feels consistent — the engine converts to world meters per
    /// sample at the active projection.
    private static let eraseBrushScreenRadiusPoints: CGFloat = 18

    /// Same threshold the polyline pipeline uses to render gap segments as
    /// dashes (`RouteRenderingPipelineInput.gapDistanceMeters` for CityDeep).
    private static let eraseDashedGapMeters: Double = 2_200

    /// Brush config passed down to the engine. Nil when not editing.
    private var eraseBrush: MapEraseBrush? {
        guard isEditingMask else { return nil }
        return MapEraseBrush(screenRadiusPoints: Self.eraseBrushScreenRadiusPoints)
    }

    /// Build the per-journey point cache used as a spatial lookup target by
    /// brush sweeps. Built once on edit-mode entry / journey change — heavy
    /// `MapCoordAdapter.forMapKit` work doesn't repeat per brush sample.
    private func rebuildEditPointTemplates() {
        guard isEditingMask else {
            if !editPointTemplates.isEmpty { editPointTemplates = [] }
            return
        }
        let countryCode = effectiveCountryISO2
        let cityKey = activeCityKey
        let engine = currentEngine
        let gapThresholdSq = Self.eraseDashedGapMeters * Self.eraseDashedGapMeters
        var out: [EditPointTemplate] = []
        for j in cachedJourneys {
            let display = j.displayRouteCoordinates
            guard !display.isEmpty else { continue }
            let cls = display.map { $0.cl }
            // Match each engine's projection: MapKit applies GCJ for China,
            // Mapbox renders WGS84 directly. Brush coords come back from the
            // engine in its own projection, so templates must match.
            let adjusted: [CLLocationCoordinate2D] = engine == .mapbox
                ? cls
                : MapCoordAdapter.forMapKit(cls, countryISO2: countryCode, cityKey: cityKey)

            // Two-pass: collect valid (idx, coord) pairs first so we can
            // compute neighbour distance against the actual polyline neighbour
            // (skipping invalid points the polyline drops too).
            var valid: [(Int, CLLocationCoordinate2D)] = []
            valid.reserveCapacity(adjusted.count)
            for (idx, coord) in adjusted.enumerated() where coord.isValid {
                valid.append((idx, coord))
            }
            for k in 0..<valid.count {
                let (idx, coord) = valid[k]
                let dashedAfter: Bool
                if k + 1 < valid.count {
                    let next = valid[k + 1].1
                    let cosLat = cos((coord.latitude + next.latitude) * 0.5 * .pi / 180.0)
                    let dLat = (next.latitude - coord.latitude) * 111_000
                    let dLon = (next.longitude - coord.longitude) * 111_000 * cosLat
                    dashedAfter = (dLat * dLat + dLon * dLon) >= gapThresholdSq
                } else {
                    dashedAfter = false
                }
                out.append(EditPointTemplate(
                    journeyID: j.id,
                    index: idx,
                    coord: coord,
                    isDashedSegmentAfter: dashedAfter
                ))
            }
        }
        editPointTemplates = out
    }

    /// Brush sweep handler. Called continuously from the engine while the
    /// user drags. Finds journey points within `radius` meters of the brush
    /// coordinate (and dashed-segment connectors that pass under the brush)
    /// and adds them to the render mask. Uses flat-earth distance with a
    /// bounding-box prefilter — accurate enough at brush-radius scale and
    /// ~100x faster than `CLLocation.distance`.
    private func handleEraseBrushSwept(at coord: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) {
        guard !editPointTemplates.isEmpty else { return }
        let cosLat = cos(coord.latitude * .pi / 180.0)
        let metersPerDegLat = 111_000.0
        let metersPerDegLon = 111_000.0 * max(cosLat, 0.001)
        let latLimitDeg = radiusMeters / metersPerDegLat
        let lonLimitDeg = radiusMeters / metersPerDegLon
        let radiusSq = radiusMeters * radiusMeters

        // Convert each candidate to local meter offsets relative to brush
        // center so distance math is straight 2D Euclidean.
        func localMeters(_ c: CLLocationCoordinate2D) -> (Double, Double) {
            ((c.latitude - coord.latitude) * metersPerDegLat,
             (c.longitude - coord.longitude) * metersPerDegLon)
        }

        var hitsByJourney: [String: Set<Int>] = [:]
        let n = editPointTemplates.count
        for k in 0..<n {
            let t = editPointTemplates[k]
            // Point-radius hit
            let dLatDeg = t.coord.latitude - coord.latitude
            let dLonDeg = t.coord.longitude - coord.longitude
            if abs(dLatDeg) <= latLimitDeg, abs(dLonDeg) <= lonLimitDeg {
                let mLat = dLatDeg * metersPerDegLat
                let mLon = dLonDeg * metersPerDegLon
                if mLat * mLat + mLon * mLon <= radiusSq {
                    hitsByJourney[t.journeyID, default: []].insert(t.index)
                }
            }

            // Dashed-segment connector under brush: erase both endpoints so
            // the visible dash line vanishes. Without this, the brush passes
            // through gaps without any effect because there are no points
            // along the dashed line.
            guard t.isDashedSegmentAfter, k + 1 < n else { continue }
            let next = editPointTemplates[k + 1]
            guard next.journeyID == t.journeyID else { continue }
            let (ax, ay) = localMeters(t.coord)
            let (bx, by) = localMeters(next.coord)
            let dx = bx - ax
            let dy = by - ay
            let lenSq = dx * dx + dy * dy
            let segDistSq: Double
            if lenSq < 1 {
                segDistSq = ax * ax + ay * ay
            } else {
                let s = max(0, min(1, -(ax * dx + ay * dy) / lenSq))
                let cx = ax + s * dx
                let cy = ay + s * dy
                segDistSq = cx * cx + cy * cy
            }
            if segDistSq <= radiusSq {
                hitsByJourney[t.journeyID, default: []].insert(t.index)
                hitsByJourney[next.journeyID, default: []].insert(next.index)
            }
        }
        for (jid, indices) in hitsByJourney {
            renderMaskStore.erase(journeyID: jid, indices: indices)
        }
    }

    /// Coordinates where memories exist, used for glow-dot overlays
    private var memoryDotCoordinates: [CLLocationCoordinate2D] {
        cachedJourneys
            .flatMap { $0.memories }
            .filter { $0.locationStatus != .pending }
            .map { JourneyMemoryMapCoordinateResolver.mapCoordinate(for: $0, fallbackCountryISO2: effectiveCountryISO2, fallbackCityKey: activeCityKey, engine: currentEngine) }
    }

    struct MemoryGroup: Identifiable {
        let id: String
        let key: String
        let coordinate: CLLocationCoordinate2D
        let items: [JourneyMemory]
    }

    private var groupedMemories: [MemoryGroup] {
        let all = cachedJourneys
            .flatMap { $0.memories }
            .filter { $0.locationStatus != .pending }
        guard !all.isEmpty else { return [] }

        return all
            .sorted { $0.timestamp < $1.timestamp }
            .map { m in
                let mapped = JourneyMemoryMapCoordinateResolver.mapCoordinate(
                    for: m,
                    fallbackCountryISO2: effectiveCountryISO2,
                    fallbackCityKey: activeCityKey,
                    engine: currentEngine
                )
                return MemoryGroup(id: m.id, key: m.id, coordinate: mapped, items: [m])
            }
    }

    private func regionByFitting(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coords.isEmpty else { return nil }
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLon = coords[0].longitude, maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.25),
                                    longitudeDelta: max(0.01, (maxLon - minLon) * 1.25))
        return MKCoordinateRegion(center: center, span: span)
    }

    private func isBoundaryTrusted(_ region: MKCoordinateRegion, anchor: CLLocationCoordinate2D?) -> Bool {
        guard let anchor else { return true }
        let anchorLoc = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        let centerLoc = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let centerDistance = centerLoc.distance(from: anchorLoc)
        return centerDistance <= boundaryTrustMaxDistanceMeters
            && region.span.latitudeDelta <= boundaryTrustMaxSpanDegrees
            && region.span.longitudeDelta <= boundaryTrustMaxSpanDegrees
    }

    private func clampCenter(
        _ center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        inside boundary: MKCoordinateRegion
    ) -> CLLocationCoordinate2D {
        let minLat = boundary.center.latitude - boundary.span.latitudeDelta / 2 + span.latitudeDelta / 2
        let maxLat = boundary.center.latitude + boundary.span.latitudeDelta / 2 - span.latitudeDelta / 2
        let minLon = boundary.center.longitude - boundary.span.longitudeDelta / 2 + span.longitudeDelta / 2
        let maxLon = boundary.center.longitude + boundary.span.longitudeDelta / 2 - span.longitudeDelta / 2

        return CLLocationCoordinate2D(
            latitude: min(max(center.latitude, minLat), maxLat),
            longitude: min(max(center.longitude, minLon), maxLon)
        )
    }

    private func zoomRegionInsideBoundary(
        boundaryRegion: MKCoordinateRegion,
        journeyCoordsForMap: [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        guard let journeyRegion = regionByFitting(journeyCoordsForMap), !journeyCoordsForMap.isEmpty else {
            return boundaryRegion
        }

        let minZoomSpan: CLLocationDegrees = 0.04
        let targetSpan = MKCoordinateSpan(
            latitudeDelta: min(boundaryRegion.span.latitudeDelta, max(minZoomSpan, journeyRegion.span.latitudeDelta)),
            longitudeDelta: min(boundaryRegion.span.longitudeDelta, max(minZoomSpan, journeyRegion.span.longitudeDelta))
        )
        let targetCenter = clampCenter(journeyRegion.center, span: targetSpan, inside: boundaryRegion)
        return MKCoordinateRegion(center: targetCenter, span: targetSpan)
    }

    private func focusedJourneyCoords(
        journeys: [JourneyRoute],
        anchorWGS: CLLocationCoordinate2D?
    ) -> [CLLocationCoordinate2D] {
        guard let anchorWGS else { return journeys.flatMap { $0.allCLCoords } }
        let anchorLoc = CLLocation(latitude: anchorWGS.latitude, longitude: anchorWGS.longitude)

        func localWindow(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
            guard !coords.isEmpty else { return [] }

            let near = coords.filter {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: anchorLoc) < cityFocusRadiusMeters
            }
            if near.count >= cityFocusMinPoints { return near }

            var out: [CLLocationCoordinate2D] = []
            let head = CLLocation(latitude: coords[0].latitude, longitude: coords[0].longitude)
            for c in coords {
                out.append(c)
                if out.count >= cityFocusWindowMaxPoints { break }
                let d = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: head)
                if d >= cityFocusWindowMeters, out.count >= cityFocusMinPoints { break }
            }
            return out
        }

        let focused = journeys.flatMap { localWindow($0.allCLCoords) }
        if focused.count >= cityFocusMinPoints { return focused }
        return [anchorWGS]
    }

    private func computeFittedRegion() -> MKCoordinateRegion? {
        CityDeepRenderEngine.fittedRegion(
            cityKey: activeCityKey,
            countryISO2: effectiveCountryISO2,
            journeys: cachedJourneys,
            anchorWGS: effectiveAnchor,
            effectiveBoundaryWGS: effectiveBoundaryPolygon,
            fetchedBoundaryWGS: fetchedBoundaryPolygon
        )
    }

    private var statsBadge: some View {
        let isDataLoading = !store.hasLoaded || store.isLoading
        let journeyCount = cachedJourneys.count
        let memoryCount = cachedJourneys.reduce(0) { $0 + $1.memories.count }
        return HStack(spacing: 10) {
            if isDataLoading {
                ProgressView()
                    .scaleEffect(0.8)
                Text(L10n.t("loading"))
            } else {
                Text(String(format: L10n.t("city_deep_journeys_count"), journeyCount))
                Text(String(format: L10n.t("city_deep_memories_count"), memoryCount))
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(UITheme.softBlack)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(UITheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(UITheme.cardStroke, lineWidth: 0.8)
        )
        .shadow(radius: 2, y: 1)
    }

    var body: some View {
        let isDataLoading = !store.hasLoaded || store.isLoading
        ZStack(alignment: .top) {
            UnifiedMapView(
                segments: mapSegments(),
                annotations: mapAnnotations,
                circles: mapCircles,
                eraseBrush: eraseBrush,
                cameraCommand: initialCameraCommand,
                config: .cityDeep(),
                callbacks: MapCallbacks(
                    onSelectMemories: { memories in
                        guard !isEditingMask else { return }
                        guard let latest = memories.sorted(by: { $0.timestamp > $1.timestamp }).first else { return }
                        editingMemory = latest
                    },
                    onEraseBrushSwept: { coord, radius in
                        handleEraseBrushSwept(at: coord, radiusMeters: radius)
                    },
                    onEraseBrushStrokeStart: {
                        renderMaskStore.beginStroke()
                    },
                    onEraseBrushStrokeEnd: {
                        renderMaskStore.endStroke()
                    }
                )
            )
            .ignoresSafeArea()
        .onAppear {
            refreshRegionAndBoundary()
        }

            VStack(spacing: 0) {
                headerBar

                HStack(alignment: .top, spacing: 8) {
                    statsBadge
                    Spacer(minLength: 0)
                    if isEditingMask {
                        Button {
                            renderMaskStore.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(renderMaskStore.undoDepth > 0 ? UITheme.softBlack : UITheme.softBlack.opacity(0.35))
                                .frame(width: 32, height: 32)
                                .background(UITheme.cardBg)
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(UITheme.cardStroke, lineWidth: 0.8)
                                )
                                .shadow(radius: 2, y: 1)
                        }
                        .buttonStyle(CardPressButtonStyle(pressedScale: 0.92, pressedOpacity: 0.88))
                        .disabled(renderMaskStore.undoDepth == 0)
                        .accessibilityLabel(L10n.t("city_deep_eraser_undo"))
                    }
                    if !isEditingMask {
                        Button {
                            showMemoriesOnMap.toggle()
                            if !showMemoriesOnMap {
                                editingMemory = nil
                            }
                        } label: {
                            Text(L10n.t(showMemoriesOnMap ? "city_deep_memories_toggle_on" : "city_deep_memories_toggle_off"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(UITheme.softBlack)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(UITheme.cardBg)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(UITheme.cardStroke, lineWidth: 0.8)
                                )
                                .shadow(radius: 2, y: 1)
                        }
                        .buttonStyle(CardPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.88))
                        .accessibilityLabel(L10n.t(showMemoriesOnMap ? "city_deep_memories_toggle_hide_accessibility" : "city_deep_memories_toggle_show_accessibility"))
                    }
                    Button {
                        isEditingMask.toggle()
                        if isEditingMask {
                            editingMemory = nil
                        }
                    } label: {
                        Image(systemName: "eraser")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isEditingMask ? .white : UITheme.softBlack)
                            .frame(width: 32, height: 32)
                            .background(isEditingMask ? Color(red: 1.00, green: 0.45, blue: 0.05) : UITheme.cardBg)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(UITheme.cardStroke, lineWidth: 0.8)
                            )
                            .shadow(radius: 2, y: 1)
                    }
                    .buttonStyle(CardPressButtonStyle(pressedScale: 0.92, pressedOpacity: 0.88))
                    .accessibilityLabel(L10n.t(isEditingMask ? "city_deep_eraser_done" : "city_deep_eraser_enter"))
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()
            }
        }
        .overlay {
            if let tappedMemory = editingMemory {
                MemoryEditorSheet(
                    isPresented: Binding(
                        get: { editingMemory != nil },
                        set: { if !$0 { editingMemory = nil } }
                    ),
                    userID: sessionStore.currentUserID,
                    existing: tappedMemory,
                    onSave: { updated in
                        let targetId = tappedMemory.id
                        if let updated {
                            if let jIdx = store.journeys.firstIndex(where: { $0.memories.contains(where: { $0.id == targetId }) }) {
                                var j = store.journeys[jIdx]
                                if let mIdx = j.memories.firstIndex(where: { $0.id == targetId }) {
                                    var normalized = updated
                                    normalized.id = tappedMemory.id
                                    normalized.timestamp = tappedMemory.timestamp
                                    normalized.coordinate = tappedMemory.coordinate
                                    normalized.type = .memory
                                    normalized.cityKey = tappedMemory.cityKey
                                    normalized.cityName = tappedMemory.cityName
                                    j.memories[mIdx] = normalized
                                    store.upsertSnapshotThrottled(j, coordCount: j.coordinates.count)
                                    store.flushPersist(journey: j)
                                }
                            }
                        } else {
                            if let jIdx = store.journeys.firstIndex(where: { $0.memories.contains(where: { $0.id == targetId }) }) {
                                var j = store.journeys[jIdx]
                                j.memories.removeAll(where: { $0.id == targetId })
                                store.upsertSnapshotThrottled(j, coordCount: j.coordinates.count)
                                store.flushPersist(journey: j)
                            }
                        }
                    }
                )
                .environmentObject(sessionStore)
            }
        }
        .onAppear {
            refreshDisplayTitleFromCardKey()
        }
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
            cachedJourneys = buildCurrentJourneys()
        }
        .onDisappear {
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .onChange(of: activeCityKey) { _ in
            fetchedBoundaryPolygon = nil
            cachedJourneys = buildCurrentJourneys()
            isEditingMask = false
            editPointTemplates = []
            refreshRegionAndBoundary()
            refreshDisplayTitleFromCardKey()
        }
        .onChange(of: store.metadataRevision) { _ in
            cachedJourneys = buildCurrentJourneys()
        }
        .onChange(of: locale) { _ in
            refreshDisplayTitleFromCardKey()
        }
        .onChange(of: languagePreference.currentLanguage) { _ in
            refreshDisplayTitleFromCardKey()
        }
        .task(id: activeCityKey) {
            guard let cached = activeCachedCity else { return }
            let locale = LanguagePreference.shared.displayLocale
            if let translated = await CityNameTranslationCache.shared.translateIfNeeded(cached, locale: locale) {
                displayTitle = translated
            }
        }
        .onChange(of: cachedJourneys.count) { _ in
            refreshRegionAndBoundary()
            if isEditingMask { rebuildEditPointTemplates() }
        }
        .onChange(of: layerStyleRaw) { _ in
            // Engine projections differ (MapKit applies GCJ for China,
            // Mapbox uses WGS84 directly); rebuild template coords so
            // brush hit-test stays aligned with what the user sees.
            if isEditingMask { rebuildEditPointTemplates() }
            refreshRegionAndBoundary()
        }
        .onChange(of: isEditingMask) { editing in
            if editing {
                rebuildEditPointTemplates()
            } else {
                editPointTemplates = []
            }
        }
        .background(SwipeBackEnabler())
        .navigationBarBackButtonHidden(true)
    }

    private var headerBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .appFullSurfaceTapTarget(.circle)
            }
            .buttonStyle(CardPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.88))
            .hoverEffect(.lift)

            Spacer(minLength: 0)

            Text(displayTitle)
                .appHeaderStyle()
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(CityDeepPalette.headerBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.8)
        }
    }

    private func headerBaseCityName() -> String {
        effectiveCityName
    }

    private func refreshDisplayTitleFromCardKey() {
        let base = headerBaseCityName().trimmingCharacters(in: .whitespacesAndNewlines)
        displayTitle = base.isEmpty ? city.localizedName : base
    }

    private func refreshRegionAndBoundary() {
        let region = computeFittedRegion()
        fittedRegion = region
        if let region { initialCameraCommand = .setRegion(region, animated: false) }
        Task {
            let boundary = await CityBoundaryService.shared.boundaryPolygon(
                cityKey: activeCityKey,
                cityName: effectiveCityName,
                countryISO2: effectiveCountryISO2,
                anchor: effectiveAnchor ?? cachedJourneys.first?.allCLCoords.first
            )
            guard let boundary, !boundary.isEmpty else { return }
            await MainActor.run {
                fetchedBoundaryPolygon = boundary
                let r = computeFittedRegion()
                fittedRegion = r
                if let r { initialCameraCommand = .setRegion(r, animated: false) }
            }
        }
    }

}

// Old CityDeepMKMap, CityDeepStyledPolyline, CityDeepLayeredPolylineRenderer, MemoryDotCircle removed — now using UnifiedMapView

private extension String {
    func normalizedCityNameForMatching() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}
