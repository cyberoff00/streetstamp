import Foundation
import SwiftUI
import MapKit
import CoreLocation

private enum CityDeepPalette {
    static let headerBg = Color(red: 251.0 / 255.0, green: 251.0 / 255.0, blue: 249.0 / 255.0)
}

struct CityDeepView: View {
    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceStyle.dark.rawValue
    private let cityFocusRadiusMeters: CLLocationDistance = 80_000
    private let cityFocusWindowMeters: CLLocationDistance = 40_000
    private let cityFocusMinPoints = 2
    private let cityFocusWindowMaxPoints = 80
    private let boundaryTrustMaxDistanceMeters: CLLocationDistance = 120_000
    private let boundaryTrustMaxSpanDegrees: CLLocationDegrees = 3.0
    let city: City
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cache: CityCache
    @EnvironmentObject private var flow: AppFlowCoordinator

    init(city: City) {
        self.city = city
        _displayTitle = State(initialValue: city.displayName ?? city.name)
        _activeCityKey = State(initialValue: city.id)
    }

    @State private var displayTitle: String
    @State private var activeCityKey: String

    @State private var editingMemory: JourneyMemory? = nil
    @State private var showMemoriesOnMap = true

    @State private var fittedRegion: MKCoordinateRegion? = nil
    @State private var fetchedBoundaryPolygon: [CLLocationCoordinate2D]? = nil
    @State private var showCityLevelPicker = false
    @State private var showCityLevelConfirm = false
    @State private var cityLevelOptions: [CityPlacemarkResolver.CardLevel] = []
    @State private var cityLevelOptionLabels: [CityPlacemarkResolver.CardLevel: String] = [:]
    @State private var cityLevelParentRegionKey: String?
    @State private var cityLevelCurrentSelection: CityPlacemarkResolver.CardLevel?
    @State private var cityLevelCanonicalSnapshot: ReverseGeocodeService.CanonicalResult?
    @State private var pendingCityLevelSelection: CityPlacemarkResolver.CardLevel?
    @State private var blockedCityLevelSelection: CityPlacemarkResolver.CardLevel?
    @State private var cityLevelLoading = false
    @State private var showCityLevelDowngradeBlocked = false
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
        activeCachedCity?.name ?? city.displayName ?? city.name
    }

    private var cityJourneyIDs: Set<String> {
        if let ids = activeCachedCity?.journeyIds, !ids.isEmpty {
            return Set(ids)
        }
        return Set(city.journeys.map { $0.id })
    }

    private var reserveJourneyStart: CLLocationCoordinate2D? {
        if let reserved = activeCachedCity?.anchor?.cl, reserved.isValid {
            return reserved
        }
        let firstByStart = currentJourneys
            .sorted { ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture) }
            .first?
            .startCoordinate
        return firstByStart ?? effectiveAnchor
    }

    private var currentJourneys: [JourneyRoute] {
        let byId = Dictionary(uniqueKeysWithValues: store.journeys.map { ($0.id, $0) })
        if let ids = activeCachedCity?.journeyIds, !ids.isEmpty {
            return ids.compactMap { byId[$0] }
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

    private func styledSegments() -> [Segment] {
        CityDeepRenderEngine
            .styledSegments(
                journeys: currentJourneys,
                countryISO2: effectiveCountryISO2,
                cityKey: activeCityKey
            )
            .map { seg in
                Segment(coords: seg.coords, isGap: seg.isGap, repeatWeight: seg.repeatWeight)
        }
    }

    struct MemoryGroup: Identifiable {
        let id: String
        let key: String
        let coordinate: CLLocationCoordinate2D
        let items: [JourneyMemory]
    }

    private var groupedMemories: [MemoryGroup] {
        let all = currentJourneys.flatMap { $0.memories }
        guard !all.isEmpty else { return [] }

        return all
            .sorted { $0.timestamp < $1.timestamp }
            .map { m in
                let mapped = MapCoordAdapter.forMapKit(.init(latitude: m.coordinate.0, longitude: m.coordinate.1), countryISO2: effectiveCountryISO2)
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
        let journeyCount = currentJourneys.count
        let memoryCount = currentJourneys.reduce(0) { $0 + $1.memories.count }
        return HStack(spacing: 10) {
            Text(String(format: L10n.t("city_deep_journeys_count"), journeyCount))
            Text(String(format: L10n.t("city_deep_memories_count"), memoryCount))
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
        ZStack(alignment: .top) {
            CityDeepMKMap(
                segments: styledSegments(),
                memoryGroups: showMemoriesOnMap ? groupedMemories : [],
                initialRegion: fittedRegion,
                onTapMemoryGroup: { group in
                    guard let latest = group.items.sorted(by: { $0.timestamp > $1.timestamp }).first else { return }
                    editingMemory = latest
                }
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
                        Text(showMemoriesOnMap ? "记忆 开" : "记忆 关")
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
                    .accessibilityLabel(showMemoriesOnMap ? "Hide memories on map" : "Show memories on map")
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
            loadReservedLevelSelection()
            initializeReservedLevelProfileIfNeeded(showPickerWhenReady: false)
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
            loadReservedLevelSelection()
            initializeReservedLevelProfileIfNeeded(showPickerWhenReady: false)
            refreshDisplayTitleFromCardKey()
        }
        .onChange(of: currentJourneys.count) { _ in
            refreshRegionAndBoundary()
        }
        .onChange(of: mapAppearanceRaw) { _ in
            refreshRegionAndBoundary()
        }
        .navigationBarBackButtonHidden(true)
        .confirmationDialog(
            levelDialogTitle(),
            isPresented: $showCityLevelPicker,
            titleVisibility: .visible
        ) {
            ForEach(cityLevelOptions, id: \.rawValue) { level in
                Button(levelDialogButtonLabel(for: level, selected: level == cityLevelCurrentSelection)) {
                    if let current = cityLevelCurrentSelection, levelRank(level) < levelRank(current) {
                        blockedCityLevelSelection = level
                        showCityLevelDowngradeBlocked = true
                        return
                    }
                    pendingCityLevelSelection = level
                    showCityLevelConfirm = true
                }
            }
            Button(levelDialogCancelTitle(), role: .cancel) {}
        }
        .alert(
            cityLevelConfirmTitle(),
            isPresented: $showCityLevelConfirm
        ) {
            Button(levelDialogCancelTitle(), role: .cancel) {
                pendingCityLevelSelection = nil
            }
            Button(cityLevelConfirmApplyTitle(), role: .destructive) {
                guard let level = pendingCityLevelSelection else { return }
                pendingCityLevelSelection = nil
                applyCityLevelPreference(level)
            }
        } message: {
            Text(cityLevelConfirmMessage())
        }
        .alert(
            cityLevelDowngradeBlockedTitle(),
            isPresented: $showCityLevelDowngradeBlocked
        ) {
            Button(levelDialogCancelTitle(), role: .cancel) {
                blockedCityLevelSelection = nil
            }
        } message: {
            Text(cityLevelDowngradeBlockedMessage())
        }
    }

    private var headerBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
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

            Button(action: { openCityLevelPicker() }) {
                Group {
                    if cityLevelLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                    } else {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(CardPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.88))
            .hoverEffect(.lift)
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

    private func openCityLevelPicker() {
        guard !cityLevelLoading else { return }
        if !cityLevelOptions.isEmpty {
            showCityLevelPicker = true
            return
        }
        initializeReservedLevelProfileIfNeeded(showPickerWhenReady: true)
    }

    private func applyCityLevelPreference(_ level: CityPlacemarkResolver.CardLevel) {
        CityLevelPreferenceStore.shared.setPreferredLevel(level, for: cityLevelParentRegionKey)
        guard !cityLevelLoading else { return }
        cityLevelLoading = true

        Task {
            if let current = await MainActor.run(body: { cityLevelCurrentSelection }),
               levelRank(level) < levelRank(current) {
                await MainActor.run {
                    blockedCityLevelSelection = level
                    showCityLevelDowngradeBlocked = true
                    cityLevelLoading = false
                }
                return
            }

            guard let anchor = reserveJourneyStart,
                  CLLocationCoordinate2DIsValid(anchor)
            else {
                await MainActor.run { cityLevelLoading = false }
                return
            }

            let canonical = await resolveCanonicalForPicker(anchor: anchor)
            guard let canonical else {
                await MainActor.run { cityLevelLoading = false }
                return
            }

            let selectedNameRaw = canonical.availableLevels[level] ?? canonical.cityName
            let selectedName = selectedNameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selectedName.isEmpty else {
                await MainActor.run { cityLevelLoading = false }
                return
            }

            let iso = (canonical.iso2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let targetKey = "\(selectedName)|\(iso)"
            let sourceKey = await MainActor.run { activeCityKey }
            let targetNameNorm = selectedName.normalizedCityNameForMatching()
            let baseLevelForDisplay: CityPlacemarkResolver.CardLevel? = await MainActor.run {
                if let raw = activeCachedCity?.reservedLevelRaw,
                   let level = CityPlacemarkResolver.CardLevel(rawValue: raw) {
                    return level
                }
                return cityLevelCurrentSelection
            }

            if targetKey == sourceKey {
                await MainActor.run {
                    cityLevelCurrentSelection = level
                    cityLevelLoading = false
                }
                return
            }

            let sourceCities = await MainActor.run {
                cache.cachedCities.filter { !($0.isTemporary ?? false) }
            }
            let sourceCitiesByKey = Dictionary(uniqueKeysWithValues: sourceCities.map { ($0.id, $0) })

            let candidateSourceKeys: Set<String> = {
                guard let parentKey = canonical.parentRegionKey, !targetNameNorm.isEmpty else {
                    return [sourceKey]
                }

                let selectedRank = levelRank(level)
                let matched = sourceCities.compactMap { cached -> String? in
                    guard cached.reservedParentRegionKey == parentKey else { return nil }
                    guard let selectedLevelName = cached.reservedAvailableLevelNames?[level.rawValue] else { return nil }
                    let normalized = selectedLevelName.normalizedCityNameForMatching()
                    guard !normalized.isEmpty, normalized == targetNameNorm else { return nil }

                    if let raw = cached.reservedLevelRaw,
                       let existingLevel = CityPlacemarkResolver.CardLevel(rawValue: raw),
                       levelRank(existingLevel) > selectedRank,
                       cached.id != sourceKey,
                       cached.id != targetKey {
                        return nil
                    }
                    return cached.id
                }
                return Set(matched).union([sourceKey])
            }()

            var sourceJourneyIDsByCity: [String: Set<String>] = [:]
            for key in candidateSourceKeys {
                if let city = sourceCitiesByKey[key], !city.journeyIds.isEmpty {
                    sourceJourneyIDsByCity[key] = Set(city.journeyIds)
                }
            }
            if sourceJourneyIDsByCity.isEmpty {
                sourceJourneyIDsByCity[sourceKey] = cityJourneyIDs
            }

            let allCandidateJourneyIDs = sourceJourneyIDsByCity.values.reduce(into: Set<String>()) { acc, ids in
                acc.formUnion(ids)
            }

            var updatedJourneys: [JourneyRoute] = []
            let source = await MainActor.run { store.journeys }

            for j in source where allCandidateJourneyIDs.contains(j.id) && j.isCompleted {
                var next = j
                next.startCityKey = targetKey
                next.cityKey = targetKey
                next.canonicalCity = selectedName
                if !iso.isEmpty {
                    next.countryISO2 = iso
                }
                updatedJourneys.append(next)
            }

            let updatedIDs = Set(updatedJourneys.map(\.id))
            sourceJourneyIDsByCity = sourceJourneyIDsByCity
                .mapValues { ids in ids.intersection(updatedIDs) }
                .filter { !$0.value.isEmpty }

            if sourceJourneyIDsByCity.isEmpty {
                sourceJourneyIDsByCity[sourceKey] = Set(updatedJourneys.map(\.id))
            }

            await MainActor.run {
                store.applyBulkCompletedUpdates(updatedJourneys)
                for (fromKey, ids) in sourceJourneyIDsByCity where fromKey != targetKey {
                    let moved = updatedJourneys.filter { ids.contains($0.id) }
                    guard !moved.isEmpty else { continue }
                    cache.applyCityLevelReassignment(
                        from: fromKey,
                        to: targetKey,
                        targetCityName: selectedName,
                        targetISO2: iso,
                        movedJourneys: moved,
                        anchor: anchor
                    )
                }
                cache.updateCityLevelReserveProfile(
                    cityKey: targetKey,
                    level: baseLevelForDisplay,
                    parentRegionKey: canonical.parentRegionKey,
                    availableLevels: canonical.availableLevels,
                    anchor: anchor,
                    force: true
                )
                activeCityKey = targetKey
                cityLevelCurrentSelection = level
                cityLevelCanonicalSnapshot = canonical
                cityLevelLoading = false
            }

            await MainActor.run {
                refreshDisplayTitleFromCardKey()
            }
        }
    }

    private func levelRank(_ level: CityPlacemarkResolver.CardLevel) -> Int {
        switch level {
        case .locality: return 0
        case .subAdmin: return 1
        case .admin: return 2
        case .island: return 3
        case .country: return 4
        }
    }

    private func resolveCanonicalForPicker(anchor: CLLocationCoordinate2D) async -> ReverseGeocodeService.CanonicalResult? {
        if let snapshot = await MainActor.run(body: { cityLevelCanonicalSnapshot }) {
            return snapshot
        }
        let anchorLoc = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        return await canonicalWithRetry(for: anchorLoc)
    }

    private func loadReservedLevelSelection() {
        let baseLevel = activeCachedCity?.reservedLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) }
        if let rawNames = activeCachedCity?.reservedAvailableLevelNames {
            var labels: [CityPlacemarkResolver.CardLevel: String] = [:]
            for (raw, name) in rawNames {
                if let level = CityPlacemarkResolver.CardLevel(rawValue: raw) {
                    labels[level] = name
                }
            }
            cityLevelOptionLabels = labels
            let ordered: [CityPlacemarkResolver.CardLevel] = [.island, .locality, .subAdmin, .admin, .country]
            let minRank = baseLevel.map(levelRank) ?? 0
            cityLevelOptions = ordered.filter {
                guard levelRank($0) >= minRank else { return false }
                if let name = labels[$0] {
                    return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return false
            }
            cityLevelCurrentSelection = resolveCurrentLevelFromLabels(
                labels: labels,
                options: cityLevelOptions,
                parentRegionKey: activeCachedCity?.reservedParentRegionKey,
                fallback: baseLevel
            )
        } else {
            cityLevelOptions = []
            cityLevelOptionLabels = [:]
            cityLevelCurrentSelection = nil
        }
        cityLevelParentRegionKey = activeCachedCity?.reservedParentRegionKey
    }

    private func initializeReservedLevelProfileIfNeeded(showPickerWhenReady: Bool) {
        guard !cityLevelLoading else { return }
        if !cityLevelOptions.isEmpty {
            if showPickerWhenReady {
                showCityLevelPicker = true
            }
            return
        }
        guard let reserveAnchor = reserveJourneyStart, CLLocationCoordinate2DIsValid(reserveAnchor) else { return }

        cityLevelLoading = true
        let loc = CLLocation(latitude: reserveAnchor.latitude, longitude: reserveAnchor.longitude)
        Task {
            let canonical = await canonicalWithRetry(for: loc)
            await MainActor.run {
                cityLevelLoading = false
                guard let canonical else { return }

                let ordered: [CityPlacemarkResolver.CardLevel] = [.island, .locality, .subAdmin, .admin, .country]
                let resolvedCurrent = resolveCurrentLevel(canonical: canonical, options: ordered)
                let baseLevel = activeCachedCity?.reservedLevelRaw
                    .flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) }
                    ?? resolvedCurrent
                let minRank = baseLevel.map(levelRank) ?? 0
                let options = ordered.filter {
                    guard levelRank($0) >= minRank else { return false }
                    if let name = canonical.availableLevels[$0] {
                        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    return false
                }

                cityLevelCanonicalSnapshot = canonical
                cityLevelParentRegionKey = canonical.parentRegionKey
                cityLevelOptionLabels = canonical.availableLevels
                cityLevelOptions = options
                cityLevelCurrentSelection = resolveCurrentLevel(canonical: canonical, options: options)
                refreshDisplayTitleFromCardKey()
                cache.updateCityLevelReserveProfile(
                    cityKey: activeCityKey,
                    level: baseLevel,
                    parentRegionKey: canonical.parentRegionKey,
                    availableLevels: canonical.availableLevels,
                    anchor: reserveAnchor,
                    force: false
                )
                if showPickerWhenReady {
                    showCityLevelPicker = true
                }
            }
        }
    }

    private func resolveCurrentLevel(
        canonical: ReverseGeocodeService.CanonicalResult,
        options: [CityPlacemarkResolver.CardLevel]
    ) -> CityPlacemarkResolver.CardLevel? {
        if let preferred = CityLevelPreferenceStore.shared.preferredLevel(for: canonical.parentRegionKey),
           options.contains(preferred) {
            return preferred
        }

        let currentName = cityName(from: activeCityKey).normalizedCityNameForMatching()
        guard !currentName.isEmpty else { return nil }
        for level in options {
            let name = (canonical.availableLevels[level] ?? "").normalizedCityNameForMatching()
            if !name.isEmpty && name == currentName {
                return level
            }
        }
        return nil
    }

    private func resolveCurrentLevelFromLabels(
        labels: [CityPlacemarkResolver.CardLevel: String],
        options: [CityPlacemarkResolver.CardLevel],
        parentRegionKey: String?,
        fallback: CityPlacemarkResolver.CardLevel?
    ) -> CityPlacemarkResolver.CardLevel? {
        if let preferred = CityLevelPreferenceStore.shared.preferredLevel(for: parentRegionKey),
           options.contains(preferred),
           let preferredName = labels[preferred],
           !preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preferred
        }

        let currentName = cityName(from: activeCityKey).normalizedCityNameForMatching()
        if !currentName.isEmpty {
            for level in options {
                let name = (labels[level] ?? "").normalizedCityNameForMatching()
                if !name.isEmpty && name == currentName {
                    return level
                }
            }
        }

        if let fallback, options.contains(fallback) {
            return fallback
        }
        return options.first
    }

    private func isoFromCityKey(_ cityKey: String) -> String {
        let parts = cityKey.components(separatedBy: "|")
        guard parts.count > 1 else { return "" }
        return parts[1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func headerBaseCityName() -> String {
        if let selected = cityLevelCurrentSelection,
           let selectedName = cityLevelOptionLabels[selected]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedName.isEmpty {
            return selectedName
        }
        let fromKey = cityName(from: activeCityKey).trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromKey.isEmpty { return fromKey }
        let cached = effectiveCityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cached.isEmpty ? city.name : cached
    }

    private func formatHeaderTitle(baseName: String) -> String {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return city.name }

        let iso = (effectiveCountryISO2 ?? isoFromCityKey(activeCityKey)).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if iso == "US",
           let admin = cityLevelOptionLabels[.admin]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !admin.isEmpty {
            if admin.normalizedCityNameForMatching() != base.normalizedCityNameForMatching() {
                return "\(base), \(admin)"
            }
        }
        return base
    }

    private func refreshDisplayTitleFromCardKey() {
        displayTitle = formatHeaderTitle(baseName: headerBaseCityName())
    }

    private func cityName(from cityKey: String) -> String {
        cityKey.components(separatedBy: "|").first ?? cityKey
    }

    private func canonicalWithRetry(for location: CLLocation) async -> ReverseGeocodeService.CanonicalResult? {
        if let first = await ReverseGeocodeService.shared.canonical(for: location) {
            return first
        }
        try? await Task.sleep(nanoseconds: 1_650_000_000)
        return await ReverseGeocodeService.shared.canonical(for: location)
    }

    private func refreshRegionAndBoundary() {
        fittedRegion = computeFittedRegion()
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
                fittedRegion = computeFittedRegion()
            }
        }
    }

    private func levelDialogTitle() -> String {
        isChineseLocale() ? "选择层级范围" : "Choose Hierarchy Level"
    }

    private func levelDialogCancelTitle() -> String {
        isChineseLocale() ? "取消" : "Cancel"
    }

    private func levelDialogButtonLabel(for level: CityPlacemarkResolver.CardLevel, selected: Bool) -> String {
        let placeName = cityLevelOptionLabels[level]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = placeName.isEmpty ? "" : " · \(placeName)"
        let prefix = selected ? "✓ " : ""
        switch level {
        case .locality:
            return prefix + (isChineseLocale() ? "Locality（市）" : "Locality") + suffix
        case .subAdmin:
            return prefix + (isChineseLocale() ? "SubAdmin（地区）" : "SubAdmin") + suffix
        case .admin:
            return prefix + (isChineseLocale() ? "Admin（省/州）" : "Admin") + suffix
        case .island:
            return prefix + (isChineseLocale() ? "Island（整岛）" : "Island") + suffix
        case .country:
            if shouldDisplayRegionForCurrentCity {
                return prefix + (isChineseLocale() ? "Region（区域）" : "Region") + suffix
            }
            return prefix + (isChineseLocale() ? "Country（国家）" : "Country") + suffix
        }
    }

    private func cityLevelConfirmTitle() -> String {
        isChineseLocale() ? "确认更换城市层级" : "Confirm Level Change"
    }

    private func cityLevelConfirmApplyTitle() -> String {
        isChineseLocale() ? "确认更换" : "Apply"
    }

    private func cityLevelConfirmMessage() -> String {
        if let pending = pendingCityLevelSelection,
           let current = cityLevelCurrentSelection,
           levelRank(pending) > levelRank(current) {
            if isChineseLocale() {
                return "更换后，会将同一大层级下更小层级的卡片合并到新层级；未来在同一区域的 Journey 也会默认归到该层级。"
            }
            return "After switching, cards from smaller levels in the same parent region will be merged into this level, and future journeys in this region will default to it."
        }
        if isChineseLocale() {
            return "更换后，未来在同一区域的 Journey 会默认归到该层级，直到你再次修改。"
        }
        return "After switching, future journeys in the same region will default to this level until you change it again."
    }

    private func cityLevelDowngradeBlockedTitle() -> String {
        isChineseLocale() ? "暂不支持改为更小层级" : "Smaller Level Not Supported"
    }

    private func cityLevelDowngradeBlockedMessage() -> String {
        if let from = cityLevelCurrentSelection, let to = blockedCityLevelSelection {
            let fromName = levelNameForHint(from)
            let toName = levelNameForHint(to)
            if isChineseLocale() {
                return "当前仅支持从小层级改到大层级。\n你选择了从 \(fromName) 改到 \(toName)，此方向暂不支持。"
            }
            return "Only upgrading from a smaller to a larger hierarchy level is supported now. Changing from \(fromName) to \(toName) is currently blocked."
        }
        if isChineseLocale() {
            return "当前仅支持从小层级改到大层级。"
        }
        return "Only upgrading from a smaller to a larger hierarchy level is supported now."
    }

    private func levelNameForHint(_ level: CityPlacemarkResolver.CardLevel) -> String {
        switch level {
        case .locality: return "Locality"
        case .subAdmin: return "SubAdmin"
        case .admin: return "Admin"
        case .island: return "Island"
        case .country:
            return shouldDisplayRegionForCurrentCity ? "Region" : "Country"
        }
    }

    private func isChineseLocale() -> Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    private var shouldDisplayRegionForCurrentCity: Bool {
        let iso = (effectiveCountryISO2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ["HK", "MO", "TW"].contains(iso)
    }
}

private struct CityDeepMKMap: UIViewRepresentable {
    let segments: [AnySegment]
    let memoryGroups: [CityDeepView.MemoryGroup]
    let initialRegion: MKCoordinateRegion?
    let onTapMemoryGroup: (CityDeepView.MemoryGroup) -> Void

    struct AnySegment {
        let coords: [CLLocationCoordinate2D]
        let isGap: Bool
        let repeatWeight: Double
    }

    init(
        segments: [CityDeepView.Segment],
        memoryGroups: [CityDeepView.MemoryGroup],
        initialRegion: MKCoordinateRegion?,
        onTapMemoryGroup: @escaping (CityDeepView.MemoryGroup) -> Void
    ) {
        self.segments = segments.map { AnySegment(coords: $0.coords, isGap: $0.isGap, repeatWeight: $0.repeatWeight) }
        self.memoryGroups = memoryGroups
        self.initialRegion = initialRegion
        self.onTapMemoryGroup = onTapMemoryGroup
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = MapAppearanceSettings.interfaceStyle
        map.showsCompass = false
        map.showsScale = false
        map.showsTraffic = false
        map.pointOfInterestFilter = .excludingAll
        map.mapType = MapAppearanceSettings.mapType
        map.isRotateEnabled = false
        map.isPitchEnabled = false

        if let r = initialRegion {
            map.setRegion(r, animated: false)
        }

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.overrideUserInterfaceStyle = MapAppearanceSettings.interfaceStyle
        map.mapType = MapAppearanceSettings.mapType

        if let r = initialRegion, !context.coordinator.didSetInitialRegion {
            context.coordinator.didSetInitialRegion = true
            map.setRegion(r, animated: false)
        }

        map.removeOverlays(map.overlays)
        for seg in segments {
            guard seg.coords.count >= 2 else { continue }
            let poly = StyledPolyline(coordinates: seg.coords, count: seg.coords.count)
            poly.isGap = seg.isGap
            poly.repeatWeight = max(0, min(1, seg.repeatWeight))
            map.addOverlay(poly)
        }

        map.removeAnnotations(map.annotations)
        for g in memoryGroups {
            let ann = MemoryGroupAnnotation(group: g)
            map.addAnnotation(ann)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: CityDeepMKMap
        var didSetInitialRegion = false

        init(_ parent: CityDeepMKMap) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? StyledPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let base = MapAppearanceSettings.routeBaseColor
            let gapDash = RouteRenderStyleTokens.dashLengths.map { NSNumber(value: Double($0)) }
            let weight = CGFloat(max(0, min(1, poly.repeatWeight)))
            let isGap = poly.isGap

            let glow = MKPolylineRenderer(polyline: poly)
            glow.lineWidth = isGap ? 2.0 : (3.0 + weight * 1.2)
            glow.lineCap = .round
            glow.lineJoin = .round
            glow.strokeColor = base.withAlphaComponent(isGap ? 0.08 : 0.12)
            if isGap { glow.lineDashPattern = gapDash }

            let core = MKPolylineRenderer(polyline: poly)
            core.lineWidth = isGap ? 1.1 : (1.6 + weight * 0.8)
            core.lineCap = .round
            core.lineJoin = .round
            core.strokeColor = base.withAlphaComponent(isGap ? 0.30 : 0.84)
            if isGap { core.lineDashPattern = gapDash }

            let freq = MKPolylineRenderer(polyline: poly)
            freq.lineWidth = isGap ? 0 : (2.2 + weight * 1.2)
            freq.lineCap = .round
            freq.lineJoin = .round
            freq.strokeColor = base.withAlphaComponent(isGap ? 0 : (0.05 + 0.15 * weight))

            return LayeredPolylineRenderer(renderers: [glow, freq, core])
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? MemoryGroupAnnotation else { return nil }
            let id = "memGroup"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: ann, reuseIdentifier: id)
            view.annotation = ann
            view.canShowCallout = false
            view.bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
            view.backgroundColor = .clear
            view.displayPriority = .required
            if #available(iOS 14.0, *) {
                view.zPriority = .max
            }

            let hosting = UIHostingController(rootView: MemoryPin(cluster: ann.group.items))
            hosting.view.backgroundColor = .clear
            hosting.view.frame = view.bounds
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hosting.view)

            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let ann = view.annotation as? MemoryGroupAnnotation else { return }
            parent.onTapMemoryGroup(ann.group)
            mapView.deselectAnnotation(ann, animated: false)
        }
    }
}

private final class MemoryGroupAnnotation: NSObject, MKAnnotation {
    let group: CityDeepView.MemoryGroup
    var coordinate: CLLocationCoordinate2D { group.coordinate }

    init(group: CityDeepView.MemoryGroup) {
        self.group = group
    }
}

private final class StyledPolyline: MKPolyline {
    var isGap: Bool = false
    var repeatWeight: Double = 0
}

private final class LayeredPolylineRenderer: MKOverlayRenderer {
    private let renderers: [MKPolylineRenderer]

    init(renderers: [MKPolylineRenderer]) {
        precondition(!renderers.isEmpty)
        self.renderers = renderers
        super.init(overlay: renderers[0].overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        for renderer in renderers {
            renderer.draw(mapRect, zoomScale: zoomScale, in: context)
        }
    }
}

private extension String {
    func normalizedCityNameForMatching() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}
