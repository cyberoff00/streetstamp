import SwiftUI
import MapKit
import UIKit

private struct LifelogShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct LifelogView: View {
    @ObservedObject private var tracking = TrackingService.shared
    @EnvironmentObject private var lifelogStore: LifelogStore
    @EnvironmentObject private var locationHub: LocationHub
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"
    @AppStorage(AppSettings.avatarHeadlightEnabledKey) private var avatarHeadlightEnabled = true

    @State private var position: MapCameraPosition = .automatic
    @State private var showGlobe = false
    @State private var globeJourneysSnapshot: [JourneyRoute] = []
    @State private var showEnableHint = false
    @State private var showDisableConfirm = false
    @State private var shareItem: LifelogShareImageItem? = nil
    @State private var didCenterOnEnter = false
    @State private var selectedDay: Date? = nil
    @State private var moodPickerDay: Date? = nil
    @State private var calendarDisplayMode: CalendarDisplayMode = .day
    @State private var visibleMonthAnchor: Date = Calendar.current.startOfDay(for: Date())
    @State private var isSheetExpanded = true
    @State private var sheetDragOffset: CGFloat = 0
    @State private var bottomDockHeight: CGFloat = 0
    @State private var visibleRegion: MKCoordinateRegion? = nil
    @State private var cameraRegion: MKCoordinateRegion? = nil
    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue

    private var mapAppearance: MapAppearanceStyle {
        MapAppearanceStyle(rawValue: mapAppearanceRaw) ?? .dark
    }
    private var isDarkAppearance: Bool { mapAppearance == .dark }
    private var panelBackground: Color { isDarkAppearance ? Color.black.opacity(0.80) : FigmaTheme.card.opacity(0.96) }
    private var panelText: Color { isDarkAppearance ? .white : .black }

    private var pathCoords: [CLLocationCoordinate2D] {
        let wgs = lifelogStore.mapPolylineViewport(
            day: selectedDay,
            region: visibleRegion,
            lodLevel: renderLodLevel,
            maxPoints: renderMaxPoints
        )
        return mapCoordsForLifelog(wgs)
    }

    private var footprintCoords: [CLLocationCoordinate2D] {
        let spaced = resampledFootprints(
            from: pathCoords,
            targetSpacingMeters: footprintStrideMeters
        )
        guard spaced.count > 2 else { return [] }
        let chain = Array(spaced.dropLast())
        return decimatedFootprintsForViewport(chain)
    }

    private var footprintRenderCoords: [CLLocationCoordinate2D] {
        guard let current = currentDisplayLocation?.coordinate else {
            return footprintCoords
        }
        let me = CLLocation(latitude: current.latitude, longitude: current.longitude)
        let threshold = avatarFootprintExclusionMeters
        return footprintCoords.filter { coord in
            let point = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            return point.distance(from: me) > threshold
        }
    }

