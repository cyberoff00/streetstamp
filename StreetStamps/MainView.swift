import Foundation
import SwiftUI
import MapKit
import CoreLocation

// MARK: - Design Theme
private struct DesignTheme {
    static let accent = FigmaTheme.primary
}

struct MainView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var locationHub: LocationHub
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var lifelogStore: LifelogStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @EnvironmentObject private var publishStore: JourneyPublishStore

    @Binding var selectedTab: Int
    @StateObject private var tracking = TrackingService.shared
    
    @State private var showMapView = false
    @State private var showSharingCard = false
    @State private var sharingJourney: JourneyRoute? = nil
    
    @State private var hasOngoingJourney = false
    @State private var ongoingJourney = JourneyRoute()
    @State private var didPrefetchAfterFirstCoord = false
    
    @State private var trackingMode: TrackingMode = .daily
    @State private var startPulse = false
    @State private var showTitle = false
    @State private var showStartButton = false
    @State private var didPlayStartIntro = false
    @State private var ripplePhase = false
    
    @StateObject private var cityLoc = CityLocationManager()
    @State private var showLinkEmailPrompt = false

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
                let controlLift: CGFloat = compactHeight ? -8 : -12

                VStack(spacing: 0) {
                    Spacer().frame(height: titleTop)

                    Text(L10n.t("main_unlock_new_journey"))
                        .font(.system(size: 26, weight: .black))
                        .tracking(-0.6)
                        .lineSpacing(9)
                        .foregroundColor(Color.black.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: 360)
                        .padding(.bottom, 64)
                        .opacity(showTitle ? 1 : 0)
                        .offset(y: showTitle ? 0 : 18)

                    startButton(circleSize: circleSize)
                        .opacity(showStartButton ? 1 : 0)
                        .scaleEffect(showStartButton ? 1 : 0.96)
                        .offset(y: (showStartButton ? 0 : 20) + controlLift)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                Color.clear
                    .frame(width: 42, height: 42)
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
                        selectedTab = NavigationTab.cities.rawValue
                        onboardingGuide.advance(.openCityCards)
                    }
                )
            } else {
                Color.clear.onAppear { showSharingCard = false }
            }
        }
        .overlay(alignment: .bottom) {
            if onboardingGuide.isCurrent(.startJourney) {
                OnboardingCoachCard(
                    message: OnboardingGuideStore.Step.startJourney.message,
                    actionTitle: OnboardingGuideStore.Step.startJourney.actionTitle,
                    onAction: { startOrContinueJourneyAndOpenMap() },
                    onLater: { onboardingGuide.pauseForLater() },
                    onSkip: { onboardingGuide.skipAll() }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 98)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showSharingCard)
        .onChange(of: showSharingCard) { isShowing in
            if !isShowing { sharingJourney = nil }
        }
        .onAppear {
            cityLoc.bind(to: locationHub)
            if !didPlayStartIntro {
                showTitle = false
                showStartButton = false
                withAnimation(.easeOut(duration: 0.35)) { showTitle = true }
                withAnimation(.easeOut(duration: 0.45).delay(0.08)) { showStartButton = true }
                didPlayStartIntro = true
            } else {
                showTitle = true
                showStartButton = true
            }
            ripplePhase = true
            startPulse = false
            if store.hasLoaded {
                syncOngoingFromStore()
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
        .onChange(of: flow.pendingWidgetCaptureSignal) { signal in
            guard signal > 0 else { return }
            syncOngoingFromStore()
            guard hasOngoingJourney, ongoingJourney.endTime == nil else {
                flow.consumeWidgetCapture()
                return
            }
            showMapView = true
        }
        .onChange(of: flow.endOngoingSignal) { _ in
            syncOngoingFromStore()
            guard hasOngoingJourney, ongoingJourney.endTime == nil else { return }
            endUnfinishedJourneyAndShare()
        }
        .sheet(isPresented: $showLinkEmailPrompt) {
            NavigationStack {
                LinkEmailPasswordView()
                    .environmentObject(sessionStore)
            }
        }
        .onAppear { checkLinkEmailPrompt() }
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
    
    // MARK: - Link Email Prompt

    private func checkLinkEmailPrompt() {
        guard sessionStore.isLoggedIn,
              !sessionStore.hasEmailPassword,
              LinkEmailPromptPolicy.shouldShow()
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard sessionStore.isLoggedIn, !sessionStore.hasEmailPassword else { return }
            showLinkEmailPrompt = true
            LinkEmailPromptPolicy.recordDismissal()
        }
    }

    // MARK: - UI Components

    private var isGuideStartStep: Bool {
        onboardingGuide.isCurrent(.startJourney)
    }
    
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
                    .overlay {
                        if isGuideStartStep {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .shadow(color: Color.white.opacity(0.8), radius: 8)
                        }
                    }

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
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                    Text(buttonText)
                        .font(.system(size: 40 / 2, weight: .bold))
                        .tracking(-0.4)
                        .foregroundColor(.white)
                }
            }
            .appFullSurfaceTapTarget(.circle)
        }
        .buttonStyle(.plain)
        .scaleEffect(isGuideStartStep ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isGuideStartStep)
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
            // MARK: - Journey Logic
            
            private func startOrContinueJourneyAndOpenMap() {
                onboardingGuide.advance(.startJourney)
                locationHub.requestPermissionIfNeeded()

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
                    lifelogStore: lifelogStore,
                    source: .resumeDeclined,
                    recordedLocations: tracking.recordedLocationsForMemories,
                    lastKnownLocation: tracking.latestReliableLocationForMemories
                ) { updated in
                    ongoingJourney = updated
                    sharingJourney = updated
                    showSharingCard = true
                }
            }

            private func completeJourneyAndSync(journey: JourneyRoute) {
                ongoingJourney = journey
                JourneySaveCompletion.persistFinalizedJourney(journey, in: store)
                publishStore.publish(
                    journey: journey,
                    sessionStore: sessionStore,
                    cityCache: cityCache,
                    journeyStore: store
                )
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
            Section(L10n.t("debug_cn_test_section")) {
                NavigationLink(L10n.t("debug_cn_test_full")) {
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
