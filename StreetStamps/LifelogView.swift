import SwiftUI
import MapKit
import UIKit
import HealthKit

enum LifelogStepMilestoneCloseButtonPlacement: Equatable {
    case topTrailing
}

enum LifelogStepMilestonePresentation {
    static let supportsBackdropDismiss = true
    static let showsFooterCloseButton = false
    static let closeButtonPlacement: LifelogStepMilestoneCloseButtonPlacement = .topTrailing
}

enum LifelogRenderModeSelector {
    static let nearModeLatitudeDeltaThreshold: CLLocationDegrees = 0.05
    static let nearModeLongitudeDeltaThreshold: CLLocationDegrees = 0.05
    static let footprintStepMeters: CLLocationDistance = 80

    static func isNearMode(_ region: MKCoordinateRegion?) -> Bool {
        guard let region else { return false }
        return abs(region.span.latitudeDelta) <= nearModeLatitudeDeltaThreshold &&
            abs(region.span.longitudeDelta) <= nearModeLongitudeDeltaThreshold
    }

    static func viewportMaxSpanMeters(for region: MKCoordinateRegion) -> CLLocationDistance {
        let centerLat = clampLatitude(region.center.latitude)
        let centerLon = normalizeLongitude(region.center.longitude)
        let halfLat = abs(region.span.latitudeDelta) / 2.0
        let halfLon = abs(region.span.longitudeDelta) / 2.0

        let north = CLLocation(
            latitude: clampLatitude(centerLat + halfLat),
            longitude: centerLon
        )
        let south = CLLocation(
            latitude: clampLatitude(centerLat - halfLat),
            longitude: centerLon
        )
        let east = CLLocation(
            latitude: centerLat,
            longitude: normalizeLongitude(centerLon + halfLon)
        )
        let west = CLLocation(
            latitude: centerLat,
            longitude: normalizeLongitude(centerLon - halfLon)
        )

        let verticalMeters = north.distance(from: south)
        let horizontalMeters = east.distance(from: west)
        return max(verticalMeters, horizontalMeters)
    }

    private static func clampLatitude(_ value: CLLocationDegrees) -> CLLocationDegrees {
        min(max(value, -89.999_999), 89.999_999)
    }

    private static func normalizeLongitude(_ value: CLLocationDegrees) -> CLLocationDegrees {
        var out = value.truncatingRemainder(dividingBy: 360)
        if out > 180 { out -= 360 }
        if out < -180 { out += 360 }
        return out
    }
}

private struct LifelogShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum LifelogFootprintSampler {
    private static let turnThresholdDegrees: CLLocationDirection = 24
    private static let minimumTurnLegMeters: CLLocationDistance = 18
    private static let maximumStraightSpanMeters: CLLocationDistance = 140
    private static let fillDistanceThresholds: [CLLocationDistance] = [90, 180, 320]
    private static let maximumFillPointsPerSpan = 3

    static func sample(
        route coords: [CLLocationCoordinate2D],
        stepMeters: CLLocationDistance,
        gapBreakMeters: CLLocationDistance
    ) -> [CLLocationCoordinate2D] {
        guard coords.count > 1 else { return coords }
        guard stepMeters > 0 else { return coords }

        let runs = splitRuns(coords, gapBreakMeters: gapBreakMeters)
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(coords.count)

        for run in runs {
            let sampledRun = sampleContinuousRun(run, stepMeters: stepMeters)
            appendDeduplicating(sampledRun, into: &result)
        }

        return result.isEmpty ? [coords[0]] : result
    }

