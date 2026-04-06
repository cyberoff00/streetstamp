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
    @ObservedObject private var languagePreference = LanguagePreference.shared

    init(city: City) {
        self.city = city
        _displayTitle = State(initialValue: city.localizedName)
        _activeCityKey = State(initialValue: city.sourceCityKeys.first ?? city.id)
    }

    @State private var displayTitle: String
    @State private var activeCityKey: String

    @State private var editingMemory: JourneyMemory? = nil
    @State private var showMemoriesOnMap = true

    @State private var fittedRegion: MKCoordinateRegion? = nil
    @State private var initialCameraCommand: MapCameraCommand? = nil
    @State private var fetchedBoundaryPolygon: [CLLocationCoordinate2D]? = nil
    @State private var sidebarHideToken = UUID().uuidString

    private var activeCachedCity: CachedCity? {
        cache.cachedCities.first(where: { $0.id == activeCityKey && !($0.isTemporary ?? false) })
            ?? sourceCachedCities.first
    }

    private var sourceCityKeys: [String] {
        let keys = city.sourceCityKeys.isEmpty ? [city.id] : city.sourceCityKeys
        return Array(Set(keys)).sorted()
    }

    private var sourceCachedCities: [CachedCity] {
        let keySet = Set(sourceCityKeys)
        return cache.cachedCities.filter { keySet.contains($0.id) && !($0.isTemporary ?? false) }
    }

    private var effectiveCountryISO2: String? {
        activeCachedCity?.countryISO2 ?? sourceCachedCities.first?.countryISO2 ?? city.countryISO2
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
        let cachedIDs = sourceCachedCities.flatMap(\.journeyIds)
        if !cachedIDs.isEmpty {
            return Set(cachedIDs)
        }
        return Set(city.journeys.map { $0.id })
    }

    private var currentJourneys: [JourneyRoute] {
        let byId = Dictionary(store.journeys.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let cachedIDs = Array(cityJourneyIDs)
        if !cachedIDs.isEmpty {
            return cachedIDs.compactMap { byId[$0] }
        }
        return city.journeys.compactMap { byId[$0.id] }
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

    private func segmentSignature(_ coords: [CLLocationCoordinate2D]) -> String {
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

        func quantized(_ c: CLLocationCoordinate2D) -> String {
            let lat = Int((c.latitude * 2_000).rounded())
            let lon = Int((c.longitude * 2_000).rounded())
            return "\(lat):\(lon)"
        }

        let forward = samples.map(quantized).joined(separator: "|")
        let backward = samples.reversed().map(quantized).joined(separator: "|")
        return min(forward, backward)
    }

    private func quantile(_ values: [Int], p: Double) -> Double {
        guard !values.isEmpty else { return 1.0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return Double(sorted[max(0, min(sorted.count - 1, index))])
    }

    private var currentEngine: MapEngineSetting {
        (MapLayerStyle(rawValue: layerStyleRaw) ?? .mutedDark).engine
    }

    private func styledSegments() -> [Segment] {
        let surface: RouteRenderSurface = currentEngine == .mapbox ? .mapbox : .mapKit
        return CityDeepRenderEngine
            .styledSegments(
                journeys: currentJourneys,
                countryISO2: effectiveCountryISO2,
                cityKey: activeCityKey,
                surface: surface
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
        guard showMemoriesOnMap, store.hasLoaded, !store.isLoading else { return [] }
        return groupedMemories.map { g in
            MapAnnotationItem(id: g.id, coordinate: g.coordinate, kind: .memoryGroup(key: g.key, items: g.items))
        }
    }

    private var mapCircles: [MapCircleOverlay] {
        guard showMemoriesOnMap, store.hasLoaded, !store.isLoading else { return [] }
        return memoryDotCoordinates.enumerated().map { (i, coord) in
            MapCircleOverlay(id: "dot-\(i)", center: coord, radiusMeters: 30)
        }
    }

    /// Coordinates where memories exist, used for glow-dot overlays
    private var memoryDotCoordinates: [CLLocationCoordinate2D] {
        currentJourneys
            .flatMap { $0.memories }
            .filter { $0.locationStatus != .pending }
            .map { JourneyMemoryMapCoordinateResolver.mapCoordinate(for: $0, fallbackCountryISO2: effectiveCountryISO2, fallbackCityKey: activeCityKey) }
    }

    struct MemoryGroup: Identifiable {
        let id: String
        let key: String
        let coordinate: CLLocationCoordinate2D
        let items: [JourneyMemory]
    }

    private var groupedMemories: [MemoryGroup] {
        let all = currentJourneys
            .flatMap { $0.memories }
            .filter { $0.locationStatus != .pending }
        guard !all.isEmpty else { return [] }

        return all
            .sorted { $0.timestamp < $1.timestamp }
            .map { m in
                let mapped = JourneyMemoryMapCoordinateResolver.mapCoordinate(
                    for: m,
                    fallbackCountryISO2: effectiveCountryISO2,
                    fallbackCityKey: activeCityKey
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
            journeys: currentJourneys,
            anchorWGS: effectiveAnchor,
            effectiveBoundaryWGS: effectiveBoundaryPolygon,
            fetchedBoundaryWGS: fetchedBoundaryPolygon
        )
    }

    private var statsBadge: some View {
        let isDataLoading = !store.hasLoaded || store.isLoading
        let journeyCount = currentJourneys.count
        let memoryCount = currentJourneys.reduce(0) { $0 + $1.memories.count }
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
                cameraCommand: initialCameraCommand,
                config: .cityDeep(),
                callbacks: MapCallbacks(
                    onSelectMemories: { memories in
                        guard let latest = memories.sorted(by: { $0.timestamp > $1.timestamp }).first else { return }
                        editingMemory = latest
                    }
                )
            )
            .ignoresSafeArea()
        .onAppear {
            refreshRegionAndBoundary()
        }

            VStack(spacing: 0) {
                headerBar

                HStack(alignment: .top) {
                    statsBadge
                    Spacer(minLength: 0)
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
                                Capsule()
                                    .stroke(UITheme.cardStroke, lineWidth: 0.8)
                            )
                            .shadow(radius: 2, y: 1)
                    }
                    .buttonStyle(CardPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.88))
                    .accessibilityLabel(L10n.t(showMemoriesOnMap ? "city_deep_memories_toggle_hide_accessibility" : "city_deep_memories_toggle_show_accessibility"))
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
        }
        .onDisappear {
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .onChange(of: activeCityKey) { _ in
            fetchedBoundaryPolygon = nil
            refreshRegionAndBoundary()
            refreshDisplayTitleFromCardKey()
        }
        .onChange(of: locale) { _ in
            refreshDisplayTitleFromCardKey()
        }
        .onChange(of: languagePreference.currentLanguage) { _ in
            refreshDisplayTitleFromCardKey()
        }
        .onChange(of: currentJourneys.count) { _ in
            refreshRegionAndBoundary()
        }
        .onChange(of: layerStyleRaw) { _ in
            refreshRegionAndBoundary()
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
                anchor: effectiveAnchor ?? currentJourneys.first?.allCLCoords.first
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
