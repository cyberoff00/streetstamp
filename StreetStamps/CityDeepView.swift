import Foundation
import SwiftUI
import MapKit
import CoreLocation

private enum CityDeepPalette {
    static let headerBg = Color(red: 251.0 / 255.0, green: 251.0 / 255.0, blue: 249.0 / 255.0)
}

enum CityLevelReconcilePolicy {
    static func shouldFetchFreshProfile(isLoading: Bool, hasExistingOptions: Bool) -> Bool {
        guard !isLoading else { return false }
        return !hasExistingOptions
    }
}

private enum CityDeepDebugLogger {
    static func log(_ domain: String, _ message: String) {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let enabled = args.contains("-CityDeepDebug")
            || UserDefaults.standard.bool(forKey: "city.deep.debug.enabled")
        guard enabled else { return }
        print("🏙️ [CityDeep][\(domain)] \(message)")
#endif
    }
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
    @Environment(\.locale) private var locale
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cache: CityCache
    @EnvironmentObject private var flow: AppFlowCoordinator

    init(city: City) {
        self.city = city
        _displayTitle = State(initialValue: city.localizedName)
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

    private var cityLevelLabelsSignature: String {
        cityLevelOptionLabels
            .map { ($0.key.rawValue, $0.value) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "|")
    }

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
            return CityPlacemarkResolver.displayTitle(for: cached, locale: .current)
        }
        return city.localizedName
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
            CityDeepMKMap(
                segments: styledSegments(),
                memoryGroups: showMemoriesOnMap && !isDataLoading ? groupedMemories : [],
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
        .onChange(of: locale) { _ in
            refreshDisplayTitleFromCardKey()
        }
        .onChange(of: currentJourneys.count) { _ in
            refreshRegionAndBoundary()
        }
        .onChange(of: mapAppearanceRaw) { _ in
            refreshRegionAndBoundary()
        }
        .onChange(of: cityLevelCurrentSelection) { _, _ in
            Task { await ensureActiveCityKeyMatchesCurrentSelection() }
        }
        .onChange(of: cityLevelLabelsSignature) { _, _ in
            Task { await ensureActiveCityKeyMatchesCurrentSelection() }
        }
        .background(SwipeBackEnabler())
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

            let anchorLocation = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            let canonical = await resolveCanonicalForPicker(anchor: anchor)
            let localized = await localizedHierarchyWithRetry(for: anchorLocation)
            guard let canonical else {
                await MainActor.run { cityLevelLoading = false }
                return
            }

            let liveLevels = localized?.availableLevels ?? canonical.availableLevels
            let iso = (canonical.iso2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let sourceKey = await MainActor.run { activeCityKey }
            let sourceCities = await MainActor.run {
                cache.cachedCities.filter { !($0.isTemporary ?? false) }
            }
            let sourceCitiesByKey = Dictionary(uniqueKeysWithValues: sourceCities.map { ($0.id, $0) })
            let sourceCached = sourceCitiesByKey[sourceKey]
            let sourceDisplayLevels = CityPlacemarkResolver.resolvedStableLevelNamesForDisplay(
                storedAvailableLevelNamesRaw: sourceCached?.reservedAvailableLevelNames,
                storedLocaleIdentifier: sourceCached?.reservedAvailableLevelNamesLocaleID,
                freshlyResolvedLevelNames: liveLevels,
                locale: .current
            )
            let selectedNameRaw = sourceDisplayLevels[level] ?? localized?.cityName ?? canonical.availableLevels[level] ?? canonical.cityName
            let selectedName = selectedNameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selectedName.isEmpty else {
                await MainActor.run { cityLevelLoading = false }
                return
            }

            let targetKey = CityPlacemarkResolver.stableCityKey(
                selectedLevel: level,
                canonicalAvailableLevels: canonical.availableLevels,
                fallbackCityKey: sourceKey,
                iso2: canonical.iso2
            )
            let targetCached = sourceCitiesByKey[targetKey]
            let displayLevels = CityPlacemarkResolver.resolvedStableLevelNamesForDisplay(
                storedAvailableLevelNamesRaw: targetCached?.reservedAvailableLevelNames,
                storedLocaleIdentifier: targetCached?.reservedAvailableLevelNamesLocaleID,
                freshlyResolvedLevelNames: liveLevels,
                locale: .current
            )
            let targetNameNorm = selectedName.normalizedCityNameForMatching()

            if targetKey == sourceKey {
                await MainActor.run {
                    cityLevelCurrentSelection = level
                    cityLevelLoading = false
                }
                return
            }

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
                    level: level,
                    parentRegionKey: canonical.parentRegionKey,
                    availableLevels: displayLevels,
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
        CityDeepDebugLogger.log(
            "loadReservedLevelSelection",
            "cityKey=\(activeCityKey) baseLevel=\(baseLevel?.rawValue ?? "nil") parentRegionKey=\(activeCachedCity?.reservedParentRegionKey ?? "nil") hasStoredLevelNames=\((activeCachedCity?.reservedAvailableLevelNames?.isEmpty == false) ? "true" : "false")"
        )
        if let labels = CityPlacemarkResolver.preferredAvailableLevelNamesForDisplay(
            activeCachedCity?.reservedAvailableLevelNames,
            storedLocaleIdentifier: activeCachedCity?.reservedAvailableLevelNamesLocaleID,
            locale: .current
        ) {
            let displayLabels = normalizedCityLevelLabels(labels)
            cityLevelOptionLabels = displayLabels
            let ordered: [CityPlacemarkResolver.CardLevel] = [.island, .locality, .subAdmin, .admin, .country]
            let minRank = baseLevel.map(levelRank) ?? 0
            cityLevelOptions = ordered.filter {
                guard levelRank($0) >= minRank else { return false }
                if let name = displayLabels[$0] {
                    return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return false
            }
            cityLevelCurrentSelection = resolveCurrentLevelFromLabels(
                labels: displayLabels,
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
        let hasExistingOptions = !cityLevelOptions.isEmpty
        let shouldFetch = CityLevelReconcilePolicy.shouldFetchFreshProfile(
            isLoading: cityLevelLoading,
            hasExistingOptions: hasExistingOptions
        )
        CityDeepDebugLogger.log(
            "initializeReservedLevelProfileIfNeeded",
            "cityKey=\(activeCityKey) showPickerWhenReady=\(showPickerWhenReady) isLoading=\(cityLevelLoading) hasExistingOptions=\(hasExistingOptions) shouldFetch=\(shouldFetch)"
        )
        guard shouldFetch else { return }

        if showPickerWhenReady && hasExistingOptions {
            showCityLevelPicker = true
        }

        let shouldShowPickerAfterRefresh = showPickerWhenReady && !hasExistingOptions
        guard let reserveAnchor = reserveJourneyStart, CLLocationCoordinate2DIsValid(reserveAnchor) else {
            CityDeepDebugLogger.log(
                "initializeReservedLevelProfileIfNeeded",
                "cityKey=\(activeCityKey) skip=missingReserveAnchor"
            )
            return
        }

        cityLevelLoading = true
        let loc = CLLocation(latitude: reserveAnchor.latitude, longitude: reserveAnchor.longitude)
        Task {
            CityDeepDebugLogger.log(
                "initializeReservedLevelProfileIfNeeded",
                "cityKey=\(activeCityKey) action=fetchFreshProfile anchor=\(reserveAnchor.latitude),\(reserveAnchor.longitude)"
            )
            let canonical = await canonicalWithRetry(for: loc)
            let localized = await localizedHierarchyWithRetry(for: loc)
            await MainActor.run {
                cityLevelLoading = false
                guard let canonical else {
                    CityDeepDebugLogger.log(
                        "initializeReservedLevelProfileIfNeeded",
                        "cityKey=\(activeCityKey) result=canonical_nil localizedNil=\(localized == nil)"
                    )
                    return
                }
                let liveLabels = localized?.availableLevels ?? canonical.availableLevels
                let labels = CityPlacemarkResolver.resolvedStableLevelNamesForDisplay(
                    storedAvailableLevelNamesRaw: activeCachedCity?.reservedAvailableLevelNames,
                    storedLocaleIdentifier: activeCachedCity?.reservedAvailableLevelNamesLocaleID,
                    freshlyResolvedLevelNames: liveLabels,
                    locale: .current
                )

                let ordered: [CityPlacemarkResolver.CardLevel] = [.island, .locality, .subAdmin, .admin, .country]
                let resolvedCurrent = resolveCurrentLevel(labels: labels, parentRegionKey: canonical.parentRegionKey, options: ordered)
                let baseLevel = activeCachedCity?.reservedLevelRaw
                    .flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) }
                let minRank = baseLevel.map(levelRank) ?? 0
                let options = ordered.filter {
                    guard levelRank($0) >= minRank else { return false }
                    if let name = labels[$0] {
                        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    return false
                }

                cityLevelCanonicalSnapshot = canonical
                cityLevelParentRegionKey = canonical.parentRegionKey
                cityLevelOptionLabels = labels
                cityLevelOptions = options
                cityLevelCurrentSelection = resolveCurrentLevel(labels: labels, parentRegionKey: canonical.parentRegionKey, options: options)
                CityDeepDebugLogger.log(
                    "initializeReservedLevelProfileIfNeeded",
                    "cityKey=\(activeCityKey) result=updated currentSelection=\(cityLevelCurrentSelection?.rawValue ?? "nil") parentRegionKey=\(canonical.parentRegionKey ?? "nil") options=\(options.map { $0.rawValue }.joined(separator: ",")) localizedSource=\(localized == nil ? "canonicalFallback" : "localizedHierarchy")"
                )
                reconcileActiveCityKeyWithSelectionIfNeeded(
                    canonical: canonical,
                    labels: labels,
                    selectedLevel: cityLevelCurrentSelection,
                    anchor: reserveAnchor
                )
                refreshDisplayTitleFromCardKey()
                cache.updateCityLevelReserveProfile(
                    cityKey: activeCityKey,
                    level: cityLevelCurrentSelection ?? baseLevel,
                    parentRegionKey: canonical.parentRegionKey,
                    availableLevels: labels,
                    anchor: reserveAnchor,
                    force: false
                )
                if shouldShowPickerAfterRefresh {
                    showCityLevelPicker = true
                }
            }
        }
    }

    @MainActor
    private func reconcileActiveCityKeyWithSelectionIfNeeded(
        canonical: ReverseGeocodeService.CanonicalResult,
        labels: [CityPlacemarkResolver.CardLevel: String],
        selectedLevel: CityPlacemarkResolver.CardLevel?,
        anchor: CLLocationCoordinate2D
    ) {
        guard let selectedLevel else { return }
        let selectedName = (labels[selectedLevel] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedName.isEmpty else { return }

        let iso = (canonical.iso2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let sourceKey = activeCityKey
        let targetKey = CityPlacemarkResolver.stableCityKey(
            selectedLevel: selectedLevel,
            canonicalAvailableLevels: canonical.availableLevels,
            fallbackCityKey: sourceKey,
            iso2: canonical.iso2
        )
        guard targetKey != sourceKey else { return }

        let candidateJourneyIDs = cityJourneyIDs
        let updatedJourneys: [JourneyRoute] = store.journeys.compactMap { journey in
            guard candidateJourneyIDs.contains(journey.id), journey.isCompleted else { return nil }
            var next = journey
            next.startCityKey = targetKey
            next.cityKey = targetKey
            next.canonicalCity = selectedName
            if !iso.isEmpty {
                next.countryISO2 = iso
            }
            return next
        }

        if !updatedJourneys.isEmpty {
            store.applyBulkCompletedUpdates(updatedJourneys)
            cache.applyCityLevelReassignment(
                from: sourceKey,
                to: targetKey,
                targetCityName: selectedName,
                targetISO2: iso,
                movedJourneys: updatedJourneys,
                anchor: anchor
            )
        }

        cache.updateCityLevelReserveProfile(
            cityKey: targetKey,
            level: selectedLevel,
            parentRegionKey: canonical.parentRegionKey,
            availableLevels: labels,
            anchor: anchor,
            force: true
        )
        activeCityKey = targetKey
    }

    @MainActor
    private func ensureActiveCityKeyMatchesCurrentSelection() async {
        guard !cityLevelLoading else { return }
        let inferredSelection = resolveCurrentLevel(
            labels: cityLevelOptionLabels,
            parentRegionKey: cityLevelParentRegionKey,
            options: cityLevelOptions
        )
        let selectedLevel = cityLevelCurrentSelection ?? inferredSelection
        guard let selectedLevel else { return }
        if cityLevelCurrentSelection == nil {
            cityLevelCurrentSelection = selectedLevel
        }
        guard !cityLevelOptionLabels.isEmpty else { return }
        guard let anchor = reserveJourneyStart, CLLocationCoordinate2DIsValid(anchor) else { return }

        let canonical: ReverseGeocodeService.CanonicalResult? = {
            if let cached = cityLevelCanonicalSnapshot { return cached }
            return nil
        }()

        let resolvedCanonical: ReverseGeocodeService.CanonicalResult?
        if let canonical {
            resolvedCanonical = canonical
        } else {
            let location = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            resolvedCanonical = await canonicalWithRetry(for: location)
            if let resolvedCanonical {
                cityLevelCanonicalSnapshot = resolvedCanonical
                cityLevelParentRegionKey = resolvedCanonical.parentRegionKey
            }
        }

        guard let resolvedCanonical else { return }
        reconcileActiveCityKeyWithSelectionIfNeeded(
            canonical: resolvedCanonical,
            labels: cityLevelOptionLabels,
            selectedLevel: selectedLevel,
            anchor: anchor
        )
        refreshDisplayTitleFromCardKey()
    }

    private func normalizedCityLevelLabels(
        _ labels: [CityPlacemarkResolver.CardLevel: String]
    ) -> [CityPlacemarkResolver.CardLevel: String] {
        guard !labels.isEmpty else { return labels }

        return labels
    }

    private func resolveCurrentLevel(
        labels: [CityPlacemarkResolver.CardLevel: String],
        parentRegionKey: String?,
        options: [CityPlacemarkResolver.CardLevel]
    ) -> CityPlacemarkResolver.CardLevel? {
        if let preferred = CityLevelPreferenceStore.shared.preferredLevel(for: parentRegionKey),
           options.contains(preferred) {
            return preferred
        }

        let currentName = cityName(from: activeCityKey).normalizedCityNameForMatching()
        guard !currentName.isEmpty else { return nil }
        for level in options {
            let name = (labels[level] ?? "").normalizedCityNameForMatching()
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
        let parentRegionKey = cityLevelParentRegionKey ?? activeCachedCity?.reservedParentRegionKey
        if !cityLevelOptionLabels.isEmpty {
            return CityPlacemarkResolver.displayTitle(
                cityKey: activeCityKey,
                iso2: effectiveCountryISO2,
                fallbackTitle: effectiveCityName,
                availableLevelNames: cityLevelOptionLabels,
                parentRegionKey: parentRegionKey,
                preferredLevel: cityLevelCurrentSelection,
                localizedDisplayNameByLocale: activeCachedCity?.localizedDisplayNameByLocale,
                locale: .current
            )
        }

        if let activeCachedCity {
            return CityPlacemarkResolver.displayTitle(
                cityKey: activeCachedCity.id,
                iso2: activeCachedCity.countryISO2,
                fallbackTitle: activeCachedCity.name,
                availableLevelNamesRaw: activeCachedCity.reservedAvailableLevelNames,
                storedAvailableLevelNamesLocaleID: activeCachedCity.reservedAvailableLevelNamesLocaleID,
                parentRegionKey: parentRegionKey,
                preferredLevel: activeCachedCity.reservedLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
                localizedDisplayNameByLocale: activeCachedCity.localizedDisplayNameByLocale,
                locale: .current
            )
        }

        let fromKey = CityPlacemarkResolver.displayTitle(
            cityKey: activeCityKey,
            iso2: effectiveCountryISO2,
            fallbackTitle: effectiveCityName,
            parentRegionKey: parentRegionKey,
            preferredLevel: cityLevelCurrentSelection,
            locale: .current
        )
        let trimmed = fromKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? city.localizedName : trimmed
    }

    private func formatHeaderTitle(baseName: String) -> String {
        let base = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return city.localizedName }

        let iso = (effectiveCountryISO2 ?? isoFromCityKey(activeCityKey)).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if iso == "US",
           let admin = cityLevelOptionLabels[.admin]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !admin.isEmpty {
            // Guard against double-appending: base may already contain the state
            // (e.g. "San Francisco, California" from localizedDisplayNameByLocale).
            let baseNorm = base.normalizedCityNameForMatching()
            let adminNorm = admin.normalizedCityNameForMatching()
            if adminNorm != baseNorm && !baseNorm.contains(adminNorm) {
                return "\(base), \(admin)"
            }
        }
        return base
    }

    private func refreshDisplayTitleFromCardKey() {
        displayTitle = formatHeaderTitle(baseName: headerBaseCityName())
    }

    private func cityName(from cityKey: String) -> String {
        if let cached = cache.cachedCities.first(where: { $0.id == cityKey && !($0.isTemporary ?? false) }) {
            return CityPlacemarkResolver.displayTitle(for: cached, locale: .current)
        }

        let fallbackTitle = cityKey.components(separatedBy: "|").first ?? cityKey
        return CityPlacemarkResolver.displayTitle(
            cityKey: cityKey,
            iso2: isoFromCityKey(cityKey),
            fallbackTitle: fallbackTitle,
            parentRegionKey: cityLevelParentRegionKey ?? activeCachedCity?.reservedParentRegionKey,
            preferredLevel: cityLevelCurrentSelection,
            locale: .current
        )
    }

    private func canonicalWithRetry(for location: CLLocation) async -> ReverseGeocodeService.CanonicalResult? {
        if let first = await ReverseGeocodeService.shared.canonical(for: location) {
            return first
        }
        try? await Task.sleep(nanoseconds: 1_650_000_000)
        return await ReverseGeocodeService.shared.canonical(for: location)
    }

    private func localizedHierarchyWithRetry(for location: CLLocation) async -> ReverseGeocodeService.CanonicalResult? {
        if let first = await ReverseGeocodeService.shared.localizedHierarchy(for: location) {
            CityDeepDebugLogger.log(
                "localizedHierarchyWithRetry",
                "cityKey=\(activeCityKey) attempt=1 result=hit parentRegionKey=\(first.parentRegionKey ?? "nil") locale=\(first.localeIdentifier)"
            )
            return first
        }
        try? await Task.sleep(nanoseconds: 1_650_000_000)
        let second = await ReverseGeocodeService.shared.localizedHierarchy(for: location)
        CityDeepDebugLogger.log(
            "localizedHierarchyWithRetry",
            "cityKey=\(activeCityKey) attempt=2 result=\(second == nil ? "nil" : "hit")"
        )
        return second
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
        L10n.t("city_level_picker_title")
    }

    private func levelDialogCancelTitle() -> String {
        L10n.t("city_level_picker_cancel")
    }

    private func levelDialogButtonLabel(for level: CityPlacemarkResolver.CardLevel, selected: Bool) -> String {
        let placeName = cityLevelOptionLabels[level]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = placeName.isEmpty ? "" : " · \(placeName)"
        let prefix = selected ? "✓ " : ""
        return prefix + localizedLevelName(for: level) + suffix
    }

    private func cityLevelConfirmTitle() -> String {
        L10n.t("city_level_confirm_title")
    }

    private func cityLevelConfirmApplyTitle() -> String {
        L10n.t("city_level_confirm_apply")
    }

    private func cityLevelConfirmMessage() -> String {
        if let pending = pendingCityLevelSelection,
           let current = cityLevelCurrentSelection,
           levelRank(pending) > levelRank(current) {
            return L10n.t("city_level_confirm_upgrade_message")
        }
        return L10n.t("city_level_confirm_future_default_message")
    }

    private func cityLevelDowngradeBlockedTitle() -> String {
        L10n.t("city_level_downgrade_blocked_title")
    }

    private func cityLevelDowngradeBlockedMessage() -> String {
        if let from = cityLevelCurrentSelection, let to = blockedCityLevelSelection {
            let fromName = levelNameForHint(from)
            let toName = levelNameForHint(to)
            return String(
                format: L10n.t("city_level_downgrade_blocked_message_format"),
                locale: Locale.current,
                fromName,
                toName
            )
        }
        return String(
            format: L10n.t("city_level_downgrade_blocked_message_format"),
            locale: Locale.current,
            localizedLevelName(for: .locality),
            localizedLevelName(for: .admin)
        )
    }

    private func levelNameForHint(_ level: CityPlacemarkResolver.CardLevel) -> String {
        localizedLevelName(for: level)
    }

    private var shouldDisplayRegionForCurrentCity: Bool {
        let iso = (effectiveCountryISO2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ["HK", "MO", "TW"].contains(iso)
    }

    private func localizedLevelName(for level: CityPlacemarkResolver.CardLevel) -> String {
        switch level {
        case .locality:
            return L10n.t("city_level_locality")
        case .subAdmin:
            return L10n.t("city_level_sub_admin")
        case .admin:
            return L10n.t("city_level_admin")
        case .island:
            return L10n.t("city_level_island")
        case .country:
            return L10n.t(shouldDisplayRegionForCurrentCity ? "city_level_region" : "city_level_country")
        }
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