    private static func interpolateCoordinate(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D,
        t: Double
    ) -> CLLocationCoordinate2D {
        let clamped = min(max(t, 0), 1)
        let lat = a.latitude + (b.latitude - a.latitude) * clamped
        let lon = a.longitude + (b.longitude - a.longitude) * clamped
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func sampleContinuousRun(
        _ run: [CLLocationCoordinate2D],
        stepMeters: CLLocationDistance
    ) -> [CLLocationCoordinate2D] {
        guard run.count > 1 else { return run }

        let anchorIndices = anchorIndices(for: run)
        guard anchorIndices.count > 1 else { return [run[0], run[run.count - 1]] }

        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(anchorIndices.count * 2)

        for pairIndex in 0..<(anchorIndices.count - 1) {
            let startIndex = anchorIndices[pairIndex]
            let endIndex = anchorIndices[pairIndex + 1]
            let start = run[startIndex]
            let end = run[endIndex]
            let pathSlice = Array(run[startIndex...endIndex])
            let distance = pathDistanceMeters(pathSlice)

            if !sameCoordinate(result.last, start) {
                result.append(start)
            }

            let spanAnchors = straightSpanAnchorCount(distance: distance)
            if spanAnchors > 0 {
                for anchorIndex in 1...spanAnchors {
                    let t = Double(anchorIndex) / Double(spanAnchors + 1)
                    result.append(coordinate(along: pathSlice, progress: t))
                }
            } else {
                let fillCount = fillPointCount(distance: distance, stepMeters: stepMeters)
                if fillCount > 0 {
                    for fillIndex in 1...fillCount {
                        let t = Double(fillIndex) / Double(fillCount + 1)
                        result.append(coordinate(along: pathSlice, progress: t))
                    }
                }
            }

            if !sameCoordinate(result.last, end) {
                result.append(end)
            }
        }

        return deduplicated(result)
    }

    private static func splitRuns(
        _ coords: [CLLocationCoordinate2D],
        gapBreakMeters: CLLocationDistance
    ) -> [[CLLocationCoordinate2D]] {
        guard !coords.isEmpty else { return [] }

        var runs: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = [coords[0]]

        for idx in 1..<coords.count {
            let previous = coords[idx - 1]
            let currentCoord = coords[idx]
            let distance = distanceMeters(from: previous, to: currentCoord)

            if distance > gapBreakMeters {
                runs.append(deduplicated(current))
                current = [currentCoord]
                continue
            }

            current.append(currentCoord)
        }

        if !current.isEmpty {
            runs.append(deduplicated(current))
        }

        return runs.filter { !$0.isEmpty }
    }

    private static func anchorIndices(for run: [CLLocationCoordinate2D]) -> [Int] {
        guard run.count > 2 else { return Array(run.indices) }

        var anchors = IndexSet()
        anchors.insert(0)
        anchors.insert(run.count - 1)

        for idx in 1..<(run.count - 1) {
            guard isTurnAnchor(at: idx, in: run) else { continue }
            anchors.insert(idx)
        }

        return anchors.map(\.self)
    }

    private static func isTurnAnchor(at index: Int, in run: [CLLocationCoordinate2D]) -> Bool {
        guard index > 0, index < run.count - 1 else { return false }

        let previous = run[index - 1]
        let current = run[index]
        let next = run[index + 1]
        let incomingDistance = distanceMeters(from: previous, to: current)
        let outgoingDistance = distanceMeters(from: current, to: next)

        guard incomingDistance >= minimumTurnLegMeters, outgoingDistance >= minimumTurnLegMeters else {
            return false
        }

        let incomingHeading = headingDegrees(from: previous, to: current)
        let outgoingHeading = headingDegrees(from: current, to: next)
        let delta = headingDeltaDegrees(from: incomingHeading, to: outgoingHeading)
        return delta >= turnThresholdDegrees
    }

    private static func straightSpanAnchorCount(distance: CLLocationDistance) -> Int {
        guard distance > maximumStraightSpanMeters else { return 0 }
        return max(0, Int(ceil(distance / maximumStraightSpanMeters)) - 1)
    }

    private static func fillPointCount(
        distance: CLLocationDistance,
        stepMeters: CLLocationDistance
    ) -> Int {
        let normalizedStep = max(stepMeters, 1)
        let adjustedThresholds = fillDistanceThresholds.map { max($0, normalizedStep * 1.8) }

        switch distance {
        case ..<adjustedThresholds[0]:
            return 0
        case ..<adjustedThresholds[1]:
            return 1
        case ..<adjustedThresholds[2]:
            return 2
        default:
            return maximumFillPointsPerSpan
        }
    }

    private static func appendDeduplicating(
        _ coords: [CLLocationCoordinate2D],
        into result: inout [CLLocationCoordinate2D]
    ) {
        for coord in coords where !sameCoordinate(result.last, coord) {
            result.append(coord)
        }
    }

    private static func deduplicated(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(coords.count)
        appendDeduplicating(coords, into: &result)
        return result
    }

    private static func distanceMeters(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private static func pathDistanceMeters(_ coords: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coords.count > 1 else { return 0 }

        var total: CLLocationDistance = 0
        for index in 1..<coords.count {
            total += distanceMeters(from: coords[index - 1], to: coords[index])
        }
        return total
    }

    private static func coordinate(
        along path: [CLLocationCoordinate2D],
        progress: Double
    ) -> CLLocationCoordinate2D {
        guard path.count > 1 else { return path.first ?? .init() }

        let clamped = min(max(progress, 0), 1)
        if clamped <= 0 { return path[0] }
        if clamped >= 1 { return path[path.count - 1] }

        let totalDistance = pathDistanceMeters(path)
        guard totalDistance > 0 else { return path[0] }

        let targetDistance = totalDistance * clamped
        var traversed: CLLocationDistance = 0

        for index in 1..<path.count {
            let start = path[index - 1]
            let end = path[index]
            let segmentDistance = distanceMeters(from: start, to: end)
            guard segmentDistance > 0.001 else { continue }

            if traversed + segmentDistance >= targetDistance {
                let remaining = targetDistance - traversed
                let localT = remaining / segmentDistance
                return interpolateCoordinate(from: start, to: end, t: localT)
            }

            traversed += segmentDistance
        }

        return path[path.count - 1]
    }

    private static func headingDegrees(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = a.latitude * .pi / 180
        let lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let lon2 = b.longitude * .pi / 180
        let deltaLon = lon2 - lon1
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let heading = atan2(y, x) * 180 / .pi
        return heading.isFinite ? heading : 0
    }

    private static func headingDeltaDegrees(
        from lhs: CLLocationDirection,
        to rhs: CLLocationDirection
    ) -> CLLocationDirection {
        let raw = abs(rhs - lhs).truncatingRemainder(dividingBy: 360)
        return raw > 180 ? 360 - raw : raw
    }

    private static func sameCoordinate(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D) -> Bool {
        guard let a else { return false }
        return abs(a.latitude - b.latitude) < 0.000_000_1 && abs(a.longitude - b.longitude) < 0.000_000_1
    }
}

enum LifelogFootprintProjector {
    static func projectRuns(
        from routeRuns: [[CLLocationCoordinate2D]],
        stepMeters: CLLocationDistance,
        gapBreakMeters: CLLocationDistance,
        countryISO2: String?,
        cityKey: String?
    ) -> [[CLLocationCoordinate2D]] {
        routeRuns.flatMap { run -> [[CLLocationCoordinate2D]] in
            guard !run.isEmpty else { return [] }

            let segments = RouteRenderingPipeline.buildSegments(
                .init(
                    coordsWGS84: run,
                    applyGCJForChina: false,
                    gapDistanceMeters: gapBreakMeters,
                    countryISO2: countryISO2,
                    cityKey: cityKey
                ),
                surface: .canvas
            ).segments

            let solidSegments = segments.filter { $0.style == .solid && !$0.coords.isEmpty }
            if !solidSegments.isEmpty {
                return solidSegments.compactMap { segment in
                    let sampled = LifelogFootprintSampler.sample(
                        route: segment.coords,
                        stepMeters: stepMeters,
                        gapBreakMeters: gapBreakMeters
                    )
                    return sampled.isEmpty ? nil : sampled
                }
            }

            // If a run is only a dashed jump, keep isolated endpoints but never sample across it.
            var isolated: [[CLLocationCoordinate2D]] = []
            for segment in segments where segment.style == .dashed {
                guard let first = segment.coords.first else { continue }
                isolated.append([first])
                if let last = segment.coords.last, !sameCoordinate(first, last) {
                    isolated.append([last])
                }
            }
            return isolated
        }
    }

    private static func sameCoordinate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 0.000_000_1 &&
        abs(a.longitude - b.longitude) < 0.000_000_1
    }
}
struct LifelogView: View {
    @ObservedObject private var tracking = TrackingService.shared
    @EnvironmentObject private var lifelogStore: LifelogStore
    @EnvironmentObject private var trackTileStore: TrackTileStore
    @EnvironmentObject private var locationHub: LocationHub
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var lifelogRenderCache: LifelogRenderCacheCoordinator
    @EnvironmentObject private var flow: AppFlowCoordinator
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"
    @AppStorage(AppSettings.avatarHeadlightEnabledKey) private var avatarHeadlightEnabled = true

