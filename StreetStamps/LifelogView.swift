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
    static let showsCelebrationHeadline = false
    static let contentSpacing: CGFloat = 14
    static let heroIconDiameter: CGFloat = 60
    static let heroIconSize: CGFloat = 24
    static let topPadding: CGFloat = 14
    static let horizontalPadding: CGFloat = 22
}


private struct LifelogShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum LifelogRenderRefreshPolicy {
    static func placeholderSnapshot(
        currentSnapshot: LifelogRenderSnapshot,
        targetDay: Date,
        cachedSnapshot: LifelogRenderSnapshot?
    ) -> LifelogRenderSnapshot {
        if let cachedSnapshot {
            return cachedSnapshot
        }

        // Only reuse the current snapshot if it belongs to the same day.
        // Reusing a different day's routes causes stale route bleed.
        if hasVisibleContent(currentSnapshot),
           let snapshotDay = currentSnapshot.selectedDay,
           Calendar.current.isDate(snapshotDay, inSameDayAs: targetDay) {
            return currentSnapshot
        }

        return LifelogRenderSnapshot(
            selectedDay: targetDay,
            cachedPathCoordsWGS84: [],
            farRouteSegments: [],
            selectedDayCenterCoordinate: nil,
            isHighQuality: false
        )
    }

    private static func hasVisibleContent(_ snapshot: LifelogRenderSnapshot) -> Bool {
        !snapshot.cachedPathCoordsWGS84.isEmpty ||
        !snapshot.farRouteSegments.isEmpty ||
        snapshot.selectedDayCenterCoordinate != nil
    }
}

