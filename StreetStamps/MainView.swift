import Foundation
import SwiftUI
import MapKit
import CoreLocation

// MARK: - Design Theme
private struct DesignTheme {
    static let bg = FigmaTheme.background
    static let accent = FigmaTheme.primary
    static let text = FigmaTheme.text
    static let modeBorder = FigmaTheme.secondary
}

struct MainView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var locationHub: LocationHub
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    
    @Binding var selectedTab: Int
    @Binding var showSidebar: Bool
    @StateObject private var tracking = TrackingService.shared
    
    @State private var showMapView = false
    @State private var showSharingCard = false
    @State private var sharingJourney: JourneyRoute? = nil
    
    @State private var hasOngoingJourney = false
    @State private var ongoingJourney = JourneyRoute()
    @State private var didPrefetchAfterFirstCoord = false
    
    @State private var trackingMode: TrackingMode = .daily
    @State private var showModeSelector = false
    @State private var startPulse = false
    @State private var showTitle = false
    @State private var showStartButton = false
    @State private var showModeButtonState = false
    @State private var didPlayStartIntro = false
    @State private var ripplePhase = false
    
    @StateObject private var cityLoc = CityLocationManager()
    
#if DEBUG
    @State private var showDebugPanel = false
#endif
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            FigmaTheme.mutedBackground.ignoresSafeArea()

            GeometryReader { proxy in
                let compactHeight = proxy.size.height < 760
                let topInset = max(12, proxy.safeAreaInsets.top + 6)
                let circleSize = min(max(220, proxy.size.width * 0.65), 258)
                let titleTop = compactHeight ? max(120, proxy.size.height * 0.18) : max(156, proxy.size.height * 0.205)

                VStack(spacing: 0) {
                    Spacer().frame(height: titleTop)

                    Text("JOURNEY")
                        .font(.system(size: min(72, proxy.size.width * 0.183), weight: .black))
                        .tracking(-3.2)
                        .foregroundColor(.black)
                        .opacity(showTitle ? 1 : 0)
                        .offset(y: showTitle ? 0 : 18)

                    Spacer().frame(height: compactHeight ? 40 : 52)

                    startButton(circleSize: circleSize)
                        .opacity(showStartButton ? 1 : 0)
                        .scaleEffect(showStartButton ? 1 : 0.96)
                        .offset(y: showStartButton ? 0 : 20)

                    Spacer().frame(height: compactHeight ? 26 : 32)

                    modeButton
                        .opacity(showModeButtonState ? 1 : 0)
                        .offset(y: showModeButtonState ? 0 : 12)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 24)

                SidebarHamburgerButton(showSidebar: $showSidebar, size: 42, iconSize: 20, iconWeight: .semibold, foreground: .black)
                .padding(.leading, 24)
                .padding(.top, topInset)
#if DEBUG
                .onLongPressGesture(minimumDuration: 0.6) {
                    showDebugPanel = true
                }
#endif
            }
        }
       
        .fullScreenCover(isPresented: $showMapView) {
            MapView(
                cityName: resolvedCanonicalCityForNewJourney,
                isPresented: $showMapView,
                hasOngoingJourney: $hasOngoingJourney,
                selectedTab: $selectedTab,
                journeyRoute: $ongoingJourney,
                showSharingCard: $showSharingCard,
                sharingJourney: $sharingJourney
            )
        }
        .fullScreenCover(isPresented: $showSharingCard) {
            if let j = sharingJourney {
                let fallback: CLLocationCoordinate2D? = j.coordinates.last?.cl
                PopSharingCard(
                    isPresented: $showSharingCard,
                    journey: j,
                    fallbackCenter: fallback,
                    onContinueJourney: {
                        var resumed = j
                        resumed.endTime = nil
                        ongoingJourney = resumed
                        hasOngoingJourney = true
                        store.upsertSnapshotThrottled(resumed, coordCount: resumed.coordinates.count)
                        store.flushPersist()
                        tracking.syncFromJourneyIfNeeded(resumed)
                        tracking.resumeJourney()
                        showMapView = true
                    },
                    onCompleteAndExit: { finalized in
                        completeJourneyAndSync(journey: finalized)
                        hasOngoingJourney = false
                        sharingJourney = nil
                    },
                    onGoToLibrary: {
                        selectedTab = 1
                    }
                )
            } else {
                Color.clear.onAppear { showSharingCard = false }
            }
        }
        .overlay {
            if showModeSelector {
                modeSelectorOverlay
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showSharingCard)
        .animation(.easeInOut(duration: 0.18), value: showModeSelector)
        .onChange(of: showSharingCard) { isShowing in
            if !isShowing { sharingJourney = nil }
        }
        .onAppear {
            cityLoc.bind(to: locationHub)
            if !didPlayStartIntro {
                showTitle = false
                showStartButton = false
                showModeButtonState = false
                withAnimation(.easeOut(duration: 0.35)) { showTitle = true }
                withAnimation(.easeOut(duration: 0.45).delay(0.08)) { showStartButton = true }
                withAnimation(.easeOut(duration: 0.35).delay(0.16)) { showModeButtonState = true }
                didPlayStartIntro = true
            } else {
                showTitle = true
                showStartButton = true
                showModeButtonState = true
            }
            ripplePhase = true
            startPulse = false
            // ✅ 只有 store 加载完成才同步，否则等 onChange 触发
            if store.hasLoaded {
                syncOngoingFromStore()
                cityCache.rebuildFromJourneyStore()
            }
            if tracking.isTracking && ongoingJourney.endTime == nil {
                hasOngoingJourney = true
            }
        }
        .onChange(of: showMapView) { isShowing in
            if !isShowing {
                syncOngoingFromStore()
                if !tracking.isTracking, ongoingJourney.endTime != nil {
                    hasOngoingJourney = false
                }
            }
        }
        // ✅ 监听 store 加载完成，立即同步数据
        .onChange(of: store.hasLoaded) { loaded in
            if loaded {
                syncOngoingFromStore()
                cityCache.rebuildFromJourneyStore()
            }
        }
        .onChange(of: trackingMode) { newMode in
            // ✅ 旅程中也允许切换；策略 B：若当前已在前台静止省电态，不强制退出省电态
            tracking.setTrackingMode(newMode)
            
            // ✅ ongoing 旅程把 mode 写回去（只更新 meta，不强制写坐标大文件）
            if hasOngoingJourney, ongoingJourney.endTime == nil {
                var updated = ongoingJourney
                updated.trackingMode = newMode
                ongoingJourney = updated
                store.upsertSnapshotThrottled(updated, coordCount: updated.coordinates.count)
            }
        }
        .onChange(of: flow.resumeOngoingSignal) { _ in
            syncOngoingFromStore()
            guard hasOngoingJourney, ongoingJourney.endTime == nil else { return }
            showMapView = true
        }
        .onChange(of: flow.endOngoingSignal) { _ in
            syncOngoingFromStore()
            guard hasOngoingJourney, ongoingJourney.endTime == nil else { return }
            endUnfinishedJourneyAndShare()
        }
#if DEBUG
        .sheet(isPresented: $showDebugPanel) {
            DebugLocationPanel(
                modeText: debugModeText,
                onSwitchToSystem: { locationHub.switchToSystem() },
                onJumpToCity: { coord in
                    locationHub.mockPlayPath(points: [coord, coord], pointsPerSecond: 2.0, fixedSpeed: 0, accuracy: 5, altitude: 10)
                },
                onSimulateFlight: { path in
                    locationHub.mockPlayPath(points: path, pointsPerSecond: 2.5, fixedSpeed: 240, accuracy: 5, altitude: 10000)
                }
            )
        }
#endif
    }
    
    // MARK: - UI Components
    
    private func startButton(circleSize: CGFloat) -> some View {
        Button(action: startOrContinueJourneyAndOpenMap) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.46))
                    .frame(width: circleSize + 18, height: circleSize + 18)

                Circle()
                    .fill(DesignTheme.accent)
                    .frame(width: circleSize, height: circleSize)
                    .shadow(color: DesignTheme.accent.opacity(0.30), radius: 24, y: 12)

                Circle()
                    .stroke(DesignTheme.accent.opacity(0.22), lineWidth: 1.5)
                    .frame(width: circleSize + 28, height: circleSize + 28)
                    .scaleEffect(ripplePhase ? 1.045 : 0.99)
                    .opacity(ripplePhase ? 0.08 : 0.14)
                    .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: ripplePhase)

                Circle()
                    .stroke(DesignTheme.accent.opacity(0.10), lineWidth: 1.0)
                    .frame(width: circleSize + 54, height: circleSize + 54)
                    .scaleEffect(ripplePhase ? 1.03 : 0.985)
                    .opacity(ripplePhase ? 0.05 : 0.09)
                    .animation(.easeInOut(duration: 3.1).repeatForever(autoreverses: true), value: ripplePhase)

                VStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 48, weight: .black))
                        .foregroundColor(.white)
                    Text(buttonText)
                        .font(.system(size: 40 / 2, weight: .black))
                        .tracking(-0.4)
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var modeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                showModeSelector = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: trackingMode == .sport ? "bolt.fill" : "shoeprints.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(DesignTheme.modeBorder)

                Text(trackingMode == .sport ? L10n.key("lockscreen_sport_mode") : L10n.key("lockscreen_daily_mode"))
                    .font(.system(size: 32 / 2, weight: .black))
                    .tracking(-0.4)
                    .foregroundColor(DesignTheme.modeBorder)
            }
            .padding(.horizontal, 32)
            .frame(height: 59)
            .background(Color.white.opacity(0.94))
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(DesignTheme.modeBorder, lineWidth: 1.5)
            )
            .shadow(color: DesignTheme.modeBorder.opacity(0.12), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
    }
            
            // MARK: - Mode Selector Popup
            private var buttonText: String {
                let hasLiveJourney = hasOngoingJourney || (tracking.isTracking && ongoingJourney.endTime == nil)
                if !hasLiveJourney {
                    return L10n.t("start_upper")
                }
                
                // 有进行中的旅程
                if tracking.wasExplicitlyPaused {
                    // 用户主动暂停了 → 显示 "继续" 或 "RESUME"
                    return L10n.t("resume_upper")
                } else {
                    // 只是后台运行（没主动暂停）→ 显示 "进行中"
                    return L10n.t("in_progress_upper")
                }
            }
            private var modeSelectorOverlay: some View {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showModeSelector = false
                            }
                        }
                    
                    TrackingModeSelector(selectedMode: $trackingMode, isPresented: $showModeSelector)
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 28)
                        .transition(.opacity)
                }
            }
            
            // MARK: - Journey Logic
            
            private func startOrContinueJourneyAndOpenMap() {
                if !hasOngoingJourney {
                    ongoingJourney = JourneyRoute()
                    ongoingJourney.startTime = Date()
                    ongoingJourney.endTime = nil
                    ongoingJourney.trackingMode = trackingMode
                    
                    let canonical = cityLoc.canonicalCity.trimmingCharacters(in: .whitespacesAndNewlines)
                    ongoingJourney.canonicalCity = canonical.isEmpty ? L10n.t("unknown") : canonical
                    ongoingJourney.cityKey = cityLoc.canonicalCityKey
                    ongoingJourney.countryISO2 = cityLoc.countryISO2
                    
                    ongoingJourney.currentCity = ongoingJourney.canonicalCity
                    ongoingJourney.cityName = ongoingJourney.canonicalCity
                    
                    hasOngoingJourney = true
                    didPrefetchAfterFirstCoord = false
                    
                    tracking.startNewJourney(mode: trackingMode)
                } else {
                    tracking.resumeJourney()
                }
                
                showMapView = true
            }
            
            private var resolvedCanonicalCityForNewJourney: String {
                let t = cityLoc.canonicalCity.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? L10n.t("unknown") : t
            }
            
            // MARK: - Sync
            
            private func syncOngoingFromStore() {
                if let ongoing = store.latestOngoing, ongoing.endTime == nil {
                    ongoingJourney = ongoing
                    hasOngoingJourney = true
                    didPrefetchAfterFirstCoord = false
                    
                    // ✅ 恢复 ongoing 时对齐 UI + TrackingService
                    trackingMode = ongoing.trackingMode
                    tracking.setTrackingMode(trackingMode)
                    return
                }
                if let ongoing = store.journeys.first(where: { $0.endTime == nil }) {
                    ongoingJourney = ongoing
                    hasOngoingJourney = true
                    didPrefetchAfterFirstCoord = false
                    
                    // ✅ 恢复 ongoing 时对齐 UI + TrackingService
                    trackingMode = ongoing.trackingMode
                    tracking.setTrackingMode(trackingMode)
                    return
                }
                if let last = store.journeys.first {
                    ongoingJourney = last
                }
                hasOngoingJourney = false
            }
            
            // MARK: - Unfinished journey prompt
            
            private func endUnfinishedJourneyAndShare() {
                var ended = ongoingJourney
                ended.endTime = Date()
                hasOngoingJourney = false
                
                tracking.stopJourney()
                
                JourneyFinalizer.finalize(
                    route: ended,
                    journeyStore: store,
                    cityCache: cityCache,
                    source: .resumeDeclined
                ) { updated in
                    ongoingJourney = updated
                    sharingJourney = updated
                    showSharingCard = true
                }
            }

            private func completeJourneyAndSync(journey: JourneyRoute) {
                ongoingJourney = journey
                store.flushPersist(journey: journey)
                triggerAutoCloudSyncAfterSave(savedJourney: journey)
            }

            private func triggerAutoCloudSyncAfterSave(savedJourney: JourneyRoute) {
                guard savedJourney.visibility == .public || savedJourney.visibility == .friendsOnly else { return }
                guard BackendConfig.isEnabled,
                      let token = sessionStore.currentAccessToken,
                      !token.isEmpty else { return }

                Task {
                    do {
                        _ = try await JourneyCloudMigrationService.migrateAll(
                            sessionStore: sessionStore,
                            journeyStore: store,
                            cityCache: cityCache
                        )
                    } catch {
                        print("❌ auto cloud sync after save failed:", error.localizedDescription)
                    }
                }
            }
            