    @State private var position: MapCameraPosition = .automatic
    @State private var showGlobe = false
    @State private var showEnableHint = false
    @State private var showDisableConfirm = false
    @State private var showPermissionSettingsPrompt = false
    @State private var showAlwaysLocationGuide = false
    @AppStorage("streetstamps.lifelog.alwaysLocationGuideShown") private var alwaysLocationGuideShown = false
    @State private var shareItem: LifelogShareImageItem? = nil
    @State private var didCenterOnEnter = false
    @State private var selectedDay: Date? = nil
    @State private var moodPickerDay: Date? = nil
    @State private var isMoodPopupVisible = false
    @State private var isStepPopupVisible = false
    @State private var isRefreshingSteps = false
    @State private var isStepModalVisible = false
    @State private var stepModalStepCount = 0
    @State private var hasHealthStepPermission = false
    @State private var calendarDisplayMode: CalendarDisplayMode = .day
    @State private var visibleMonthAnchor: Date = Calendar.current.startOfDay(for: Date())
    @State private var isSheetExpanded = true
    @State private var bottomDockHeight: CGFloat = 0
    @State private var visibleRegion: MKCoordinateRegion? = nil
    @State private var cameraRegion: MKCoordinateRegion? = nil
    @State private var renderSnapshot: LifelogRenderSnapshot = .empty
    @State private var renderTask: Task<Void, Never>? = nil
    @State private var renderGenerationState = LifelogRenderGenerationState()
    @State private var pendingRecenterDay: Date? = nil
    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue
    @AppStorage("streetstamps.lifelog.health.steps.snapshot.byday") private var stepSnapshotByDayRaw = ""
    @AppStorage("streetstamps.lifelog.health.steps.snapshot.day") private var legacyStepSnapshotDay = ""
    @AppStorage("streetstamps.lifelog.health.steps.snapshot.value") private var legacyStepSnapshotValue = 0
    @AppStorage("streetstamps.lifelog.steps.popup.prompted.day") private var stepPopupPromptedDay = ""
    @AppStorage("streetstamps.lifelog.steps.popup.prompted.value") private var stepPopupPromptedValue = 0
    @AppStorage("streetstamps.lifelog.steps.badge.prompted.day") private var stepBadgePromptedDay = ""
    @AppStorage("streetstamps.lifelog.mood.prompted.day") private var moodPromptedDay = ""
    @State private var footprintViewportCache = LifelogFootprintViewportCache()

    private var mapAppearance: MapAppearanceStyle {
        MapAppearanceStyle(rawValue: mapAppearanceRaw) ?? .dark
    }
    private var isDarkAppearance: Bool { mapAppearance == .dark }
    private var panelBackground: Color { isDarkAppearance ? Color.black.opacity(0.80) : FigmaTheme.card.opacity(0.96) }
    private var panelText: Color { isDarkAppearance ? .white : .black }
    private var isNearFootprintMode: Bool {
        LifelogRenderModeSelector.isNearMode(cameraRegion ?? visibleRegion)
    }

    private var renderViewportRefreshKey: String {
        guard let region = visibleRegion else { return "nil" }
        return String(
            format: "%.4f|%.4f|%.4f|%.4f|%d",
            region.center.latitude,
            region.center.longitude,
            region.span.latitudeDelta,
            region.span.longitudeDelta,
            renderLodLevel
        )
    }

    private var farRouteSegments: [RenderRouteSegment] {
        guard !isNearFootprintMode else { return [] }
        return renderSnapshot.farRouteSegments
    }

    private var footprintRuns: [[CLLocationCoordinate2D]] {
        guard isNearFootprintMode else { return [] }
        return renderSnapshot.footprintRuns
    }

    private var footprintMapMarkers: [LifelogFootprintProjectedMarker] {
        guard isNearFootprintMode else { return [] }
        guard let region = cameraRegion ?? visibleRegion else { return [] }

        let key = LifelogFootprintViewportCache.Key(
            lodLevel: renderLodLevel,
            region: region,
            runsSignature: LifelogFootprintRenderPlanner.runsSignature(footprintRuns),
            exclusionCoordinate: currentDisplayLocation?.coordinate
        )
        return footprintViewportCache.value(for: key) {
            LifelogFootprintRenderPlanner.plannedMarkers(
                from: footprintRuns,
                region: region,
                lodLevel: renderLodLevel,
                currentCoordinate: currentDisplayLocation?.coordinate
            )
        }
    }

    private var currentDisplayLocation: CLLocation? {
        let source: CLLocation?
        if let loc = lifelogStore.currentLocation {
            source = loc
        } else if let loc = locationHub.currentLocation {
            source = loc
        } else {
            source = locationHub.lastKnownLocation
        }
        guard let source else { return nil }
        let mapped = mapCoordForLifelog(source.coordinate)
        return CLLocation(
            coordinate: mapped,
            altitude: source.altitude,
            horizontalAccuracy: source.horizontalAccuracy,
            verticalAccuracy: source.verticalAccuracy,
            timestamp: source.timestamp
        )
    }

    private var isViewingToday: Bool {
        guard let selectedDay else { return true }
        return Calendar.current.isDateInToday(selectedDay)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                mapLayer
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        header
                        permissionHint
                            .padding(.horizontal, 16)
                            .padding(.top, 10)

                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                stepPopupToggleButton
                                if isStepPopupVisible {
                                    stepCompactBadge
                                }
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 10)
                    }

                    Spacer()

