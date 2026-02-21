import SwiftUI
import MapKit
import UIKit

private struct LifelogShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct LifelogView: View {
    @Binding var showSidebar: Bool

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
    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue

    private var mapAppearance: MapAppearanceStyle {
        MapAppearanceStyle(rawValue: mapAppearanceRaw) ?? .dark
    }
    private var isDarkAppearance: Bool { mapAppearance == .dark }
    private var panelBackground: Color { isDarkAppearance ? Color.black.opacity(0.80) : FigmaTheme.card.opacity(0.96) }
    private var panelText: Color { isDarkAppearance ? .white : .black }

    private var pathCoords: [CLLocationCoordinate2D] {
        lifelogStore.mapPolylineViewport(
            day: selectedDay,
            region: visibleRegion,
            lodLevel: renderLodLevel,
            maxPoints: renderMaxPoints
        )
    }

    private var fogRevealCoords: [CLLocationCoordinate2D] {
        sampledPath(from: pathCoords, maxPoints: 70)
    }

    private var footprintCoords: [CLLocationCoordinate2D] {
        let sampled = sampledPath(from: pathCoords, maxPoints: 180)
        guard sampled.count > 3 else { return [] }
        return Array(sampled.dropLast().suffix(28))
    }

    private var allJourneysForGlobe: [JourneyRoute] {
        lifelogStore.hasTrack ? [lifelogStore.syntheticJourney] : []
    }