#if DEBUG
            private var debugModeText: String {
                switch locationHub.mode {
                case .system: return L10n.t("debug_mode_system")
                case .mock: return L10n.t("debug_mode_mock")
                }
            }
#endif
        }
    
        
        // MARK: - Tracking Mode Selector Sheet
        
struct TrackingModeSelector: View {
    @Binding var selectedMode: TrackingMode
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("SELECT MODE")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(DesignTheme.accent)
            
            VStack(spacing: 14) {
                ModeOptionCard(
                    mode: .sport,
                    isSelected: selectedMode == .sport,
                    onSelect: {
                        selectedMode = .sport
                        withAnimation(.easeInOut(duration: 0.18)) { isPresented = false }
                    }
                )
                
                ModeOptionCard(
                    mode: .daily,
                    isSelected: selectedMode == .daily,
                    onSelect: {
                        selectedMode = .daily
                        withAnimation(.easeInOut(duration: 0.18)) { isPresented = false }
                    }
                )
            }
            .padding(18)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
    }
}
    
struct ModeOptionCard: View {
    let mode: TrackingMode
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? DesignTheme.accent.opacity(0.15) : Color.black.opacity(0.05))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: mode == .sport ? "bolt.fill" : "figure.walk")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isSelected ? DesignTheme.accent : .black.opacity(0.5))
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 6) {
                    Text(mode == .sport ? L10n.key("lockscreen_sport_mode") : L10n.key("lockscreen_daily_mode"))
                        .font(.system(size: 15, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.black)
                    
                    Text(mode == .sport ? L10n.key("sport_mode_desc") : L10n.key("daily_mode_desc"))
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.55))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                    // Bottom hint row
                    HStack(spacing: 12) {
                        if mode == .sport {
                            Text(L10n.key("hint_precise"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DesignTheme.accent)
                            Text(L10n.key("hint_battery"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.black.opacity(0.35))
                        } else {
                            Text(L10n.key("hint_precision"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.black.opacity(0.35))
                            Text(L10n.key("hint_efficient"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DesignTheme.accent)
                        }
                    }
                    .padding(.top, 2)
                }
                
                Spacer()
            }
            .padding(16)
            .background(isSelected ? DesignTheme.bg : Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? DesignTheme.accent : Color.black.opacity(0.10), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
    
    // MARK: - Debug Panel (kept for development)

#if DEBUG
private struct DebugLocationPanel: View {
var modeText: String
var onSwitchToSystem: () -> Void
var onJumpToCity: (CLLocationCoordinate2D) -> Void
var onSimulateFlight: ([CLLocationCoordinate2D]) -> Void

@Environment(\.dismiss) private var dismiss

private let shanghai = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
private let london   = CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)

var body: some View {
    NavigationView {
        List {
            Section("🇨🇳 中国测试") {
                NavigationLink("完整测试板块") {
                    DebugChinaTestModule()
                }
            }
            Section(L10n.t("debug_section_mode")) {
                HStack {
                    Text(L10n.t("debug_location"))
                    Spacer()
                    Text(modeText).foregroundColor(.gray)
                }
                Button(L10n.t("debug_switch_to_system")) { onSwitchToSystem() }
            }

            Section(L10n.t("debug_section_quick_jump")) {
                Button(L10n.t("debug_jump_shanghai")) { onJumpToCity(shanghai) }
                Button(L10n.t("debug_jump_london")) { onJumpToCity(london) }
            }

            Section(L10n.t("debug_section_simulation")) {
                Button(L10n.t("debug_simulate_flight")) {
                    let points = interpolateLine(from: shanghai, to: london, steps: 120)
                    onSimulateFlight(points)
                }
            }

            Section {
                Button(L10n.t("close")) { dismiss() }
                    .foregroundColor(.red)
            }
        }
        .navigationTitle(L10n.t("debug_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func interpolateLine(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, steps: Int) -> [CLLocationCoordinate2D] {
    guard steps >= 2 else { return [a, b] }
    return (0..<steps).map { i in
        let t = Double(i) / Double(steps - 1)
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }
}
}
#endif