                    bottomDock
                        .offset(y: bottomSheetOffset())
                        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: isSheetExpanded)
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onEnded { value in
                                    let threshold: CGFloat = 72
                                    let dy = value.translation.height
                                    if isSheetExpanded, dy > threshold {
                                        isSheetExpanded = false
                                    } else if !isSheetExpanded, dy < -threshold {
                                        isSheetExpanded = true
                                    }
                                }
                        )
                }

                floatingBottomRightButtons(bottomInset: proxy.safeAreaInsets.bottom + 24)

                if isMoodPopupVisible {
                    moodPickerPopup
                }
                if isStepModalVisible {
                    stepMilestoneModal
                }
            }
        }
        .fullScreenCover(isPresented: $showGlobe) {
            GlobeViewScreen(showSidebar: .constant(false))
                .environmentObject(store)
                .environmentObject(cityCache)
                .environmentObject(lifelogStore)
                .environmentObject(trackTileStore)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.image])
        }
        .sheet(isPresented: $showAlwaysLocationGuide) {
            AlwaysLocationGuideView(isPresented: $showAlwaysLocationGuide, onEnable: {
                alwaysLocationGuideShown = true
                locationHub.requestAlwaysPermissionIfNeeded()
            })
        }
        .alert(L10n.t("lifelog_disable_title"), isPresented: $showDisableConfirm) {
            Button(L10n.t("lifelog_continue_recording"), role: .cancel) {}
            Button(L10n.t("lifelog_confirm_disable"), role: .destructive) {
                lifelogStore.setEnabled(false)
            }
        } message: {
            Text(L10n.t("lifelog_disable_message"))
        }
        .alert(L10n.t("lifelog_permission_settings_title"), isPresented: $showPermissionSettingsPrompt) {
            Button(L10n.t("lifelog_permission_settings_action")) {
                openAppSettings()
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("lifelog_permission_settings_message"))
        }
        .onAppear {
            didCenterOnEnter = false
            seedSelectedDayIfNeeded()
            migrateLegacyStepSnapshotIfNeeded()
            visibleMonthAnchor = monthStart(for: selectedDay ?? Date())
            if locationHub.authorizationStatus != .authorizedAlways {
                if !alwaysLocationGuideShown {
                    showAlwaysLocationGuide = true
                } else {
                    showEnableHint = true
                }
            }
            centerOnCurrent(force: true)
            scheduleRenderSnapshotRefresh()
            Task {
                await refreshHealthPermissionState()
                await requestHealthPermissionIfNeeded()
                await captureStepSnapshotIfNeeded(for: Calendar.current.startOfDay(for: Date()), force: true)
                if stepBadgePromptedDay != todayKey() {
                    stepBadgePromptedDay = todayKey()
                    isStepPopupVisible = true
                }
                await presentStepModalIfNeeded()
                if !isStepModalVisible {
                    presentMoodPopupIfNeeded()
                }
            }
        }
        .onDisappear {
            renderTask?.cancel()
            renderTask = nil
        }
        .onChange(of: lifelogStore.availableDays) { _ in
            seedSelectedDayIfNeeded()
        }
        .onChange(of: lifelogStore.currentLocation?.coordinate.latitude) { _ in
            centerOnCurrent(force: false)
        }
        .onChange(of: lifelogStore.currentLocation?.coordinate.longitude) { _ in
            centerOnCurrent(force: false)
        }
        .onChange(of: locationHub.currentLocation?.coordinate.latitude) { _ in
            centerOnCurrent(force: false)
        }
        .onChange(of: locationHub.currentLocation?.coordinate.longitude) { _ in
            centerOnCurrent(force: false)
        }
        .onChange(of: store.trackTileRevision) { _ in
            scheduleRenderSnapshotRefresh()
        }
        .onChange(of: lifelogStore.trackTileRevision) { _ in
            scheduleRenderSnapshotRefresh()
        }
        .onChange(of: trackTileStore.refreshRevision) { _ in
            scheduleRenderSnapshotRefresh()
        }
        .onChange(of: lifelogStore.countryISO2) { _ in
            scheduleRenderSnapshotRefresh()
        }
        .onChange(of: locationHub.countryISO2) { _ in
            scheduleRenderSnapshotRefresh()
        }
        .onChange(of: renderViewportRefreshKey) { _ in
            scheduleRenderSnapshotRefresh(debounceNanoseconds: 120_000_000)
        }
        .onChange(of: selectedDay) { _ in
            scheduleRenderSnapshotRefresh()
            guard isStepPopupVisible else { return }
            Task {
                isRefreshingSteps = true
                await captureStepSnapshotIfNeeded(for: Calendar.current.startOfDay(for: selectedDay ?? Date()), force: true)
                isRefreshingSteps = false
            }
        }
    }

    private var mapLayer: some View {
        Map(position: $position) {
            if !isNearFootprintMode {
                ForEach(farRouteSegments) { seg in
                    let base = Color(uiColor: MapAppearanceSettings.routeBaseColor)
                    let dash = RouteRenderStyleTokens.dashLengths

                    MapPolyline(coordinates: seg.coords)
                        .stroke(
                            base.opacity(seg.style == .dashed ? 0.08 : 0.12),
                            style: StrokeStyle(
                                lineWidth: seg.style == .dashed ? 2.0 : 3.0,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: seg.style == .dashed ? dash : []
                            )
                        )
                    MapPolyline(coordinates: seg.coords)
                        .stroke(
                            base.opacity(seg.style == .dashed ? 0.0 : 0.08),
                            style: StrokeStyle(
                                lineWidth: seg.style == .dashed ? 0.0 : 2.2,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    MapPolyline(coordinates: seg.coords)
                        .stroke(
                            base.opacity(seg.style == .dashed ? 0.30 : 0.84),
                            style: StrokeStyle(
                                lineWidth: seg.style == .dashed ? 1.1 : 1.6,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: seg.style == .dashed ? dash : []
                            )
                        )
                }
            }

            ForEach(Array(footprintMapMarkers.enumerated()), id: \.offset) { _, marker in
                Annotation("", coordinate: marker.coordinate) {
                    FootstepGlyph(isDark: isDarkAppearance)
                        .rotationEffect(.degrees(marker.angleDegrees))
                }
            }

            if let loc = currentDisplayLocation {
                Annotation("", coordinate: loc.coordinate) {
                    VStack(spacing: 2) {
                        if shouldShowMoodQuestionMark {
                            Button {
                                moodPickerDay = Calendar.current.startOfDay(for: Date())
                                isMoodPopupVisible = true
                            } label: {
                                Text("❓")
                                    .font(.system(size: 21))
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(Color(red: 1.0, green: 249 / 255.0, blue: 221 / 255.0))
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color(red: 1.0, green: 191 / 255.0, blue: 84 / 255.0), lineWidth: 1.5)
                                    )
                                    .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }

                        ZStack {
                            if avatarHeadlightEnabled {
                                AvatarHeadlightConeView(headingDegrees: currentHeadingDegrees)
                                    .allowsHitTesting(false)
                            }

                            RobotRendererView(
                                size: AvatarMapMarkerStyle.visualSize,
                                face: .front,
                                loadout: AvatarLoadoutStore.load()
                            )
                        }
                        .frame(width: AvatarMapMarkerStyle.annotationSize, height: AvatarMapMarkerStyle.annotationSize)
                        .shadow(color: .black.opacity(0.24), radius: 8, y: 2)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            openEquipmentView()
                        }
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: shouldShowMoodQuestionMark)
                }
            }
        }
        .mapStyle(
            .standard(
                elevation: .flat,
                emphasis: MapAppearanceSettings.usesMutedStandardMap(for: mapAppearance) ? .muted : .automatic,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            )
        )
        // Keep lifelog map dark/light switch local to the map surface.
        .environment(\.colorScheme, isDarkAppearance ? .dark : .light)
        .onMapCameraChange { context in
            let incoming = context.region
            cameraRegion = incoming
            if shouldUpdateVisibleRegion(incoming) {
                visibleRegion = incoming
            }
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Color.clear
                    .frame(width: 42, height: 42)

                Spacer()

                Button {
                    showGlobe = true
                } label: {
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(FigmaTheme.text)
                        .frame(width: 42, height: 42)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Text("WORLDO")
                .navigationTitleStyle(level: .primary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(FigmaTheme.card.opacity(0.92).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FigmaTheme.border)
                .frame(height: 1)
        }
    }

    private var shouldShowMoodQuestionMark: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return lifelogStore.mood(for: today) == nil
    }

    private var recenterButton: some View {
        Button {
            centerOnCurrent(force: true)
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FigmaTheme.text)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.92))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.10), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var permissionHint: some View {
        if showEnableHint && locationHub.authorizationStatus != .authorizedAlways {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("lifelog_permission_hint"))
                    .appCaptionStyle()
                    .foregroundColor(panelText)
                Button(L10n.t("lifelog_permission_action")) {
                    handleAlwaysPermissionAction()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isDarkAppearance ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isDarkAppearance ? Color.white : Color.black)
                .clipShape(Capsule())
            }
            .padding(12)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 10)
        }
    }

    private var bottomCard: some View {
        let totalMemories = store.journeys.reduce(0) { $0 + $1.memories.count }
        let cityCount = cityCache.cachedCities.filter { !($0.isTemporary ?? false) }.count
        let levelProgress = UserLevelProgress.from(journeys: store.journeys)
        let cardContent = ProfileSummaryCardContent(
            level: levelProgress.level,
            cityCount: cityCount,
            memoryCount: totalMemories,
            locale: .current
        )

        return HStack(spacing: 14) {
            Button {
                openEquipmentView()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 200.0 / 255.0, green: 232.0 / 255.0, blue: 221.0 / 255.0))
                        .frame(width: 68, height: 68)

                    RobotRendererView(size: 56, face: .front, loadout: AvatarLoadoutStore.load())
                }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                LevelBadgeView(level: levelProgress.level)
                    .offset(x: 10, y: -10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(normalizedDisplayName(profileName))
                    .appBodyStrongStyle()
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)

                Text(cardContent.levelText)
                    .appCaptionStyle()
                    .foregroundColor(FigmaTheme.text.opacity(0.62))
                    .lineLimit(1)

                Text(cardContent.statsText)
                    .appFootnoteStyle()
                    .foregroundColor(FigmaTheme.text.opacity(0.56))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button {
                if let image = captureCurrentPageImage() {
                    shareItem = LifelogShareImageItem(image: image)
                }
            } label: {
                Label(L10n.t("share"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(UITheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
    }

    private var lifelogRecordToggle: some View {
        Button {
            if hasAlwaysPermission {
                showEnableHint = false
            }

            if !hasAlwaysPermission {
                handleUnavailableAlwaysPermissionToggleTap()
                return
            }

            if lifelogStore.isEnabled {
                showDisableConfirm = true
            } else {
                lifelogStore.setEnabled(true)
            }
        } label: {
            Circle()
                .fill((hasAlwaysPermission && lifelogStore.isEnabled) ? Color(red: 0.42, green: 0.78, blue: 0.58) : Color.gray.opacity(0.65))
                .frame(width: 12, height: 12)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.92))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.10), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func handleAlwaysPermissionAction() {
        switch locationHub.authorizationStatus {
        case .authorizedAlways:
            showEnableHint = false
        case .denied, .restricted:
            openAppSettings()
        case .notDetermined, .authorizedWhenInUse:
            locationHub.requestAlwaysPermissionIfNeeded()
        @unknown default:
            locationHub.requestAlwaysPermissionIfNeeded()
        }
    }

    private func openEquipmentView() {
        flow.requestOpenSidebarDestination(.equipment)
    }

    private var hasAlwaysPermission: Bool {
        locationHub.authorizationStatus == .authorizedAlways
    }

    private func handleUnavailableAlwaysPermissionToggleTap() {
        showEnableHint = true
        switch locationHub.authorizationStatus {
        case .notDetermined:
            locationHub.requestAlwaysPermissionIfNeeded()
        case .authorizedWhenInUse, .denied, .restricted:
            showPermissionSettingsPrompt = true
        @unknown default:
            showPermissionSettingsPrompt = true
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var bottomDock: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color.black.opacity(0.12))
                .frame(width: 52, height: 6)
                .padding(.top, 4)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                        isSheetExpanded.toggle()
                    }
                }

            bottomCard

            calendarPanel
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 30,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 30,
                style: .continuous
            )
            .fill(Color.white.opacity(0.94))
            .ignoresSafeArea(edges: .bottom)  // ← 关键：白色延伸到底
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 30,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 30,
                style: .continuous
            )
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 22, x: 0, y: 10)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        bottomDockHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size.height) { h in
                        bottomDockHeight = h
                    }
            }
        )
    }

    private var calendarPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                if calendarDisplayMode == .month {
                    Button {
                        shiftVisibleMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(FigmaTheme.text)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    Text(monthTitle(for: visibleMonthAnchor))
                        .font(.system(size: 34 / 2, weight: .bold))
                        .foregroundColor(FigmaTheme.text)

                    Button {
                        shiftVisibleMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(FigmaTheme.text)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        calendarDisplayMode = calendarDisplayMode == .day ? .month : .day
                    }
                } label: {
                    Text(calendarDisplayMode == .day ? "Display by month" : "Display by day")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)

            if calendarDisplayMode == .day {
                dayModeCalendar
            } else {
                monthModeCalendar
            }
        }
    }

    private func bottomSheetOffset() -> CGFloat {
        let collapsedOffset = max(0, bottomDockHeight - AvatarMapMarkerStyle.collapsedSheetPeekHeight)
        return isSheetExpanded ? 0 : collapsedOffset
    }

    private var visibleBottomDockHeight: CGFloat {
        max(0, bottomDockHeight - bottomSheetOffset())
    }

    private func floatingBottomRightButtons(bottomInset: CGFloat) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    lifelogRecordToggle
                    recenterButton
                }
                .padding(.trailing, 16)
                .padding(.bottom, visibleBottomDockHeight + max(10, bottomInset + 6))
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var stepPopupToggleButton: some View {
        Button {
            if isStepPopupVisible {
                isStepPopupVisible = false
            } else {
                Task { await openStepPopup() }
            }
        } label: {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.80, blue: 0.74),
                            Color(red: 0.08, green: 0.63, blue: 0.57)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var currentHeadingDegrees: Double {
        let h = tracking.headingDegrees.truncatingRemainder(dividingBy: 360)
        return h >= 0 ? h : (h + 360)
    }

    private var renderLodLevel: Int {
        let span = max(
            visibleRegion?.span.latitudeDelta ?? 0.03,
            visibleRegion?.span.longitudeDelta ?? 0.03
        )
        switch span {
        case ..<0.015: return 3
        case ..<0.08: return 2
        case ..<0.35: return 1
        default: return 0
        }
    }

    private func shouldUpdateVisibleRegion(_ incoming: MKCoordinateRegion) -> Bool {
        guard let old = visibleRegion else { return true }
        let oldCenter = CLLocation(latitude: old.center.latitude, longitude: old.center.longitude)
        let newCenter = CLLocation(latitude: incoming.center.latitude, longitude: incoming.center.longitude)
        let centerMove = oldCenter.distance(from: newCenter)
        let oldSpan = max(old.span.latitudeDelta, old.span.longitudeDelta)
        let newSpan = max(incoming.span.latitudeDelta, incoming.span.longitudeDelta)
        let spanDelta = abs(newSpan - oldSpan)
        let spanRatio = spanDelta / max(oldSpan, 0.0001)
        return centerMove > 120 || spanRatio > 0.20
    }


    private var dayModeCalendar: some View {
        let days = recentSevenDays
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    Button {
                        handleDayTap(day)
                    } label: {
                        VStack(spacing: 4) {
                            Text(shortWeekday(day))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(FigmaTheme.text.opacity(0.44))
                            ZStack {
                                Circle()
                                    .fill(dayCellBackground(day: day, forMonthMode: false))
                                    .frame(width: 40, height: 40)
                                if let mood = lifelogStore.mood(for: day) {
                                    moodSymbolView(for: mood, imageSize: 26, fontSize: 20)
                                } else {
                                    Text("\(Calendar.current.component(.day, from: day))")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(isSelectedDay(day) ? .white : .black)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var monthModeCalendar: some View {
        let weekLabels = weekdayLabels
        let grid = monthGrid(for: visibleMonthAnchor)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(weekLabels, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.44))
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { idx in
                        let day = week[idx]
                        if let day {
                            Button {
                                handleDayTap(day)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(dayCellBackground(day: day, forMonthMode: true))
                                        .frame(height: 40)
                                    VStack(spacing: 1) {
                                        Text("\(Calendar.current.component(.day, from: day))")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(isSelectedDay(day) ? .white : .black)
                                        if let mood = lifelogStore.mood(for: day) {
                                            moodSymbolView(for: mood, imageSize: 22, fontSize: 18)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                        }
                    }
                }
            }
        }
    }

    private func centerOnCurrent(force: Bool) {
        if !force && !isViewingToday {
            return
        }

        if force, !isViewingToday, let center = centerCoordinateForSelectedDay() {
            position = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
            return
        }

        guard force || !didCenterOnEnter else { return }
        guard let current = currentCoordinateForCentering() else { return }
        didCenterOnEnter = true
        position = .region(MKCoordinateRegion(center: current, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
    }

    private func currentCoordinateForCentering() -> CLLocationCoordinate2D? {
        if let current = lifelogStore.currentLocation?.coordinate {
            return mapCoordForLifelog(current)
        }
        if let current = locationHub.currentLocation?.coordinate {
            return mapCoordForLifelog(current)
        }
        if let current = locationHub.lastKnownLocation?.coordinate {
            return mapCoordForLifelog(current)
        }
        return nil
    }

    private func captureCurrentPageImage() -> UIImage? {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: \.isKeyWindow)
        else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func normalizedDisplayName(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.t("explorer_fallback") : value
    }

    private func centerCoordinateForSelectedDay() -> CLLocationCoordinate2D? {
        renderSnapshot.selectedDayCenterCoordinate ?? currentCoordinateForCentering()
    }

    private func applyRenderSnapshotIfCurrent(_ snapshot: LifelogRenderSnapshot, generation: Int) {
        guard renderGenerationState.accepts(generation) else { return }
        debugRenderLog(
            "apply generation=\(generation) day=\(debugDayString(snapshot.selectedDay)) " +
            "far=\(snapshot.farRouteSegments.count) footprints=\(snapshot.footprintRuns.count) high=\(snapshot.isHighQuality)"
        )
        renderSnapshot = snapshot

        guard let pendingDay = pendingRecenterDay else { return }
        guard let snapshotDay = snapshot.selectedDay else { return }
        guard Calendar.current.isDate(snapshotDay, inSameDayAs: pendingDay) else { return }
        guard let center = snapshot.selectedDayCenterCoordinate else { return }

        position = .region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        )
        pendingRecenterDay = nil
    }

    private func scheduleRenderSnapshotRefresh(debounceNanoseconds: UInt64 = 0) {
        renderTask?.cancel()

        var generationState = renderGenerationState
        let generation = generationState.issue()
        renderGenerationState = generationState

        let targetDay = Calendar.current.startOfDay(for: selectedDay ?? Date())
        let viewport = TrackRenderAdapter.viewport(from: visibleRegion)
        let countryISO2 = lifelogCountryISO2
        debugRenderLog(
            "schedule generation=\(generation) day=\(debugDayString(targetDay)) " +
            "viewport=\(viewport != nil) country=\(countryISO2 ?? "nil")"
        )
        let isSwitchingDay: Bool = {
            guard let currentDay = renderSnapshot.selectedDay else { return true }
            return !Calendar.current.isDate(currentDay, inSameDayAs: targetDay)
        }()
        if let cached = lifelogRenderCache.cachedRenderSnapshot(
            day: targetDay,
            countryISO2: countryISO2,
            viewport: viewport
        ) {
            applyRenderSnapshotIfCurrent(cached, generation: generation)
        } else if isSwitchingDay {
            applyRenderSnapshotIfCurrent(
                LifelogRenderSnapshot(
                    selectedDay: targetDay,
                    cachedPathCoordsWGS84: [],
                    farRouteSegments: [],
                    footprintRuns: [],
                    selectedDayCenterCoordinate: nil,
                    isHighQuality: false
                ),
                generation: generation
            )
        }

        renderTask = Task(priority: .userInitiated) {
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }

            let snapshot = await lifelogRenderCache.ensureRenderSnapshot(
                day: targetDay,
                countryISO2: countryISO2,
                viewport: viewport
            )
            guard !Task.isCancelled else { return }
            guard let snapshot else {
                await MainActor.run {
                    debugRenderLog("ensure returned nil day=\(debugDayString(targetDay)) generation=\(generation)")
                }
                return
            }

            await MainActor.run {
                applyRenderSnapshotIfCurrent(snapshot, generation: generation)
            }
        }
    }

    private var lifelogCountryISO2: String? {
        lifelogStore.countryISO2 ?? locationHub.countryISO2
    }

    private func mapCoordForLifelog(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        MapCoordAdapter.forMapKit(coord, countryISO2: lifelogCountryISO2)
    }

    private func seedSelectedDayIfNeeded() {
        guard selectedDay == nil else { return }
        let today = Calendar.current.startOfDay(for: Date())
        selectedDay = today
    }

    private func isSelectedDay(_ day: Date) -> Bool {
        guard let selectedDay else { return false }
        return Calendar.current.isDate(day, inSameDayAs: selectedDay)
    }

    private func monthTitle(for day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: day)
    }

    private var recentSevenDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: offset - 6, to: today)
        }
    }

    private var weekdayLabels: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first]).map { String($0.prefix(3)) }
    }

    private func shortWeekday(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: day)
    }

    private func monthStart(for day: Date) -> Date {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: day)) ?? day
        return cal.startOfDay(for: start)
    }

    private func shiftVisibleMonth(by delta: Int) {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: delta, to: visibleMonthAnchor) else { return }
        visibleMonthAnchor = monthStart(for: next)
        if calendarDisplayMode == .day {
            calendarDisplayMode = .month
        }
    }

    private func monthGrid(for monthAnchor: Date) -> [[Date?]] {
        let cal = Calendar.current
        guard
            let monthInterval = cal.dateInterval(of: .month, for: monthAnchor),
            let daysRange = cal.range(of: .day, in: .month, for: monthAnchor)
        else { return [] }

        let firstDay = monthInterval.start
        let weekday = cal.component(.weekday, from: firstDay)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)

        for day in daysRange {
            if let date = cal.date(byAdding: .day, value: day - 1, to: firstDay) {
                cells.append(cal.startOfDay(for: date))
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<($0 + 7)])
        }
    }

    private func handleDayTap(_ day: Date) {
        let targetDay = Calendar.current.startOfDay(for: day)
        if isSelectedDay(targetDay) {
            moodPickerDay = targetDay
            isMoodPopupVisible = true
            return
        }
        selectedDay = targetDay
        visibleMonthAnchor = monthStart(for: targetDay)
        pendingRecenterDay = targetDay
    }

    private func dayCellBackground(day: Date, forMonthMode: Bool) -> Color {
        if isSelectedDay(day) {
            return FigmaTheme.primary
        }
        if lifelogStore.mood(for: day) != nil {
            return Color(red: 240 / 255.0, green: 249 / 255.0, blue: 244 / 255.0)
        }
        return forMonthMode ? .white : Color.white.opacity(0.92)
    }

    private struct MoodOption {
        let id: String
        let moodValue: String
        let imageAssetName: String
        let fallbackEmoji: String
        let labelKey: String
    }

    private static let moodOptions: [MoodOption] = [
        .init(id: "sad", moodValue: "sad", imageAssetName: "Sad", fallbackEmoji: "😢", labelKey: "lifelog_mood_option_sad"),
        .init(id: "notbad", moodValue: "notbad2", imageAssetName: "notbad2", fallbackEmoji: "🙂", labelKey: "lifelog_mood_option_notbad"),
        .init(id: "happy", moodValue: "happy", imageAssetName: "Happy", fallbackEmoji: "😄", labelKey: "lifelog_mood_option_happy")
    ]

    @ViewBuilder
    private func moodSymbolView(for mood: String, imageSize: CGFloat, fontSize: CGFloat) -> some View {
        if let option = moodOption(for: mood) {
            moodImageView(option: option, size: imageSize, fallbackFontSize: fontSize)
        } else {
            Text(mood)
                .font(.system(size: fontSize))
        }
    }

    private func moodOption(for mood: String) -> MoodOption? {
        switch mood {
        case "Happy", "mood/Happy", "happy", "mood/happy", "😄", "🤩":
            return Self.moodOptions.first { $0.id == "happy" }
        case "notbad2", "mood/notbad2", "notbad", "normal", "😐", "🙂":
            return Self.moodOptions.first { $0.id == "notbad" }
        case "Sad", "mood/Sad", "sad", "mood/sad", "😢", "😭":
            return Self.moodOptions.first { $0.id == "sad" }
        default:
            return nil
        }
    }

    @ViewBuilder
    private func moodImageView(option: MoodOption, size: CGFloat, fallbackFontSize: CGFloat) -> some View {
        if UIImage(named: option.imageAssetName) != nil {
            Image(option.imageAssetName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(option.fallbackEmoji)
                .font(.system(size: fallbackFontSize))
        }
    }

    @ViewBuilder
    private var moodPickerPopup: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 14) {
                Text(L10n.t("lifelog_mood_title"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(FigmaTheme.text)

                HStack(spacing: 12) {
                    ForEach(Self.moodOptions, id: \.id) { mood in
                        Button {
                            guard let day = moodPickerDay else { return }
                            lifelogStore.setMood(mood.moodValue, for: day)
                            moodPromptedDay = todayKey()
                            isMoodPopupVisible = false
                            moodPickerDay = nil
                        } label: {
                            VStack(spacing: 10) {
                                moodImageView(option: mood, size: 56, fallbackFontSize: 42)
                                Text(L10n.t(mood.labelKey))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(FigmaTheme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FigmaTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(FigmaTheme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Button(L10n.t("lifelog_clear_mood")) {
                        guard let day = moodPickerDay else { return }
                        lifelogStore.setMood(nil, for: day)
                        moodPromptedDay = todayKey()
                        isMoodPopupVisible = false
                        moodPickerDay = nil
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(FigmaTheme.subtext)

                    Spacer()

                    Button(L10n.t("lifelog_mood_later")) {
                        moodPromptedDay = todayKey()
                        isMoodPopupVisible = false
                        moodPickerDay = nil
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(FigmaTheme.primary)
                }
            }
            .padding(20)
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(FigmaTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
            .padding(.horizontal, 18)
        }
    }

    private var stepMilestoneModal: some View {
        ZStack {
            Color.black.opacity(0.36)
                .ignoresSafeArea()
                .onTapGesture {
                    if LifelogStepMilestonePresentation.supportsBackdropDismiss {
                        dismissStepModal()
                    }
                }

            VStack(alignment: .center, spacing: 16) {
                HStack {
                    Spacer()
                    if LifelogStepMilestonePresentation.closeButtonPlacement == .topTrailing {
                        Button {
                            dismissStepModal()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(FigmaTheme.subtext)
                                .frame(width: 30, height: 30)
                                .background(FigmaTheme.background)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [FigmaTheme.primary.opacity(0.2), FigmaTheme.primary.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(FigmaTheme.primary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    Text("🎉 太棒了！")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(FigmaTheme.primary)

                    Text(L10n.t("lifelog_steps_modal_title"))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(FigmaTheme.text)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

                Text(formattedStepCount(stepModalStepCount))
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(FigmaTheme.primary)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                Text("今天你在地球上又留下了 \(formattedStepCount(stepModalStepCount)) 步足迹")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(FigmaTheme.subtext)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if LifelogStepMilestonePresentation.showsFooterCloseButton {
                    Button(L10n.t("lifelog_steps_modal_close")) {
                        dismissStepModal()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(FigmaTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(FigmaTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 20, x: 0, y: 8)
            .padding(.horizontal, 20)
        }
        .transition(.opacity)
    }

    private var canShowStepSnapshot: Bool {
        hasHealthStepPermission && stepSnapshotValue(for: selectedDay ?? Date()) > 0
    }

    private var stepCompactBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 11, weight: .bold))
            Text(stepCompactText)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .contentTransition(.numericText())
        }
        .foregroundColor(Color(red: 0.10, green: 0.12, blue: 0.16))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.90))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 5, y: 2)
    }

    private var stepCompactText: String {
        if isRefreshingSteps { return "..." }
        if canShowStepSnapshot { return "\(stepSnapshotValue(for: selectedDay ?? Date()))" }
        return "--"
    }

    private func presentMoodPopupIfNeeded() {
        guard !isStepModalVisible else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard lifelogStore.mood(for: today) == nil else { return }
        guard moodPromptedDay != todayKey() else { return }
        moodPickerDay = today
        isMoodPopupVisible = true
    }

    private func refreshHealthPermissionState() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let status = HKHealthStore().authorizationStatus(for: stepType)
        // `authorizationStatus(for:)` is share-oriented; for read-only requests it can be misleading.
        // Treat "requested before" as available, and confirm by running a read query afterwards.
        hasHealthStepPermission = status != .notDetermined
    }

    private func openStepPopup() async {
        isStepPopupVisible = true
        isRefreshingSteps = true
        await refreshHealthPermissionState()
        await requestHealthPermissionIfNeeded()
        await refreshHealthPermissionState()
        await captureStepSnapshotIfNeeded(for: Calendar.current.startOfDay(for: selectedDay ?? Date()), force: true)
        isRefreshingSteps = false
    }

    private func requestHealthPermissionIfNeeded() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }
        let store = HKHealthStore()
        if store.authorizationStatus(for: stepType) != .notDetermined {
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [stepType])
            await refreshHealthPermissionState()
        } catch {
            await refreshHealthPermissionState()
        }
    }

    private func stepSnapshotValue(for day: Date) -> Int {
        let cache = LifelogStepSnapshotCache(rawValue: stepSnapshotByDayRaw)
        let key = dayKey(for: Calendar.current.startOfDay(for: day))
        return max(0, cache.value(forDayKey: key) ?? 0)
    }

    private func presentStepModalIfNeeded() async {
        let today = Calendar.current.startOfDay(for: Date())
        let todayKey = dayKey(for: today)
        let todaySteps = stepSnapshotValue(for: today)
        let decision = LifelogStepPopupTriggerPolicy.decide(
            todayKey: todayKey,
            todaySteps: todaySteps,
            lastPromptedDay: stepPopupPromptedDay,
            lastPromptedSteps: stepPopupPromptedValue
        )
        guard decision.shouldPresent else { return }
        stepPopupPromptedDay = decision.nextPromptedDay
        stepPopupPromptedValue = decision.nextPromptedSteps
        stepModalStepCount = todaySteps
        isStepModalVisible = true
    }

    private func dismissStepModal() {
        isStepModalVisible = false
        presentMoodPopupIfNeeded()
    }

    private func formattedStepCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: max(0, value))) ?? "\(max(0, value))"
    }

    private func migrateLegacyStepSnapshotIfNeeded() {
        guard !legacyStepSnapshotDay.isEmpty else { return }
        guard legacyStepSnapshotValue > 0 else { return }
        var cache = LifelogStepSnapshotCache(rawValue: stepSnapshotByDayRaw)
        if cache.value(forDayKey: legacyStepSnapshotDay) == nil {
            cache.setValue(max(0, legacyStepSnapshotValue), forDayKey: legacyStepSnapshotDay)
            stepSnapshotByDayRaw = cache.rawValue
        }
    }

    private func captureStepSnapshotIfNeeded(for day: Date, force: Bool = false) async {
        guard hasHealthStepPermission else { return }
        let dayStart = Calendar.current.startOfDay(for: day)
        let key = dayKey(for: dayStart)
        var cache = LifelogStepSnapshotCache(rawValue: stepSnapshotByDayRaw)
        if !force, cache.value(forDayKey: key) != nil {
            return
        }
        guard let count = try? await fetchStepCount(for: dayStart) else { return }
        cache.setValue(max(0, count), forDayKey: key)
        stepSnapshotByDayRaw = cache.rawValue
    }

    private func fetchStepCount(for day: Date) async throws -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        let end: Date
        if calendar.isDateInToday(startOfDay) {
            end = Date()
        } else {
            end = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: end,
            options: [.strictStartDate]
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: Int(value.rounded(.down)))
            }
            HKHealthStore().execute(query)
        }
    }

    private func todayKey() -> String {
        dayKey(for: Date())
    }

    private func dayKey(for day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: day)
    }

    private func debugRenderLog(_ message: String) {
#if DEBUG
        print("🗺️ [LifelogView] \(message)")
#endif
    }

    private func debugDayString(_ day: Date?) -> String {
        guard let day else { return "nil" }
        return dayKey(for: day)
    }

    private enum CalendarDisplayMode {
        case day
        case month
    }
}