private struct LifelogBottomCardView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache

    let profileName: String
    let onOpenEquipment: () -> Void
    let onShare: () -> Void

    var body: some View {
        let totalMemories = store.journeys.reduce(0) { $0 + $1.memories.count }
        let cityCount = cityCache.cachedCities.filter { !($0.isTemporary ?? false) }.count
        let levelProgress = UserLevelProgress.from(journeys: store.journeys)
        let cardContent = ProfileSummaryCardContent(
            level: levelProgress.level,
            cityCount: cityCount,
            memoryCount: totalMemories,
            locale: LanguagePreference.shared.displayLocale
        )

        HStack(spacing: 14) {
            Button(action: onOpenEquipment) {
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
                Text(LifelogView.normalizedDisplayName(profileName))
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

            Button(action: onShare) {
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
}

private struct LifelogGlobeCoverView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var lifelogStore: LifelogStore
    @EnvironmentObject private var trackTileStore: TrackTileStore

    var body: some View {
        GlobeViewScreen()
            .environmentObject(store)
            .environmentObject(cityCache)
            .environmentObject(lifelogStore)
            .environmentObject(trackTileStore)
    }
}

struct LifelogCameraCommand {
    let id: UUID
    let region: MKCoordinateRegion
}

struct LifelogView: View {
    @ObservedObject private var weatherService = WeatherService.shared
    @EnvironmentObject private var lifelogStore: LifelogStore
    @EnvironmentObject private var trackTileStore: TrackTileStore
    @EnvironmentObject private var locationHub: LocationHub
    @EnvironmentObject private var lifelogRenderCache: LifelogRenderCacheCoordinator
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"
    @State private var cameraCommand: LifelogCameraCommand? = nil
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
    @State private var renderSnapshot: LifelogRenderSnapshot = .empty
    @State private var renderTask: Task<Void, Never>? = nil
    @State private var mapContentReady = false
    @State private var renderGenerationState = LifelogRenderGenerationState()
    @State private var pendingRecenterDay: Date? = nil
    /// Set to true after the first route-fit on enter, so we don't re-fit
    /// on every incremental snapshot update while the user is panning.
    @State private var didAutoFitToRoute = false
    @AppStorage(MapLayerStyle.storageKey) private var layerStyleRaw = MapLayerStyle.current.rawValue
    @AppStorage("streetstamps.lifelog.health.steps.snapshot.byday") private var stepSnapshotByDayRaw = ""
    @AppStorage("streetstamps.lifelog.health.steps.snapshot.day") private var legacyStepSnapshotDay = ""
    @AppStorage("streetstamps.lifelog.health.steps.snapshot.value") private var legacyStepSnapshotValue = 0
    @AppStorage("streetstamps.lifelog.steps.popup.prompted.day") private var stepPopupPromptedDay = ""
    @AppStorage("streetstamps.lifelog.steps.popup.prompted.value") private var stepPopupPromptedValue = 0
    @AppStorage("streetstamps.lifelog.steps.badge.prompted.day") private var stepBadgePromptedDay = ""
    @AppStorage("streetstamps.lifelog.mood.prompted.day") private var moodPromptedDay = ""
    @State private var activeLifelogHint: LifelogHintItem? = nil
    @State private var lifelogHintTask: Task<Void, Never>? = nil
#if DEBUG
    @AppStorage("streetstamps.debug.lifelog.mapDiagnosticsEnabled") private var mapDiagnosticsEnabled = true
    @State private var diagnosticsAppearAt: Date? = nil
#endif

    private var isDarkAppearance: Bool {
        (MapLayerStyle(rawValue: layerStyleRaw) ?? .mutedDark).isDarkStyle
    }
    private var panelBackground: Color { isDarkAppearance ? Color.black.opacity(0.80) : FigmaTheme.card.opacity(0.96) }
    private var panelText: Color { isDarkAppearance ? .white : .black }

    private var locationCenterKey: Int {
        guard let loc = locationHub.currentLocation else { return 0 }
        var h = Hasher()
        h.combine(Int(loc.coordinate.latitude * 10000))
        h.combine(Int(loc.coordinate.longitude * 10000))
        return h.finalize()
    }

    private var tileRevisionKey: Int {
        lifelogStore.trackTileRevision &+ trackTileStore.refreshRevision
    }

    private var farRouteSegments: [RenderRouteSegment] {
        renderSnapshot.farRouteSegments
    }

#if DEBUG
    private var diagnosticsOverlayReady: Bool {
        mapContentReady &&
        (
            !renderSnapshot.farRouteSegments.isEmpty ||
            renderSnapshot.selectedDayCenterCoordinate != nil ||
            currentDisplayLocation != nil
        )
    }

    private var diagnosticsStatusPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OVERLAY \(diagnosticsOverlayReady ? "READY" : "WAIT")")
            Text("OVERLAY \(diagnosticsOverlayReady ? "READY" : "WAIT")")
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func diagnosticsLog(_ message: String) {
        guard mapDiagnosticsEnabled else { return }
        print("[LifelogMapDiag] \(message)")
    }

    private func diagnosticsUpdateIfNeeded(reason: String = "") {
        guard mapDiagnosticsEnabled else { return }
        let elapsedMs = diagnosticsAppearAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        diagnosticsLog(
            "\(reason) t=\(elapsedMs)ms " +
            "mapContentReady=\(mapContentReady) " +
            "overlayReady=\(diagnosticsOverlayReady)"
        )
    }
#endif


    private var currentDisplayLocation: CLLocation? {
        let source: CLLocation? = locationHub.currentLocation ?? locationHub.lastKnownLocation
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

                WeatherOverlayView(
                    weatherService: weatherService,
                    location: locationHub.currentLocation
                )
#if DEBUG
                if mapDiagnosticsEnabled {
                    VStack {
                        HStack {
                            Spacer()
                            diagnosticsStatusPanel
                        }
                        .padding(.top, 92)
                        .padding(.trailing, 12)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
#endif

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
                                        .transition(.move(edge: .top).combined(with: .opacity))
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
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .center)))
                }
                if isStepModalVisible {
                    stepMilestoneModal
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: isMoodPopupVisible)
        .fullScreenCover(isPresented: $showGlobe) {
            LifelogGlobeCoverView()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.image])
        }
        .sheet(isPresented: $showAlwaysLocationGuide) {
            AlwaysLocationGuideView(isPresented: $showAlwaysLocationGuide, onEnable: {
                alwaysLocationGuideShown = true
                locationHub.requestAlwaysPermissionIfNeeded()
            }, onSkip: {
                alwaysLocationGuideShown = true
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
        .overlay(alignment: .bottom) {
            if let hint = activeLifelogHint {
                ContextualHintBar(
                    icon: hint.icon,
                    message: hint.message,
                    onDismiss: { dismissLifelogHintSequence() }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(hint.id)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: activeLifelogHint?.id)
        .onAppear {
            startLifelogHintSequence()
#if DEBUG
            if mapDiagnosticsEnabled {
                diagnosticsAppearAt = Date()
                diagnosticsLog(
                    "onAppear " +
                    "locationHub=\(locationHub.currentLocation != nil) " +
                    "lastKnown=\(locationHub.lastKnownLocation != nil) " +
                    "lifelogLocation=\(lifelogStore.currentLocation != nil)"
                )
                diagnosticsUpdateIfNeeded(reason: "appear")
            }
#endif
            didCenterOnEnter = false
            didAutoFitToRoute = false
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
            if !mapContentReady {
                // If a disk-cached snapshot exists, skip the 150ms defer —
                // the cached data is light enough to render immediately.
                let hasDiskCache = lifelogRenderCache.cachedRenderSnapshot(
                    day: selectedDay ?? Date(),
                    countryISO2: lifelogCountryISO2,
                    viewport: nil
                ) != nil
                if hasDiskCache {
                    mapContentReady = true
                    scheduleRenderSnapshotRefresh()
                } else {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        mapContentReady = true
                        scheduleRenderSnapshotRefresh()
                    }
                }
            } else {
                scheduleRenderSnapshotRefresh()
            }
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
        .onChange(of: locationCenterKey) { _ in
            centerOnCurrent(force: !didCenterOnEnter)
#if DEBUG
            diagnosticsUpdateIfNeeded(reason: "locationCenterKey")
#endif
        }
        .onChange(of: tileRevisionKey) { _ in
            scheduleRenderSnapshotRefresh(debounceNanoseconds: 400_000_000)
        }
        .onChange(of: lifelogCountryISO2) { _ in
            scheduleRenderSnapshotRefresh()
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

    private var lifelogMapSegments: [MapRouteSegment] {
        guard mapContentReady else { return [] }
        let engine = (MapLayerStyle(rawValue: layerStyleRaw) ?? .mutedDark).engine
        let needsGCJ = engine == .mapkit
        let countryISO2 = lifelogCountryISO2
        return farRouteSegments.enumerated().map { (i, seg) in
            let coords = needsGCJ
                ? MapCoordAdapter.forMapKit(seg.coords, countryISO2: countryISO2)
                : seg.coords
            return MapRouteSegment(id: "ll-\(i)", coordinates: coords, isGap: seg.style == .dashed, repeatWeight: 0)
        }
    }

    private var lifelogMapAnnotations: [MapAnnotationItem] {
        guard let coord = currentDisplayLocation?.coordinate else { return [] }
        return [MapAnnotationItem(id: "lifelog-avatar", coordinate: coord, kind: .lifelogAvatar(showMoodQuestion: shouldShowMoodQuestionMark))]
    }

    @State private var unifiedCameraCommand: MapCameraCommand? = nil

    private var mapLayer: some View {
        UnifiedMapView(
            segments: lifelogMapSegments,
            annotations: lifelogMapAnnotations,
            cameraCommand: unifiedCameraCommand,
            config: .lifelog(),
            callbacks: MapCallbacks(
                onAvatarDoubleTap: { openEquipmentView() },
                onMoodTap: {
                    moodPickerDay = Calendar.current.startOfDay(for: Date())
                    isMoodPopupVisible = true
                }
            )
        )
        .ignoresSafeArea()
        .onChange(of: cameraCommand?.id) { _ in
            if let cmd = cameraCommand {
                unifiedCameraCommand = .setRegion(cmd.region)
            }
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                weatherBadge

                Spacer()

                Button {
                    showGlobe = true
                } label: {
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(FigmaTheme.text)
                        .appMinTapTarget()
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

    private var weatherBadge: some View {
        let condition = weatherService.effectiveCondition
        let weather = weatherService.effectiveWeather

        return HStack(spacing: 4) {
            Image(systemName: condition.sfSymbol)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(weatherIconColor(for: condition))

            if let temp = weather?.temperature {
                Text("\(Int(temp.rounded()))\u{00B0}")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(FigmaTheme.text.opacity(0.8))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .frame(height: 42)
        .opacity(weather != nil ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: weather != nil)
    }

    private func weatherIconColor(for condition: WeatherCondition) -> Color {
        switch condition {
        case .clear:        return .orange
        case .cloudy:       return .gray
        case .drizzle:      return .cyan
        case .rain:         return .blue
        case .heavyRain:    return .blue
        case .thunderstorm: return .purple
        case .snow:         return .mint
        case .fog:          return .gray
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
                .appMinTapTarget()
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
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var bottomCard: some View {
        LifelogBottomCardView(
            profileName: profileName,
            onOpenEquipment: { flow.requestModalPush(.equipment) },
            onShare: {
                if let image = captureCurrentPageImage() {
                    shareItem = LifelogShareImageItem(image: image)
                }
            }
        )
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
        case .notDetermined:
            locationHub.requestAlwaysPermissionIfNeeded()
        case .authorizedWhenInUse, .denied, .restricted:
            openAppSettings()
        @unknown default:
            openAppSettings()
        }
    }

    private struct LifelogHintItem: Equatable {
        let id: String
        let icon: String
        let message: String
    }

    private static let lifelogHintSequence: [LifelogHintItem] = [
        LifelogHintItem(id: "weather", icon: "cloud.sun", message: L10n.t("tour_lifelog_weather")),
        LifelogHintItem(id: "globe", icon: "globe", message: L10n.t("tour_lifelog_globe")),
        LifelogHintItem(id: "calendar", icon: "calendar", message: L10n.t("tooltip_lifelog_calendar")),
    ]

    private var hasActivePopup: Bool {
        showAlwaysLocationGuide || isMoodPopupVisible || isStepPopupVisible || isStepModalVisible || showPermissionSettingsPrompt || showDisableConfirm
    }

    private func startLifelogHintSequence() {
        guard onboardingGuide.shouldShowHint(.lifelogTour) else { return }
        lifelogHintTask?.cancel()
        lifelogHintTask = Task { @MainActor in
            // Wait until all competing popups are dismissed
            while hasActivePopup {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, !hasActivePopup else { return }
            for hint in Self.lifelogHintSequence {
                guard !Task.isCancelled else { return }
                if hasActivePopup { return }
                activeLifelogHint = hint
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
            guard !Task.isCancelled else { return }
            activeLifelogHint = nil
            onboardingGuide.dismissHint(.lifelogTour)
        }
    }

    private func dismissLifelogHintSequence() {
        lifelogHintTask?.cancel()
        activeLifelogHint = nil
        onboardingGuide.dismissHint(.lifelogTour)
    }

    private func openEquipmentView() {
        flow.requestModalPush(.equipment)
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
                            .appMinTapTarget()
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
                            .appMinTapTarget()
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
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
                .appMinTapTarget()
        }
        .buttonStyle(.plain)
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

        if force, !isViewingToday {
            // Use route bounding box if the snapshot for this day is already loaded.
            let snapshotMatchesDay = renderSnapshot.selectedDay.map {
                Calendar.current.isDate($0, inSameDayAs: selectedDay ?? Date())
            } == true
            if snapshotMatchesDay, let region = regionFittingRoute(renderSnapshot.farRouteSegments) {
                cameraCommand = LifelogCameraCommand(id: UUID(), region: region)
            } else if let center = centerCoordinateForSelectedDay() {
                cameraCommand = LifelogCameraCommand(id: UUID(), region: MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
            }
            return
        }

        guard force || !didCenterOnEnter else { return }
        guard let current = currentCoordinateForCentering() else { return }
        didCenterOnEnter = true
        cameraCommand = LifelogCameraCommand(id: UUID(), region: MKCoordinateRegion(center: current, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
    }

    private func currentCoordinateForCentering() -> CLLocationCoordinate2D? {
        currentDisplayLocation?.coordinate
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

    static func normalizedDisplayName(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.t("explorer_fallback") : value
    }

    private func centerCoordinateForSelectedDay() -> CLLocationCoordinate2D? {
        if let wgs = renderSnapshot.selectedDayCenterCoordinate {
            return mapCoordForLifelog(wgs)
        }
        return currentCoordinateForCentering()
    }

    /// Returns the tightest MKCoordinateRegion that fits all coordinates in `segments`,
    /// with `padding` as a fractional expansion on each axis (default 25%).
    /// Returns nil if segments contain no coordinates.
    private func regionFittingRoute(_ segments: [RenderRouteSegment], padding: Double = 0.25) -> MKCoordinateRegion? {
        let coords = segments.flatMap { $0.coords }
        guard !coords.isEmpty else { return nil }
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        // Enforce a reasonable minimum span so a single-point day doesn't zoom in to street level.
        let latSpan = max(0.008, (maxLat - minLat) * (1.0 + padding))
        let lonSpan = max(0.008, (maxLon - minLon) * (1.0 + padding))
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
    }

    private func applyRenderSnapshotIfCurrent(_ snapshot: LifelogRenderSnapshot, generation: Int) {
        guard renderGenerationState.accepts(generation) else { return }
        debugRenderLog(
            "apply generation=\(generation) day=\(debugDayString(snapshot.selectedDay)) " +
            "far=\(snapshot.farRouteSegments.count) high=\(snapshot.isHighQuality)"
        )
        renderSnapshot = snapshot
#if DEBUG
        diagnosticsLog(
            "snapshot apply generation=\(generation) farSegs=\(snapshot.farRouteSegments.count)"
        )
        diagnosticsUpdateIfNeeded(reason: "renderSnapshot")
#endif

        // Only act on high-quality snapshots. Placeholders have no route data and
        // clearing pendingRecenterDay on them would cause the real snapshot to be ignored.
        guard snapshot.isHighQuality else { return }

        // Auto-fit today on the first fully-rendered snapshot (before the user pans).
        if !didAutoFitToRoute, isViewingToday {
            if let region = regionFittingRoute(snapshot.farRouteSegments) {
                cameraCommand = LifelogCameraCommand(id: UUID(), region: region)
            }
            didAutoFitToRoute = true
        }

        guard let pendingDay = pendingRecenterDay else { return }
        guard let snapshotDay = snapshot.selectedDay else { return }
        guard Calendar.current.isDate(snapshotDay, inSameDayAs: pendingDay) else { return }

        if let region = regionFittingRoute(snapshot.farRouteSegments) {
            cameraCommand = LifelogCameraCommand(id: UUID(), region: region)
        } else if let wgs = snapshot.selectedDayCenterCoordinate {
            cameraCommand = LifelogCameraCommand(id: UUID(), region: MKCoordinateRegion(
                center: mapCoordForLifelog(wgs),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            ))
        }
        pendingRecenterDay = nil
    }

    private func scheduleRenderSnapshotRefresh(debounceNanoseconds: UInt64 = 0) {
        renderTask?.cancel()

        var generationState = renderGenerationState
        let generation = generationState.issue()
        renderGenerationState = generationState

        let targetDay = Calendar.current.startOfDay(for: selectedDay ?? Date())
        // Always use full-day snapshot (no viewport clipping). A single day's
        // route data (10-50 segments) is well within MapKit's native culling
        // capacity, and avoiding viewport-specific rebuilds eliminates the
        // polyline-swap flash that occurs when dragging the map.
        let viewport: TrackTileViewport? = nil
        let countryISO2 = lifelogCountryISO2
        debugRenderLog(
            "schedule generation=\(generation) day=\(debugDayString(targetDay)) " +
            "viewport=\(viewport != nil) country=\(countryISO2 ?? "nil")"
        )
        let cachedSnapshot = lifelogRenderCache.cachedRenderSnapshot(
            day: targetDay,
            countryISO2: countryISO2,
            viewport: viewport
        )
        if let cachedSnapshot {
            applyRenderSnapshotIfCurrent(cachedSnapshot, generation: generation)
        } else if renderSnapshot.isHighQuality,
                  let snapshotDay = renderSnapshot.selectedDay,
                  Calendar.current.isDate(snapshotDay, inSameDayAs: targetDay) {
            // Current snapshot is same-day and high quality — keep it visible
            // instead of applying a placeholder that would cause a flash.
        } else {
            applyRenderSnapshotIfCurrent(
                LifelogRenderRefreshPolicy.placeholderSnapshot(
                    currentSnapshot: renderSnapshot,
                    targetDay: targetDay,
                    cachedSnapshot: cachedSnapshot
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
                    // Apply an empty snapshot so a stale placeholder doesn't linger.
                    applyRenderSnapshotIfCurrent(
                        LifelogRenderSnapshot(
                            selectedDay: targetDay,
                            cachedPathCoordsWGS84: [],
                            farRouteSegments: [],
                            selectedDayCenterCoordinate: nil,
                            isHighQuality: true
                        ),
                        generation: generation
                    )
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
        let engine = (MapLayerStyle(rawValue: layerStyleRaw) ?? .mutedDark).engine
        guard engine == .mapkit else { return coord }
        return MapCoordAdapter.forMapKit(coord, countryISO2: lifelogCountryISO2)
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

            VStack(alignment: .center, spacing: LifelogStepMilestonePresentation.contentSpacing) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [FigmaTheme.primary.opacity(0.2), FigmaTheme.primary.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(
                            width: LifelogStepMilestonePresentation.heroIconDiameter,
                            height: LifelogStepMilestonePresentation.heroIconDiameter
                        )

                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: LifelogStepMilestonePresentation.heroIconSize, weight: .bold))
                        .foregroundColor(FigmaTheme.primary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    if LifelogStepMilestonePresentation.showsCelebrationHeadline {
                        Text("🎉 太棒了！")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(FigmaTheme.primary)
                    }

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
            .padding(.top, LifelogStepMilestonePresentation.topPadding)
            .padding(.horizontal, LifelogStepMilestonePresentation.horizontalPadding)
            .padding(.bottom, 22)
            .background(FigmaTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(FigmaTheme.border, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if LifelogStepMilestonePresentation.closeButtonPlacement == .topTrailing {
                    Button {
                        dismissStepModal()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(FigmaTheme.subtext)
                            .frame(width: 28, height: 28)
                            .background(FigmaTheme.background.opacity(0.92))
                            .clipShape(Circle())
                            .appMinTapTarget()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                }
            }
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

// MARK: - Always Location Guide View

private struct AlwaysLocationGuideView: View {
    @Binding var isPresented: Bool
    let onEnable: () -> Void
    var onSkip: (() -> Void)?

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
                        onSkip?()
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

// MARK: - Lifelog Avatar Annotation Content (used by UnifiedMapView engines)

struct LifelogAvatarAnnotationContent: View {
    let shouldShowMoodQuestion: Bool
    let onMoodTap: () -> Void
    let onDoubleTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            if shouldShowMoodQuestion {
                Button(action: onMoodTap) {
                    Text("❓")
                        .font(.system(size: 21))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(red: 1.0, green: 249 / 255.0, blue: 221 / 255.0)))
                        .overlay(Circle().stroke(Color(red: 1.0, green: 191 / 255.0, blue: 84 / 255.0), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
            }
            RobotRendererView(
                size: AvatarMapMarkerStyle.visualSize,
                face: .front,
                loadout: AvatarLoadoutStore.load()
            )
            .frame(width: AvatarMapMarkerStyle.annotationSize, height: AvatarMapMarkerStyle.annotationSize)
            .shadow(color: .black.opacity(0.24), radius: 8, y: 2)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onDoubleTap)
        }
    }
}

// Old LifelogMKMapView removed — now using UnifiedMapView