    private var currentDisplayLocation: CLLocation? {
        if let loc = lifelogStore.currentLocation { return loc }
        if let loc = locationHub.currentLocation { return loc }
        return locationHub.lastKnownLocation
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

                    bottomDock(bottomInset: proxy.safeAreaInsets.bottom)
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
                .ignoresSafeArea(edges: .bottom)

                floatingBottomRightButtons(bottomInset: proxy.safeAreaInsets.bottom)
            }
        }
        .preferredColorScheme(isDarkAppearance ? .dark : .light)
        .fullScreenCover(isPresented: $showGlobe) {
            GlobeViewScreen(showSidebar: .constant(false), externalJourneys: globeJourneysSnapshot)
                .environmentObject(store)
                .environmentObject(cityCache)
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
                Button("\(mood.emoji) \(mood.label)") {
                    guard let day = moodPickerDay else { return }
                    lifelogStore.setMood(mood.emoji, for: day)
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
            ForEach(fogRevealCoords.indices, id: \.self) { idx in
                MapCircle(center: fogRevealCoords[idx], radius: 220)
                    .foregroundStyle(Color.white.opacity(isDarkAppearance ? 0.04 : 0.08))
            }

            if pathCoords.count >= 2 {
                MapPolyline(coordinates: pathCoords)
                    .stroke(Color(red: 0.05, green: 0.67, blue: 0.54), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            ForEach(footprintCoords.indices, id: \.self) { idx in
                let alpha = 0.20 + (Double(idx) / Double(max(footprintCoords.count - 1, 1))) * 0.58
                Annotation("", coordinate: footprintCoords[idx]) {
                    FootstepMarker(opacity: alpha)
                }
            }

            if let loc = currentDisplayLocation {
                Annotation("", coordinate: loc.coordinate) {
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
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .overlay {
            LinearGradient(
                colors: [
                    Color.black.opacity(isDarkAppearance ? 0.24 : 0.08),
                    Color.clear,
                    Color.black.opacity(isDarkAppearance ? 0.20 : 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .onMapCameraChange { context in
            let incoming = context.region
            if shouldUpdateVisibleRegion(incoming) {
                visibleRegion = incoming
            }
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                SidebarHamburgerButton(showSidebar: $showSidebar, size: 42, iconSize: 20, iconWeight: .semibold, foreground: .black)
                    .background(Color.white.opacity(isDarkAppearance ? 0.92 : 0.88))
                    .clipShape(Circle())

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
            }

            Text(L10n.t("lifelog_title"))
                .appHeaderStyle()
        }
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
                .font(.system(size: 12, weight: .bold))
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
        let totalEP = max(0, Int(totalDistanceKm.rounded(.down)))

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 200.0 / 255.0, green: 232.0 / 255.0, blue: 221.0 / 255.0))
                    .frame(width: 68, height: 68)

                RobotRendererView(size: 56, face: .front, loadout: AvatarLoadoutStore.load())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(normalizedDisplayName(profileName))
                    .appBodyStrongStyle()
                    .foregroundColor(.black)
                    .lineLimit(1)

                Text(String(format: L10n.t("level_ep_format"), totalEP))
                    .appCaptionStyle()
                    .foregroundColor(.black.opacity(0.62))
                    .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 6)
                        Capsule()
                            .fill(UITheme.accent)
                            .frame(width: max(8, proxy.size.width * 0.45), height: 6)
                    }
                }
                .frame(height: 6)

                Text(String(format: L10n.t("summary_stats_line"), cityCount, totalJourneys, totalMemories, distanceKmDisplay))
                    .appFootnoteStyle()
                    .foregroundColor(.black.opacity(0.56))
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

    private func bottomDock(bottomInset: CGFloat) -> some View {
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
        .padding(.bottom, max(20, bottomInset + 12))
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
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.black)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    Text(monthTitle(for: visibleMonthAnchor))
                        .font(.system(size: 34 / 2, weight: .black))
                        .foregroundColor(.black)

                    Button {
                        shiftVisibleMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.black)
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
                        .font(.system(size: 12, weight: .bold))
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

    private func sampledPath(from src: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard maxPoints >= 2 else { return src }
        guard src.count > maxPoints else { return src }
        let n = src.count
        return (0..<maxPoints).map { i in
            let t = Double(i) / Double(maxPoints - 1)
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            return src[min(max(idx, 0), n - 1)]
        }
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
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color.black.opacity(0.44))
                            ZStack {
                                Circle()
                                    .fill(dayCellBackground(day: day, forMonthMode: false))
                                    .frame(width: 40, height: 40)
                                if let mood = lifelogStore.mood(for: day) {
                                    Text(mood)
                                        .font(.system(size: 18))
                                } else {
                                    Text("\(Calendar.current.component(.day, from: day))")
                                        .font(.system(size: 16, weight: .black))
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
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.black.opacity(0.44))
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
                                            .font(.system(size: 12, weight: .black))
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
            return current
        }
        if let current = locationHub.currentLocation?.coordinate {
            return current
        }
        return locationHub.lastKnownLocation?.coordinate
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
        let coords = lifelogStore.mapPolyline(day: day, maxPoints: 900)
        return coords.last ?? currentCoordinateForCentering()
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
        let emoji: String
        let label: String
    }

    private static let moodOptions: [MoodOption] = [
        .init(id: "happy", emoji: "😊", label: "Happy"),
        .init(id: "calm", emoji: "🙂", label: "Calm"),
        .init(id: "tired", emoji: "😮‍💨", label: "Tired"),
        .init(id: "sad", emoji: "😢", label: "Sad"),
        .init(id: "angry", emoji: "😤", label: "Angry"),
        .init(id: "excited", emoji: "🤩", label: "Excited")
    ]

    private enum CalendarDisplayMode {
        case day
        case month
    }
}

private struct FootstepMarker: View {
    let opacity: Double

    var body: some View {
        HStack(spacing: 1) {
            Circle()
                .fill(Color(red: 0.98, green: 0.95, blue: 0.80).opacity(opacity))
                .frame(width: 4.5, height: 4.5)
            Circle()
                .fill(Color(red: 0.98, green: 0.95, blue: 0.80).opacity(opacity * 0.9))
                .frame(width: 3.8, height: 3.8)
        }
        .rotationEffect(.degrees(-18))
        .shadow(color: .black.opacity(0.12), radius: 1.2, y: 0.8)
    }
}