struct LifelogStepSnapshotCache {
    private var byDay: [String: Int]

    init(rawValue: String) {
        if let data = rawValue.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            byDay = decoded
        } else {
            byDay = [:]
        }
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(byDay),
              let raw = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return raw
    }

    func value(forDayKey key: String) -> Int? {
        byDay[key]
    }

    mutating func setValue(_ value: Int, forDayKey key: String) {
        byDay[key] = max(0, value)
    }
}

struct LifelogStepPopupTriggerPolicy {
    static let deltaThreshold = 1_000

    struct Decision {
        let shouldPresent: Bool
        let nextPromptedDay: String
        let nextPromptedSteps: Int
    }

    static func decide(
        todayKey: String,
        todaySteps: Int,
        lastPromptedDay: String,
        lastPromptedSteps: Int
    ) -> Decision {
        let normalizedSteps = max(0, todaySteps)
        let normalizedPrompted = max(0, lastPromptedSteps)

        guard normalizedSteps > 0 else {
            return Decision(
                shouldPresent: false,
                nextPromptedDay: lastPromptedDay,
                nextPromptedSteps: normalizedPrompted
            )
        }

        if lastPromptedDay != todayKey {
            return Decision(
                shouldPresent: true,
                nextPromptedDay: todayKey,
                nextPromptedSteps: normalizedSteps
            )
        }

        if normalizedSteps - normalizedPrompted >= deltaThreshold {
            return Decision(
                shouldPresent: true,
                nextPromptedDay: todayKey,
                nextPromptedSteps: normalizedSteps
            )
        }

        return Decision(
            shouldPresent: false,
            nextPromptedDay: todayKey,
            nextPromptedSteps: normalizedPrompted
        )
    }
}