    private var allJourneysForGlobe: [JourneyRoute] {
        lifelogStore.hasTrack ? [lifelogStore.syntheticJourney] : []
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Spacer()

                    bottomDock
                        .offset(y: bottomSheetOffset())
                        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: isSheetExpanded)
                        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.84), value: sheetDragOffset)
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    let dy = value.translation.height
                                    if isSheetExpanded {
                                        sheetDragOffset = max(0, dy)
                                    } else {
                                        sheetDragOffset = min(0, dy)
                                    }
                                }
                                .onEnded { value in
                                    let threshold: CGFloat = 72
                                    let dy = value.translation.height
                                    if isSheetExpanded, dy > threshold {
                                        isSheetExpanded = false
                                    } else if !isSheetExpanded, dy < -threshold {
                                        isSheetExpanded = true
                                    }
                                    sheetDragOffset = 0
                                }
                        )
                }

                floatingBottomRightButtons(bottomInset: proxy.safeAreaInsets.bottom + 24)
            }
        }
        .fullScreenCover(isPresented: $showGlobe) {
            GlobeViewScreen(showSidebar: .constant(false), externalJourneys: globeJourneysSnapshot)
                .environmentObject(store)
                .environmentObject(cityCache)
                .environmentObject(lifelogStore)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.image])
        }
        .alert(L10n.t("lifelog_disable_title"), isPresented: $showDisableConfirm) {
            Button(L10n.t("lifelog_continue_recording"), role: .cancel) {}
            Button(L10n.t("lifelog_confirm_disable"), role: .destructive) {
                lifelogStore.setEnabled(false)
            }
        } message: {
            Text(L10n.t("lifelog_disable_message"))
        }
        .confirmationDialog(
            L10n.t("lifelog_mood_title"),
            isPresented: Binding(
                get: { moodPickerDay != nil },
                set: { if !$0 { moodPickerDay = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(Self.moodOptions, id: \.id) { mood in
                Button("\(mood.placeholderEmoji) \(mood.label)") {
                    guard let day = moodPickerDay else { return }
                    lifelogStore.setMood(mood.moodValue, for: day)
                }
            }
            Button(L10n.t("lifelog_clear_mood"), role: .destructive) {
                guard let day = moodPickerDay else { return }
                lifelogStore.setMood(nil, for: day)
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        }
        .onAppear {
            didCenterOnEnter = false
            seedSelectedDayIfNeeded()
            visibleMonthAnchor = monthStart(for: selectedDay ?? Date())
            if locationHub.authorizationStatus != .authorizedAlways {
                showEnableHint = true
            }
            centerOnCurrent(force: true)
        }
        .onChange(of: lifelogStore.availableDays) { _ in seedSelectedDayIfNeeded() }
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
    }

    private var mapLayer: some View {
        Map(position: $position) {
            ForEach(footprintRenderCoords.indices, id: \.self) { idx in
                let style = footprintStyle(at: idx, in: footprintRenderCoords)
                Annotation("", coordinate: footprintRenderCoords[idx]) {
                    FootstepMarker(
                        opacity: style.opacity,
                        scale: style.scale,
                        angle: style.angle,
                        isDark: isDarkAppearance
                    )
                    .offset(x: style.lateralOffset)
                }
            }

            if let loc = currentDisplayLocation {
                Annotation("", coordinate: loc.coordinate) {
                    VStack(spacing: 2) {
                        if shouldShowMoodQuestionMark {
                            Button {
                                moodPickerDay = Calendar.current.startOfDay(for: Date())
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
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: shouldShowMoodQuestionMark)
                }
            }
        }
        .mapStyle(
            .standard(
                elevation: .flat,
                emphasis: .automatic,
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
                    globeJourneysSnapshot = allJourneysForGlobe
                    showGlobe = true
                } label: {
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(FigmaTheme.text)
                        .frame(width: 42, height: 42)
                        .background(FigmaTheme.card.opacity(0.92))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Text(L10n.t("lifelog_title"))
                .appHeaderStyle()
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
                    locationHub.requestPermissionIfNeeded()
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
        let totalJourneys = store.journeys.count
        let totalMemories = store.journeys.reduce(0) { $0 + $1.memories.count }
        let totalDistanceMeters = max(0, lifelogStore.totalDistanceMeters)
        let totalDistanceKm = totalDistanceMeters / 1000.0
        let distanceKmDisplay = max(0, Int(totalDistanceKm.rounded(.down)))
        let cityCount = cityCache.cachedCities.filter { !($0.isTemporary ?? false) }.count
        let levelProgress = UserLevelProgress.from(journeys: store.journeys)

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 200.0 / 255.0, green: 232.0 / 255.0, blue: 221.0 / 255.0))
                    .frame(width: 68, height: 68)

                RobotRendererView(size: 56, face: .front, loadout: AvatarLoadoutStore.load())
            }
            .overlay(alignment: .topTrailing) {
                LevelBadgeView(level: levelProgress.level)
                    .offset(x: 10, y: -10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(normalizedDisplayName(profileName))
                    .appBodyStrongStyle()
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(String(format: L10n.t("level_format"), levelProgress.level))
                    Text("·")
                    Text(String(format: L10n.t("level_remaining_short_format"), levelProgress.journeysRemainingToNextLevel))
                }
                    .appCaptionStyle()
                    .foregroundColor(FigmaTheme.text.opacity(0.62))
                    .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 6)
                        Capsule()
                            .fill(UITheme.accent)
                            .frame(width: max(8, proxy.size.width * levelProgress.progress), height: 6)
                    }
                }
                .frame(height: 6)

                Text(String(format: L10n.t("summary_stats_line"), cityCount, totalJourneys, totalMemories, distanceKmDisplay))
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
            if lifelogStore.isEnabled {
                showDisableConfirm = true
            } else {
                lifelogStore.setEnabled(true)
                if locationHub.authorizationStatus != .authorizedAlways {
                    showEnableHint = true
                    locationHub.requestPermissionIfNeeded()
                }
            }
        } label: {
            Circle()
                .fill(lifelogStore.isEnabled ? Color(red: 0.42, green: 0.78, blue: 0.58) : Color.gray.opacity(0.65))
                .frame(width: 12, height: 12)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.92))
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.10), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
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
                        sheetDragOffset = 0
                    }
                }

            bottomCard

            Divider()
                .overlay(Color.black.opacity(0.06))

            calendarPanel
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(Color.white.opacity(0.94))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 30,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 30,
                style: .continuous
            )
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
        VStack(spacing: 10) {
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

            if calendarDisplayMode == .day {
                dayModeCalendar
            } else {
                monthModeCalendar
            }
        }
    }

    private func bottomSheetOffset() -> CGFloat {
        let expandedBase = max(0, sheetDragOffset)
        let collapsedOffset = max(0, bottomDockHeight - AvatarMapMarkerStyle.collapsedSheetPeekHeight)
        let collapsedBase = max(0, collapsedOffset + sheetDragOffset)
        return isSheetExpanded ? expandedBase : collapsedBase
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

    private var renderMaxPoints: Int {
        switch renderLodLevel {
        case 3: return 420
        case 2: return 300
        case 1: return 220
        default: return 160
        }
    }

    private var footprintMaxMarkers: Int {
        switch renderLodLevel {
        case 3: return 140
        case 2: return 92
        case 1: return 56
        default: return 34
        }
    }

    private var footprintStrideMeters: CLLocationDistance {
        switch renderLodLevel {
        case 3: return 14
        case 2: return 24
        case 1: return 38
        default: return 60
        }
    }

    private var footprintGridCellRatio: Double {
        // Screen-space cell in normalized viewport units.
        // Larger cell on zoomed-out levels to avoid dense clusters.
        switch renderLodLevel {
        case 3: return 0.020
        case 2: return 0.036
        case 1: return 0.056
        default: return 0.090
        }
    }

    private var footprintGapBreakMeters: CLLocationDistance {
        // Break very long jumps so footprints don't form a fake straight "connection".
        switch renderLodLevel {
        case 3: return 180
        case 2: return 260
        case 1: return 380
        default: return 520
        }
    }

    private var avatarFootprintExclusionMeters: CLLocationDistance {
        switch renderLodLevel {
        case 3: return 26
        case 2: return 34
        case 1: return 44
        default: return 56
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

    private func resampledFootprints(
        from coords: [CLLocationCoordinate2D],
        targetSpacingMeters: CLLocationDistance
    ) -> [CLLocationCoordinate2D] {
        guard coords.count > 2 else { return coords }
        guard targetSpacingMeters > 0 else { return coords }

        var result: [CLLocationCoordinate2D] = [coords[0]]
        var distanceFromLastSample: CLLocationDistance = 0

        for i in 1..<coords.count {
            let segmentStart = coords[i - 1]
            let segmentEnd = coords[i]
            let startLoc = CLLocation(latitude: segmentStart.latitude, longitude: segmentStart.longitude)
            let endLoc = CLLocation(latitude: segmentEnd.latitude, longitude: segmentEnd.longitude)
            let segmentLength = endLoc.distance(from: startLoc)
            if segmentLength <= 0.001 { continue }
            if segmentLength > footprintGapBreakMeters {
                // Treat large gaps as a discontinuity: keep endpoint, but skip interpolation across the gap.
                if !sameCoordinate(result.last, segmentEnd) {
                    result.append(segmentEnd)
                }
                distanceFromLastSample = 0
                continue
            }

            var consumedOnSegment: CLLocationDistance = 0
            while distanceFromLastSample + (segmentLength - consumedOnSegment) >= targetSpacingMeters {
                let needed = targetSpacingMeters - distanceFromLastSample
                let t = (consumedOnSegment + needed) / segmentLength
                result.append(interpolateCoordinate(from: segmentStart, to: segmentEnd, t: t))
                consumedOnSegment += needed
                distanceFromLastSample = 0
            }

            distanceFromLastSample += max(0, segmentLength - consumedOnSegment)
        }

        if let last = coords.last, !sameCoordinate(result.last, last) {
            result.append(last)
        }
        return result
    }

    private func interpolateCoordinate(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D,
        t: Double
    ) -> CLLocationCoordinate2D {
        let clamped = min(max(t, 0), 1)
        let lat = a.latitude + (b.latitude - a.latitude) * clamped
        let lon = a.longitude + (b.longitude - a.longitude) * clamped
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func sameCoordinate(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D) -> Bool {
        guard let a else { return false }
        return abs(a.latitude - b.latitude) < 0.000_000_1 && abs(a.longitude - b.longitude) < 0.000_000_1
    }

    private func decimatedFootprintsForViewport(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coords.count > 3 else { return coords }
        guard let region = cameraRegion ?? visibleRegion else {
            return uniformSampledCoords(coords, maxPoints: footprintMaxMarkers)
        }
        let maxMarkers = max(2, min(footprintMaxMarkers, coords.count))
        // Full-path uniform anchors (no recent-point compensation).
        let reserveAnchors = maxMarkers
        let cell = max(0.010, footprintGridCellRatio)

        var selected = Set<Int>()
        selected.insert(0)
        selected.insert(coords.count - 1)

        if reserveAnchors > 1 {
            for i in 0..<reserveAnchors {
                let t = Double(i) / Double(max(reserveAnchors - 1, 1))
                let idx = Int((t * Double(coords.count - 1)).rounded(.toNearestOrAwayFromZero))
                selected.insert(min(max(idx, 0), coords.count - 1))
            }
        }

        func cellKey(for index: Int) -> String? {
            guard let p = normalizedViewportPoint(coords[index], in: region) else { return nil }
            guard p.x >= -0.2, p.x <= 1.2, p.y >= -0.2, p.y <= 1.2 else { return nil }
            let cx = Int(floor(p.x / cell))
            let cy = Int(floor(p.y / cell))
            return "\(cx)|\(cy)"
        }

        var occupied = Set<String>()
        for idx in selected {
            if let key = cellKey(for: idx) {
                occupied.insert(key)
            }
        }

        if selected.count < maxMarkers {
            for idx in 0..<coords.count {
                if selected.contains(idx) { continue }
                guard let key = cellKey(for: idx) else { continue }
                if occupied.contains(key) { continue }
                selected.insert(idx)
                occupied.insert(key)
                if selected.count >= maxMarkers { break }
            }
        }

        if selected.count < maxMarkers {
            for idx in stride(from: coords.count - 1, through: 0, by: -1) {
                if selected.contains(idx) { continue }
                guard let key = cellKey(for: idx) else { continue }
                if occupied.contains(key) { continue }
                selected.insert(idx)
                occupied.insert(key)
                if selected.count >= maxMarkers { break }
            }
        }

        if selected.count < maxMarkers {
            for idx in 0..<coords.count {
                if selected.contains(idx) { continue }
                selected.insert(idx)
                if selected.count >= maxMarkers { break }
            }
        }

        return selected
            .sorted()
            .map { coords[$0] }
    }

    private func uniformSampledCoords(_ coords: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard maxPoints >= 2 else { return coords }
        guard coords.count > maxPoints else { return coords }
        let n = coords.count
        return (0..<maxPoints).map { i in
            let t = Double(i) / Double(maxPoints - 1)
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            return coords[min(max(idx, 0), n - 1)]
        }
    }

    private func footprintStyle(
        at index: Int,
        in coords: [CLLocationCoordinate2D]
    ) -> (opacity: Double, scale: CGFloat, angle: Double, lateralOffset: CGFloat) {
        let opacity = 0.80
        let scale = CGFloat(0.90)
        let heading = footprintHeadingDegrees(at: index, in: coords)

        return (
            opacity: opacity,
            scale: scale,
            angle: heading,
            lateralOffset: 0
        )
    }

    private func footprintHeadingDegrees(at index: Int, in coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 2 else { return -18 }
        let from: CLLocationCoordinate2D
        let to: CLLocationCoordinate2D
        if index <= 0 {
            from = coords[0]
            to = coords[1]
        } else {
            from = coords[min(index - 1, coords.count - 1)]
            to = coords[min(index, coords.count - 1)]
        }
        return bearingDegrees(from: from, to: to)
    }

    private func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let raw = atan2(y, x) * 180 / .pi
        if raw.isFinite {
            return raw
        }
        return -18
    }

    private func normalizedViewportPoint(
        _ coord: CLLocationCoordinate2D,
        in region: MKCoordinateRegion
    ) -> CGPoint? {
        let latDelta = max(region.span.latitudeDelta, 0.000_001)
        let lonDelta = max(region.span.longitudeDelta, 0.000_001)
        let minLon = region.center.longitude - lonDelta / 2.0
        let maxLat = region.center.latitude + latDelta / 2.0

        let xRatio = (coord.longitude - minLon) / lonDelta
        let yRatio = (maxLat - coord.latitude) / latDelta
        guard xRatio.isFinite, yRatio.isFinite else { return nil }
        return CGPoint(x: xRatio, y: yRatio)
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
                                    Text(mood)
                                        .font(.system(size: 18))
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
                                            Text(mood)
                                                .font(.system(size: 16))
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
        if let last = pathCoords.last {
            return last
        }
        return currentCoordinateForCentering()
    }

    private func centerCoordinate(for day: Date) -> CLLocationCoordinate2D? {
        let coords = mapCoordsForLifelog(lifelogStore.mapPolyline(day: day, maxPoints: 900))
        return coords.last ?? currentCoordinateForCentering()
    }

    private var lifelogCountryISO2: String? {
        lifelogStore.countryISO2 ?? locationHub.countryISO2
    }

    private func mapCoordForLifelog(_ coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        MapCoordAdapter.forMapKit(coord, countryISO2: lifelogCountryISO2)
    }

    private func mapCoordsForLifelog(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        MapCoordAdapter.forMapKit(coords, countryISO2: lifelogCountryISO2)
    }

    private func recenter(for day: Date) {
        let regionCenter = centerCoordinate(for: day)
        guard let center = regionCenter else { return }
        position = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
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
            return
        }
        selectedDay = targetDay
        visibleMonthAnchor = monthStart(for: targetDay)
        recenter(for: targetDay)
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
        let placeholderEmoji: String
        let label: String
    }

    private static let moodOptions: [MoodOption] = [
        .init(id: "sad", moodValue: "😢", placeholderEmoji: "😢", label: "Sad"),
        .init(id: "normal", moodValue: "😐", placeholderEmoji: "😐", label: "Normal"),
        .init(id: "happy", moodValue: "😄", placeholderEmoji: "😄", label: "Happy")
    ]

    private enum CalendarDisplayMode {
        case day
        case month
    }
}

private struct FootstepMarker: View {
    let opacity: Double
    let scale: CGFloat
    let angle: Double
    let isDark: Bool

    var body: some View {
        Image(systemName: "shoeprints.fill")
            .font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(markerColor)
            .frame(width: 22, height: 28)
            .opacity(opacity)
            .shadow(color: markerColor.opacity(isDark ? 0.30 : 0.20), radius: isDark ? 3.2 : 1.6, x: 0, y: 0)
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
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