private struct FootstepGlyph: View {
    let isDark: Bool

    var body: some View {
        Image("foot")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(markerColor)
            .frame(width: 16)
            .shadow(color: markerColor.opacity(isDark ? 0.30 : 0.20), radius: isDark ? 3.2 : 1.6, x: 0, y: 0)
            .opacity(0.80)
            .scaleEffect(0.70)
            .shadow(color: .black.opacity(isDark ? 0.18 : 0.12), radius: 0.9, y: 0.5)
    }

    private var markerColor: Color {
        if isDark {
            // Night mode: green footprints.
            return Color(red: 86.0 / 255.0, green: 211.0 / 255.0, blue: 114.0 / 255.0)
        }
        // Day mode: orange footprints.
        return Color(red: 230.0 / 255.0, green: 125.0 / 255.0, blue: 49.0 / 255.0)
    }
}

// MARK: - Always Location Guide View

private struct AlwaysLocationGuideView: View {
    @Binding var isPresented: Bool
    let onEnable: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "location.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.white)

                VStack(spacing: 12) {
                    Text(L10n.t("lifelog_always_guide_title"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text(L10n.t("lifelog_always_guide_message"))
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        isPresented = false
                        onEnable()
                    } label: {
                        Text(L10n.t("lifelog_always_guide_enable"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        isPresented = false
                    } label: {
                        Text(L10n.t("lifelog_always_guide_skip"))
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }
}
