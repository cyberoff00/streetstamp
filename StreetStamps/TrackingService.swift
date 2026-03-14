import Foundation
import CoreLocation
import UIKit
import Combine
import UserNotifications

@MainActor
final class TrackingService: ObservableObject {

    static let shared = TrackingService()

    // MARK: - Public observable states

    @Published var userLocation: CLLocation?
    @Published var isTracking: Bool = false
    

    /// Raw recorded points (WGS84) used for storage & internal segment building.
    @Published private(set) var coords: [CLLocationCoordinate2D] = []

    @Published var totalDistance: Double = 0
    /// Total horizontal (2D) distance in meters.

    /// Total positive elevation gain (meters) accumulated from accepted points.
    @Published var totalAscent: Double = 0
    /// Total negative elevation loss (meters) accumulated from accepted points.
    @Published var totalDescent: Double = 0
    @Published var headingDegrees: Double = 0
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var movingSeconds: Int = 0
    @Published private(set) var pausedSeconds: Int = 0
    @Published private(set) var droppedByAccuracyCount: Int = 0
    @Published private(set) var droppedByJumpCount: Int = 0
    @Published private(set) var droppedByStationaryCount: Int = 0
    @Published private(set) var missingSegmentCount: Int = 0

    @Published private(set) var mode: TravelMode = .unknown

    // MARK: - Pause / Render switch

    @Published var isPaused: Bool = false
    @Published var wasExplicitlyPaused: Bool = false
    /// 当前追踪模式
    @Published private(set) var trackingMode: TrackingMode = .daily
    
    /// 当前模式配置
    private var modeConfig: TrackingModeConfig { TrackingModeConfig.config(for: trackingMode) }


    /// Foreground render switch. When false, no UI cache updates.
    @Published private(set) var isRealtimeRenderingEnabled: Bool = true

    /// Returned from background while tracking. MapView will show refresh affordance,
    /// BUT you chose "MapView进来自动对齐一次" => MapView will clear this.
    @Published private(set) var needsRefreshAfterBackground: Bool = false

    // MARK: - ✅ China gating (WGS->GCJ only in CN)

    @Published private(set) var shouldApplyChinaOffset: Bool = false



    enum SegmentStyle: String, Codable, Equatable { case solid, dashed }

    struct RouteSegment: Identifiable, Equatable {
        let id: String
        var style: SegmentStyle
        var coords: [CLLocationCoordinate2D] // WGS in internalSegments; map-ready in renderSegmentsForMap
    }

    /// Legacy WGS snapshot (not used by MapView anymore)
    @Published var segments: [RouteSegment] = []

    /// Always maintained (WGS)
    private var internalSegments: [RouteSegment] = []

    /// Always maintained (map-ready coords) for rendering cache (to avoid O(N) conversion every update)
    private var internalSegmentsForMap: [RouteSegment] = []

    /// Rebuild map-ready segments from WGS segments. Use only when internalSegments is replaced wholesale.
    private func rebuildInternalSegmentsForMapFromInternal() {
        let convert = self.convertForMap
        internalSegmentsForMap = internalSegments.map { seg in
            var s = seg
            s.coords = seg.coords.map(convert)
            return s
        }
    }

    // MARK: - ✅ Render cache output for MapView (map-ready coords)

    @Published private(set) var renderSegmentsForMap: [RouteSegment] = []
    @Published private(set) var renderUnifiedSegmentsForMap: [RenderRouteSegment] = []
    @Published private(set) var renderLiveTailForMap: [CLLocationCoordinate2D] = []

    // MARK: - Quality / UX

    @Published var isLocationLocked: Bool = false
    @Published var lastHorizontalAccuracy: CLLocationAccuracy = -1

    // MARK: - Internal state

    private var lastLocation: CLLocation?
    private var rawCoords: [CLLocationCoordinate2D] = []
    private var acceptedLocations: [CLLocation] = []
    private let smoothingWindow: Int = 5

    // MARK: - Sampling / filtering knobs

    var foregroundMinDistance: Double = 8
    var backgroundMinDistance: Double = 10

    var maxAcceptableAccuracy: Double = 70

    // MARK: - Elevation accumulation knobs

    /// Vertical accuracy is often noisy; only use altitude deltas when both points are reasonably accurate.
    var maxAcceptableVerticalAccuracy: Double = 25

    /// Ignore tiny altitude fluctuations to avoid counting GPS/barometer noise.
    var minElevationDeltaToCount: Double = 1.5

    // MARK: - ✅ Stationary jitter suppression + power saving

    /// When user is stationary, GPS jitter can create "hairy" lines. We keep monitoring
    /// location for UX (blue dot), but only record a new route point when the user actually moves.
    /// Also, after a short stationary hold, we can switch the CLLocationManager to a lower-power
    /// foreground mode, then switch back once movement resumes.
    var stationaryBaseMinMoveMeters: Double = 5
    var stationarySpeedThreshold: Double = 0.5 // m/s
    var stationaryHoldSeconds: TimeInterval = 12

    /// When accuracy is weak we sometimes let points through even if they don't clear `minD`.
    /// This helps preserve curvature while moving, but can create "scribble" while stationary.
    /// Gate the weak-accuracy bypass behind a minimum speed / distance.
    var weakAccuracyBypassMinSpeed: Double = 0.8 // m/s (~2.9 km/h)
    var weakAccuracyBypassMinDistance: Double = 18.0 // meters

    /// If speed is unknown (-1), we infer speed from last-recorded location.
    /// This multiplier provides hysteresis so we don't flap between stationary/moving.
    private let stationaryExitMoveMultiplier: Double = 1.8
    private let weakDriftDeferMinDistanceMeters: Double = 55
    private let weakDriftDecisionWindow: TimeInterval = 90
    private let weakDriftReturnRadiusMeters: Double = 20
    private let weakDriftConfirmationDistanceMeters: Double = 32

    private var lastRecordedLocationForStationary: CLLocation?
    private var stationarySince: Date?
    private var isInForegroundStationaryPowerMode: Bool = false
    private var deferredWeakDriftJump: DeferredWeakDriftJump?

    var lockAccuracy: Double = 25
    var lockConsecutiveCount: Int = 2
    private var lockStreak: Int = 0

    var maxPlausibleSpeed: Double = 18.0
    var maxJumpDistance: Double = 120.0
    var hardJumpDistance: Double = 350.0
    var dropJumpDistanceWhenAccuracyBad: Double = 180.0
    var accuracyBadThreshold: Double = 120.0

    // MARK: - Dashed policy

    var weakAccuracyThreshold: Double = 35

    var gapSecondsThreshold: TimeInterval = 12
    var gapDistanceThreshold: Double = 120

    var backgroundGapSecondsThreshold: TimeInterval = 180
    var backgroundGapDistanceThreshold: Double = 600

    var missingGapSecondsThreshold: TimeInterval = 15 * 60
    var missingGapDistanceThreshold: Double = 50_000

    // MARK: - Turn keep

    var turnKeepAngleForeground: [TravelMode: Double] = [
        .walk: 22, .run: 20, .transit: 18,
        .bike: 18, .motorcycle: 16, .drive: 16,
        .flight: 180, .unknown: 20
    ]

    var turnKeepAngleBackground: [TravelMode: Double] = [
        .walk: 18, .run: 18, .transit: 16,
        .bike: 16, .motorcycle: 14, .drive: 14,
        .flight: 180, .unknown: 16
    ]
    private let defaultTurnKeepAngleForeground: [TravelMode: Double] = [
        .walk: 22, .run: 20, .transit: 18,
        .bike: 18, .motorcycle: 16, .drive: 16,
        .flight: 180, .unknown: 20
    ]
    private let defaultTurnKeepAngleBackground: [TravelMode: Double] = [
        .walk: 18, .run: 18, .transit: 16,
        .bike: 16, .motorcycle: 14, .drive: 14,
        .flight: 180, .unknown: 16
    ]

    // MARK: - Segment switching hysteresis

    private var pendingStyle: SegmentStyle? = nil
    private var pendingStyleStartAt: Date = .distantPast
    private var pendingStylePointCount: Int = 0
    private let segmentConfirmMinSeconds: TimeInterval = 4
    private let segmentConfirmMinPoints: Int = 2

    // MARK: - Mode inference

    private var speedSamples: [(t: Date, v: Double)] = []
    private var lastModeChangeAt: Date = .distantPast
    private let modeWindowSeconds: TimeInterval = 12
    private let modeCooldownSeconds: TimeInterval = 15

    private var bag = Set<AnyCancellable>()
    private let hub = LocationHub.shared
    private var trackingStartedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0
    private var currentPauseStartedAt: Date?

    // MARK: - Long stationary reminder (1h / 100m start-end displacement)

    private var longStationaryAnchorLocation: CLLocation?
    private var longStationaryAnchorTime: Date?
    private let longStationaryWindow: TimeInterval = 60 * 60
    private let longStationaryThresholdMeters: Double = 100

    private struct DeferredWeakDriftJump {
        let anchor: CLLocation
        let candidate: CLLocation
    }
    private let longStationaryNotificationID = "streetstamps.long_stationary_reminder"
    private let longStationaryNotificationPermissionAskedKey = "streetstamps.long_stationary_reminder.notification_asked.v1"

    // MARK: - ✅ Render cache internals

    private let renderQueue = DispatchQueue(label: "ss.render.cache", qos: .userInitiated)
    private var pendingRenderWork: DispatchWorkItem?
    private var lastRenderCoordCount: Int = 0
    private var lastRenderSegPointCount: Int = 0
    private let publishDebounceInterval: TimeInterval = 0.2
    private var pendingPublishWork: DispatchWorkItem?
    private var latestRenderSegmentsForMap: [RouteSegment] = []
    private var latestRenderUnifiedSegmentsForMap: [RenderRouteSegment] = []
    private var latestRenderLiveTailForMap: [CLLocationCoordinate2D] = []
    /// Dynamic debounce to reduce CPU/GPU wakeups without changing live-tracking UX.
    /// - While actively tracking (and not paused): keep original 10Hz.
    /// - Otherwise: relax updates; also respect iOS Low Power Mode.
    private var renderDebounceInterval: TimeInterval {
        var t: TimeInterval
        if isRealtimeRenderingEnabled && isTracking && !isPaused {
            // ✅ 根据模式调整渲染频率
            t = modeConfig.renderDebounceInterval
        } else {
            t = 0.25
        }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            t *= 1.7
        }
        return t
    }

    // MARK: - ✅ One Euro Filter (enabled by mode config; used for walk/run/bike)

    private var oneEuroLat = OneEuro1D()
    private var oneEuroLon = OneEuro1D()
    private var oneEuroEnabled: Bool = false
    private var oneEuroBaseMinCutoff: Double = 1.2

    private struct OneEuro1D {
        var prevX: Double?
        var prevDX: Double?
        var prevT: TimeInterval?

        // tunables
        var minCutoff: Double = 1.2
        var beta: Double = 0.08
        var dCutoff: Double = 1.0

        mutating func reset() {
            prevX = nil
            prevDX = nil
            prevT = nil
        }

        mutating func filter(x: Double, t: TimeInterval) -> Double {
            guard let pt = prevT else {
                prevT = t
                prevX = x
                prevDX = 0
                return x
            }

            let dt = max(0.001, t - pt)
            prevT = t

            let prevX0 = prevX ?? x
            let dx = (x - prevX0) / dt

            let edx = lowPass(x: dx, prev: (prevDX ?? dx), alpha: alpha(cutoff: dCutoff, dt: dt))
            prevDX = edx

            let cutoff = minCutoff + beta * abs(edx)
            let ex = lowPass(x: x, prev: prevX0, alpha: alpha(cutoff: cutoff, dt: dt))
            prevX = ex
            return ex
        }

        private func alpha(cutoff: Double, dt: Double) -> Double {
            let tau = 1.0 / (2.0 * Double.pi * cutoff)
            return 1.0 / (1.0 + tau / dt)
        }

        private func lowPass(x: Double, prev: Double, alpha: Double) -> Double {
            prev + alpha * (x - prev)
        }
    }

    private func resetOneEuro() {
        oneEuroLat.reset()
        oneEuroLon.reset()
    }

    private func oneEuroFilteredCoord(_ loc: CLLocation) -> CLLocationCoordinate2D {
        // Adaptive minCutoff from accuracy: worse accuracy => stronger smoothing
        let acc = max(5.0, loc.horizontalAccuracy)
        // Keep mode/base tuning, then adapt by current GPS accuracy.
        let base = oneEuroBaseMinCutoff
        let minBound = max(0.65, base - 0.35)
        let maxBound = base + 0.25
        let minCut = max(minBound, min(maxBound, base - (acc - 10.0) / 50.0))
        oneEuroLat.minCutoff = minCut
        oneEuroLon.minCutoff = minCut

        let t = loc.timestamp.timeIntervalSince1970
        let lat = oneEuroLat.filter(x: loc.coordinate.latitude, t: t)
        let lon = oneEuroLon.filter(x: loc.coordinate.longitude, t: t)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private init() {
        // ingest location stream
        hub.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] loc in
                guard let self else { return }
                self.ingest(loc)
            }
            .store(in: &bag)

        hub.$headingDegrees
            .removeDuplicates { abs($0 - $1) < 1.0 }
            .sink { [weak self] heading in
                guard let self else { return }
                let h = heading.truncatingRemainder(dividingBy: 360)
                self.headingDegrees = h >= 0 ? h : (h + 360)
            }
            .store(in: &bag)

        // ✅ gating subscription
        hub.$countryISO2
            .map { ($0 ?? "").uppercased() }
            .removeDuplicates()
            .sink { [weak self] iso2 in
                guard let self else { return }
                let newValue = (iso2 == "CN")
                guard newValue != self.shouldApplyChinaOffset else { return }
                self.shouldApplyChinaOffset = newValue
                // if MapView is active, update immediately
                self.rebuildRenderCache(force: true)
            }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isTracking else { return }
                // ✅ Save GPU in background, but keep recording.
                self.setRealtimeRenderingEnabled(false)
                self.needsRefreshAfterBackground = false
                self.enterLowPowerBackgroundMode()
            }
            .store(in: &bag)


        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isTracking else { return }
                self.startForegroundHighPower()
                // ✅ Auto refresh route when returning to foreground (no "刷新路线" button)
                self.needsRefreshAfterBackground = false
                self.setRealtimeRenderingEnabled(true)
                self.rebuildRenderCache(force: true)
            }
            .store(in: &bag)

    }

    // MARK: - Public APIs

    func startNewJourney(mode: TrackingMode = .daily) {
        // 设置追踪模式
        trackingMode = mode
        startLiveActivity()
        
        // 根据模式应用配置
        let config = TrackingModeConfig.config(for: mode)
        applyModeConfig(config)
        
        rawCoords.removeAll()
        coords.removeAll()
        totalDistance = 0
        totalAscent = 0
        totalDescent = 0

        lastLocation = nil
        acceptedLocations.removeAll(keepingCapacity: true)

        lastRecordedLocationForStationary = nil
        stationarySince = nil
        isInForegroundStationaryPowerMode = false
        deferredWeakDriftJump = nil

        isLocationLocked = false
        lockStreak = 0

        speedSamples.removeAll(keepingCapacity: true)
        self.mode = .unknown

        isTracking = true
        isPaused = false

        segments.removeAll()
        internalSegments.removeAll()
        internalSegmentsForMap.removeAll()
        resetSegmentSwitchState()

        latestRenderSegmentsForMap.removeAll()
        latestRenderUnifiedSegmentsForMap.removeAll()
        latestRenderLiveTailForMap.removeAll()
        renderSegmentsForMap.removeAll()
        renderUnifiedSegmentsForMap.removeAll()
        renderLiveTailForMap.removeAll()
        lastRenderCoordCount = 0
        lastRenderSegPointCount = 0
        pendingRenderWork?.cancel()
        pendingPublishWork?.cancel()

        needsRefreshAfterBackground = false
        isRealtimeRenderingEnabled = true
        trackingStartedAt = Date()
        accumulatedPausedDuration = 0
        currentPauseStartedAt = nil
        refreshDurations()
        droppedByAccuracyCount = 0
        droppedByJumpCount = 0
        droppedByStationaryCount = 0
        missingSegmentCount = 0

        resetOneEuro()
        resetLongStationaryReminderState()
        requestLongStationaryNotificationPermissionIfNeeded()
        flushPublishedState(force: true)

        // ✅ 根据模式选择启动方式
        if mode == .sport {
            startForegroundHighPowerSport()
        } else {
            startForegroundHighPowerDaily()
        }
        wasExplicitlyPaused = false  // ✅ 新旅程时重置
    }

    /// 切换追踪模式（旅程中也支持）
    /// - Note: 采用你选的策略 B：如果当前已经处于「前台静止省电态」，切换模式时不强制退出省电态，
    ///         等下一次检测到移动再按新模式回到高功耗。
    func setTrackingMode(_ newMode: TrackingMode) {
        guard trackingMode != newMode else { return }

        trackingMode = newMode

        // 立即应用新的参数配置（采点/平滑/静止阈值/持久化节奏等）
        applyModeConfig(TrackingModeConfig.config(for: newMode))

        // 旅程进行中且未暂停：根据前后台状态调整定位策略
        guard isTracking, !isPaused else { return }

        let state = UIApplication.shared.applicationState
        if state == .active {
            // ✅ 策略 B：如果已经在前台静止省电模式，保持不变（避免一切“抖动退出/重启定位”）
            if isInForegroundStationaryPowerMode { return }

            startRealtimeForCurrentTrackingMode()
        } else {
            // 后台策略取决于 trackingMode（sport 更高精度；daily 更省电）
            enterLowPowerBackgroundMode()
        }
    }

    /// 按当前 trackingMode 启动前台高功耗（sport / daily）
    private func startRealtimeForCurrentTrackingMode() {
        if hub.isUsingMock { return }
        hub.requestPermissionIfNeeded()
        if trackingMode == .sport {
            hub.startRealTime()
        } else {
            hub.startRealTimeDaily()
        }
    }

    
    /// 应用模式配置
    private func applyModeConfig(_ config: TrackingModeConfig) {
        foregroundMinDistance = config.foregroundMinDistance
        backgroundMinDistance = config.backgroundMinDistance
        maxAcceptableAccuracy = config.maxAcceptableAccuracy
        lockAccuracy = config.lockAccuracy
        
        stationaryBaseMinMoveMeters = config.stationaryMinMoveMeters
        stationarySpeedThreshold = config.stationarySpeedThreshold
        stationaryHoldSeconds = config.stationaryHoldSeconds
        
        gapSecondsThreshold = config.gapSecondsThreshold
        gapDistanceThreshold = config.gapDistanceThreshold
        applyTurnKeepAngles(baseTurnAngle: config.turnKeepAngle)
        
        // OneEuro配置
        oneEuroEnabled = config.enableOneEuroFilter
        oneEuroBaseMinCutoff = config.oneEuroMinCutoff
        if oneEuroEnabled {
            oneEuroLat.minCutoff = config.oneEuroMinCutoff
            oneEuroLat.beta = config.oneEuroBeta
            oneEuroLon.minCutoff = config.oneEuroMinCutoff
            oneEuroLon.beta = config.oneEuroBeta
        } else {
            resetOneEuro()
        }
    }

    private func applyTurnKeepAngles(baseTurnAngle: Double) {
        let fgBaseDefault = max(1, defaultTurnKeepAngleForeground[.unknown] ?? 20)
        let bgBaseDefault = max(1, defaultTurnKeepAngleBackground[.unknown] ?? 16)
        let fgScale = max(0.4, min(2.2, baseTurnAngle / fgBaseDefault))
        let bgScale = max(0.4, min(2.2, max(6, baseTurnAngle - 2) / bgBaseDefault))

        turnKeepAngleForeground = defaultTurnKeepAngleForeground.mapValues { value in
            guard value < 180 else { return value }
            return min(170, max(8, value * fgScale))
        }
        turnKeepAngleBackground = defaultTurnKeepAngleBackground.mapValues { value in
            guard value < 180 else { return value }
            return min(170, max(8, value * bgScale))
        }
    }
    private func startForegroundHighPowerSport() {
        if hub.isUsingMock { return }
        hub.requestPermissionIfNeeded()
        // 运动模式高功耗
        hub.startRealTime()
        
        isInForegroundStationaryPowerMode = false
        stationarySince = nil
    }
    
    /// 日常模式前台启动（稍低功耗）
    private func startForegroundHighPowerDaily() {
        if hub.isUsingMock { return }
        hub.requestPermissionIfNeeded()
        hub.startRealTimeDaily()
        
        isInForegroundStationaryPowerMode = false
        stationarySince = nil
    }


    func resumeJourney(startTime: Date? = nil, restoredPausedDuration: TimeInterval = 0) {
        isTracking = true
        isPaused = false
        userLocation = nil
        lastLocation = nil
        lastRecordedLocationForStationary = nil
        stationarySince = nil
        isInForegroundStationaryPowerMode = false
        resetLongStationaryReminderState()
        requestLongStationaryNotificationPermissionIfNeeded()
        trackingStartedAt = startTime ?? trackingStartedAt ?? Date()
        accumulatedPausedDuration = max(0, restoredPausedDuration)
        currentPauseStartedAt = nil
        refreshDurations()
        startForegroundHighPower()
    }

    func stopJourney() {
        // ✅ 结束 Live Activity（锁屏追踪卡片）
        endLiveActivity()
        isTracking = false
        isPaused = false

        // Return location manager to low-power mode when tracking stops.
        isInForegroundStationaryPowerMode = false
        stationarySince = nil
        deferredWeakDriftJump = nil
        if !hub.isUsingMock {
            hub.enterLowPower()
        }
        resetLongStationaryReminderState()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [longStationaryNotificationID])
        wasExplicitlyPaused = false  // ✅ 结束时重置
        refreshDurations()
    }

    func pauseJourney() {
        guard isTracking else { return }
        isPaused = true
        lastLocation = nil
        lastRecordedLocationForStationary = nil
        deferredWeakDriftJump = nil
        resetLongStationaryReminderState()
        wasExplicitlyPaused = true  // ✅ 标记为主动暂停
        if currentPauseStartedAt == nil {
            currentPauseStartedAt = Date()
        }
        refreshDurations()
        updateLiveActivity(memoriesCount: 0)
    }

    func resumeFromPause() {
        guard isTracking else { return }
        isPaused = false
        userLocation = nil
        lastLocation = nil
        lastRecordedLocationForStationary = nil
        deferredWeakDriftJump = nil
        resetLongStationaryReminderState()
        requestLongStationaryNotificationPermissionIfNeeded()
        wasExplicitlyPaused = false  // ✅ 恢复后清除标记
        if let pauseStart = currentPauseStartedAt {
            accumulatedPausedDuration += max(0, Date().timeIntervalSince(pauseStart))
            currentPauseStartedAt = nil
        }
        refreshDurations()
        updateLiveActivity(memoriesCount: 0)
    }

    func enterLowPowerBackgroundMode() {
        guard isTracking else { return }
        
        // ✅ 根据追踪模式选择后台策略
        if trackingMode == .sport {
            hub.enterBackgroundHighFidelity()  // 运动模式保持高精度
        } else {
            hub.enterBackgroundBalanced()  // 日常模式平衡模式，或者:
            // hub.enterBackgroundPowerSaving()  // 更省电
        }
    }

    /// MapView 进来自动对齐一次（你选的策略）
    func activateMapRenderingSurface() {
        setRealtimeRenderingEnabled(true)
        needsRefreshAfterBackground = false
        rebuildRenderCache(force: true)
    }

    /// MapView 离开时调用，避免不在屏幕时仍然做渲染相关更新
    func deactivateMapRenderingSurface() {
        setRealtimeRenderingEnabled(false)
    }

    /// 用户手点刷新（仍保留）
    func requestRefresh() {
        needsRefreshAfterBackground = false
        setRealtimeRenderingEnabled(true)
        rebuildRenderCache(force: true)
    }

    func setRealtimeRenderingEnabled(_ enabled: Bool) {
        if isRealtimeRenderingEnabled == enabled { return }
        isRealtimeRenderingEnabled = enabled
        if enabled { flushPublishedState(force: true) }
    }

    func syncFromJourneyIfNeeded(_ journey: JourneyRoute) {
        let ext = journey.displayRouteCoordinates.clCoords
        guard !ext.isEmpty else { return }

        // ✅ key fix: if TrackingService already has a live route, NEVER overwrite it with stale journeyRoute.
        let hasLiveInMemory = (!rawCoords.isEmpty) || (!internalSegments.isEmpty)
        if isTracking && journey.endTime == nil && hasLiveInMemory {
            rebuildRenderCache(force: true)
            return
        }

        // For historical/ended journeys we want deterministic playback from snapshot.
        if !isTracking || journey.endTime != nil {
            rawCoords = ext
        } else if rawCoords.isEmpty {
            rawCoords = ext
        }
        if totalDistance <= 0, journey.distance > 0 { totalDistance = journey.distance }
        if totalAscent <= 0, journey.elevationGain > 0 { totalAscent = journey.elevationGain }
        if totalDescent <= 0, journey.elevationLoss > 0 { totalDescent = journey.elevationLoss }

        if lastLocation == nil, let last = ext.last {
            lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
        }

        isLocationLocked = true

        internalSegments = [RouteSegment(id: UUID().uuidString, style: .solid, coords: ext)]
        rebuildInternalSegmentsForMapFromInternal()
        flushPublishedState(force: true)

        // ✅ do not reuse old filter state for playback
        resetOneEuro()

        rebuildRenderCache(force: true)
    }

    // MARK: - Map-ready conversion (single source of truth)

    private func convertForMap(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        // ✅ One gate only: country ISO2 (authoritative) -> apply GCJ offset.
        // We intentionally do NOT use a coarse bbox check here, to avoid false positives outside CN.
        if shouldApplyChinaOffset {
            return ChinaCoordinateTransform.wgs84ToGcj02(c)
        }
        return c
    }


    func mapReady(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        convertForMap(c)
    }

    // MARK: - Render cache builder

    private func shouldUpdateRenderCache(force: Bool) -> Bool {
        guard isRealtimeRenderingEnabled else { return false }
        if needsRefreshAfterBackground && !force { return false }
        return true
    }

    private func rebuildRenderCache(force: Bool) {
        guard shouldUpdateRenderCache(force: force) else { return }

        let coordCount = rawCoords.count
        let segPointCount = internalSegments.reduce(0) { $0 + $1.coords.count }

        if !force, coordCount == lastRenderCoordCount, segPointCount == lastRenderSegPointCount {
            return
        }

        pendingRenderWork?.cancel()

        let segsForMapSnapshot = internalSegmentsForMap
        let lastWGS = rawCoords.last
        let userWGS = userLocation?.coordinate
        let convert = self.convertForMap

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }

            let segsForMap: [RouteSegment] = self.mergeRenderableSegments(segsForMapSnapshot)
            let unifiedSegsForMap: [RenderRouteSegment] = self.asRenderRouteSegments(segsForMap)

            let tailForMap: [CLLocationCoordinate2D] = {
                guard let last = lastWGS else { return [] }
                guard let u = userWGS else { return [] }
                let d = CLLocation(latitude: u.latitude, longitude: u.longitude)
                    .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
                guard d >= 12 else { return [] }
                return [convert(last), convert(u)]
            }()

            Task { @MainActor in
                guard self.shouldUpdateRenderCache(force: force) else { return }
                self.latestRenderSegmentsForMap = segsForMap
                self.latestRenderUnifiedSegmentsForMap = unifiedSegsForMap
                self.latestRenderLiveTailForMap = tailForMap
                self.flushPublishedState(force: force)
                self.lastRenderCoordCount = coordCount
                self.lastRenderSegPointCount = segPointCount
            }
        }

        pendingRenderWork = work
        renderQueue.asyncAfter(deadline: .now() + (force ? 0 : renderDebounceInterval), execute: work)
    }

    private func mergeRenderableSegments(_ segments: [RouteSegment]) -> [RouteSegment] {
        guard !segments.isEmpty else { return [] }

        func isEffectivelySame(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
            CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < 2.0
        }

        var out: [RouteSegment] = []
        out.reserveCapacity(segments.count)

        for seg in segments {
            guard seg.coords.count >= 2 else { continue }

            if var last = out.last, last.style == seg.style {
                if let lastC = last.coords.last, let firstC = seg.coords.first, isEffectivelySame(lastC, firstC) {
                    last.coords.append(contentsOf: seg.coords.dropFirst())
                } else {
                    last.coords.append(contentsOf: seg.coords)
                }
                out[out.count - 1] = last
            } else {
                out.append(seg)
            }
        }

        return out
    }

    private func asRenderRouteSegments(_ segments: [RouteSegment]) -> [RenderRouteSegment] {
        segments.map { seg in
            RenderRouteSegment(
                id: seg.id,
                style: (seg.style == .dashed) ? .dashed : .solid,
                coords: seg.coords
            )
        }
    }

    // MARK: - Ingest (EXTREME: anti-spike turns + OneEuro)

    func ingest(_ loc: CLLocation) {
        // Always update "blue dot" states
        userLocation = loc
        lastHorizontalAccuracy = loc.horizontalAccuracy

        guard isTracking else { return }
        guard !isPaused else { return } // keep blue dot, stop recording
        if loc.horizontalAccuracy < 0 { return }

        evaluateLongStationaryReminder(with: loc)

        // Foreground/background knobs
        let isActive = UIApplication.shared.applicationState == .active
        let minD = isActive ? foregroundMinDistance : backgroundMinDistance
        let gapSec = isActive ? gapSecondsThreshold : backgroundGapSecondsThreshold
        let gapDist = isActive ? gapDistanceThreshold : backgroundGapDistanceThreshold

        // Accuracy bands
        let acc = loc.horizontalAccuracy
        let accuracyVeryBad = (acc >= accuracyBadThreshold)     // e.g. >= 120
        let accuracyWeak = (acc >= weakAccuracyThreshold)       // e.g. >= 35

        // =========================================================
        // 0) GPS lock stage: require stable accuracy before recording
        // =========================================================
        if !isLocationLocked {
            // If accuracy is terrible, don't progress lock streak
            if acc > maxAcceptableAccuracy {
                lockStreak = 0
                droppedByAccuracyCount += 1
                return
            }

            if acc <= lockAccuracy { lockStreak += 1 } else { lockStreak = 0 }
            if lockStreak < lockConsecutiveCount { return }

            isLocationLocked = true
            acceptedLocations.removeAll(keepingCapacity: true)
            acceptedLocations.append(loc)

            // ✅ lock point becomes base; safe to set lastLocation
            lastLocation = loc
            resetOneEuro() // start filter fresh at lock

            rawCoords.append(loc.coordinate)
            appendPointToInternalSegments(coord: loc.coordinate, at: loc.timestamp, preferredStyle: .solid)
            lastRecordedLocationForStationary = loc
            stationarySince = nil
            publishIfNeeded()
            rebuildRenderCache(force: false)
            return
        }

        // =========================================================
        // 1) Compute distance/time from last GOOD anchor
        // =========================================================
        guard let last = lastLocation else {
            lastLocation = loc
            resetOneEuro()
            rawCoords.append(loc.coordinate)
            appendPointToInternalSegments(coord: loc.coordinate, at: loc.timestamp, preferredStyle: .solid)
            lastRecordedLocationForStationary = loc
            stationarySince = nil
            publishIfNeeded()
            rebuildRenderCache(force: false)
            return
        }

        let d2d = loc.distance(from: last)
        let dt = max(0.001, loc.timestamp.timeIntervalSince(last.timestamp))
        let impliedSpeed = d2d / dt
        // iOS may report speed = -1 (unknown). Infer from displacement so mode tuning
        // does not treat unknown speed as stationary.
        let resolvedSpeed = max(0, (loc.speed >= 0) ? loc.speed : impliedSpeed)
        updateModeIfNeeded(now: loc.timestamp, speed: resolvedSpeed)

        // =========================================================
        // 1.5) Stationary jitter suppression + foreground power saving
        // =========================================================
        if let lastRec = (lastRecordedLocationForStationary ?? lastLocation) {
            let dRec = loc.distance(from: lastRec)
            let dtRec = max(0.001, loc.timestamp.timeIntervalSince(lastRec.timestamp))

            // iOS may provide speed = -1 (unknown). Infer if needed.
            let speedUsed: Double = {
                if loc.speed >= 0 { return loc.speed }
                return dRec / dtRec
            }()

            // Dynamic min-move: worse accuracy => larger threshold to avoid GPS drift scribbles.
            // Use a stronger multiplier so small GPS drift won't be recorded as movement.
            let dynamicMinMove = max(stationaryBaseMinMoveMeters, 0.9 * max(0, loc.horizontalAccuracy))
            let nearAnchorRadius = max(dynamicMinMove * 1.2, weakDriftReturnRadiusMeters)
            let driftConfirmDistance = max(dynamicMinMove * 1.4, weakDriftConfirmationDistanceMeters)

            let stationaryCandidate = (dRec < dynamicMinMove) && (speedUsed < stationarySpeedThreshold)
            let exitCandidate = (dRec >= dynamicMinMove * stationaryExitMoveMultiplier) || (speedUsed >= stationarySpeedThreshold * 1.5)

            if let deferred = deferredWeakDriftJump {
                let anchorDistance = loc.distance(from: deferred.anchor)
                let candidateDistance = loc.distance(from: deferred.candidate)
                let decisionAge = loc.timestamp.timeIntervalSince(deferred.candidate.timestamp)

                if anchorDistance <= nearAnchorRadius && decisionAge <= weakDriftDecisionWindow {
                    deferredWeakDriftJump = nil
                    droppedByJumpCount += 1
                    droppedByStationaryCount += 1
                    return
                }

                let confirmedMovement =
                    anchorDistance >= driftConfirmDistance &&
                    (
                        candidateDistance <= max(dynamicMinMove * 1.8, weakDriftConfirmationDistanceMeters) ||
                        speedUsed >= max(stationarySpeedThreshold * 2.4, 1.8) ||
                        !accuracyWeak ||
                        decisionAge > 45
                    )

                if confirmedMovement {
                    deferredWeakDriftJump = nil
                } else {
                    deferredWeakDriftJump = DeferredWeakDriftJump(anchor: deferred.anchor, candidate: loc)
                    droppedByStationaryCount += 1
                    return
                }
            }

            if stationaryCandidate {
                deferredWeakDriftJump = nil
                if stationarySince == nil {
                    stationarySince = loc.timestamp
                }

                // After holding still for a bit in foreground, switch to a lower-power foreground mode.
                let isActive = UIApplication.shared.applicationState == .active
                if isActive,
                   !isInForegroundStationaryPowerMode,
                   let since = stationarySince,
                   loc.timestamp.timeIntervalSince(since) >= stationaryHoldSeconds {
                    hub.enterForegroundStationary()
                    isInForegroundStationaryPowerMode = true
                }

                // Don't record a new route point while stationary.
                droppedByStationaryCount += 1
                return
            } else if shouldDeferWeakDriftJump(
                loc,
                anchor: lastRec,
                distanceFromAnchor: dRec,
                speedUsed: speedUsed,
                dynamicMinMove: dynamicMinMove,
                accuracyWeak: accuracyWeak
            ) {
                deferredWeakDriftJump = DeferredWeakDriftJump(anchor: lastRec, candidate: loc)
                droppedByStationaryCount += 1
                return
            } else if isInForegroundStationaryPowerMode && exitCandidate {
                // Movement resumed: switch back to high power for responsiveness.
                let isActive = UIApplication.shared.applicationState == .active
                if isActive {
                    startRealtimeForCurrentTrackingMode()
                }
                isInForegroundStationaryPowerMode = false
                stationarySince = nil
            } else if !stationaryCandidate {
                // Normal moving state
                stationarySince = nil
            }
        }

        // =========================================================
        // 2) Turn detection (use last two RECORDED coords)
        // =========================================================
        let turnThreshold = isActive
            ? (turnKeepAngleForeground[mode] ?? 18)
            : (turnKeepAngleBackground[mode] ?? 16)

        var keepBecauseTurn = false
        if turnThreshold < 180, rawCoords.count >= 2 {
            let last2 = rawCoords[rawCoords.count - 2]
            let last1 = rawCoords[rawCoords.count - 1]
            keepBecauseTurn = isTurn(last2: last2, last1: last1, new: loc.coordinate, thresholdDeg: turnThreshold)
        }

        // =========================================================
        // 3) Drift vs Migration vs Normal
        // =========================================================
        // Treat very long time gaps as "migration" only if distance is also meaningful.
        // This avoids creating dashed/missing segments when the user simply stayed still.
        let isMigrationCandidate: Bool =
            ((dt >= missingGapSecondsThreshold) && (d2d >= 500)) ||
            (d2d  >= missingGapDistanceThreshold)

        let isDriftLike: Bool =
            accuracyVeryBad &&
            (dt <= 30) &&
            (d2d >= dropJumpDistanceWhenAccuracyBad)

        // Drift-like: if NOT turning, drop
        if isDriftLike && !keepBecauseTurn {
            droppedByJumpCount += 1
            return
        }

        // Accuracy hard gate:
        // if too bad and not turning -> drop
        if acc > maxAcceptableAccuracy && !keepBecauseTurn {
            droppedByAccuracyCount += 1
            return
        }

        // Speed-based outlier drop (only when NOT migration candidate)
        if !isMigrationCandidate {
            if d2d > maxJumpDistance && impliedSpeed > maxPlausibleSpeed {
                if !keepBecauseTurn {
                    droppedByJumpCount += 1
                    return
                }
            }
        }

        // Gap-like -> dashed (be conservative: prefer solid unless we truly lost signal / jumped)
        var isGapLike = false

        // Hard gaps (time-only gaps should not create dashed segments if the user didn't move much)
        if dt >= gapSec && d2d >= max(25, minD * 2.0) { isGapLike = true }
        if d2d  >= gapDist { isGapLike = true }

        // Weak accuracy alone should NOT create dashed "confetti" in cities.
        // Only treat as gap if it's also temporally/spatially suspicious.
        if accuracyWeak && (dt >= 8.0 || d2d >= 200.0) { isGapLike = true }

        // Drift-like turns: keep solid for small hops; only dashed when it's a larger uncertain move.
        if isDriftLike && (dt >= 6.0 || d2d >= 80.0) { isGapLike = true }

        // Missing segment -> single dashed connection
        var isMissingSegment = false
        var missingFromCoord: CLLocationCoordinate2D? = nil
        isMissingSegment = (d2d >= missingGapDistanceThreshold) || isMigrationCandidate
        if isMissingSegment {
            isGapLike = true
            missingFromCoord = rawCoords.last
            missingSegmentCount += 1
        }

        // =========================================================
        // 4) Sample gate: min distance unless turn keep
        //    when weak accuracy, allow a point every few seconds to preserve curvature
        // =========================================================
        if d2d < minD && !keepBecauseTurn {
            if accuracyWeak && dt >= 3.0 {
                // When accuracy is weak we allow an occasional point so moving curvature doesn't flatten,
                // but ONLY if we are likely moving (otherwise GPS drift creates scribble lines).
                let speedGate = max(impliedSpeed, resolvedSpeed)
                let likelyMoving = (speedGate >= weakAccuracyBypassMinSpeed) || (d2d >= weakAccuracyBypassMinDistance)
                if !likelyMoving { return }
                // allow pass
            } else {
                return
            }
        }

        // =========================================================
        // 5) Distance accumulation (2D horizontal distance)
        //    don't add nonsense on very bad accuracy unless migration
        //    Daily mode: count missing (dashed) segment mileage as requested.
        // =========================================================
        let shouldAccumulateDistance: Bool = {
            guard (!accuracyVeryBad || isMigrationCandidate) else { return false }
            if isMissingSegment {
                return trackingMode == .daily
            }
            return true
        }()

        if shouldAccumulateDistance {
            totalDistance += d2d
            accumulateElevation(from: last, to: loc)
        }

        // =========================================================
        // 6) Filtering (enabled by mode config) — NEVER on turns
        // =========================================================
        let shouldFilter: Bool = {
            if !isActive { return false }
            if keepBecauseTurn { return false }

            guard oneEuroEnabled else { return false }
            switch mode {
            case .walk, .run, .bike:
                return true
            default:
                return false
            }
        }()

        acceptedLocations.append(loc)

        let outCoord: CLLocationCoordinate2D = {
            guard shouldFilter else { return loc.coordinate }
            return oneEuroFilteredCoord(loc)
        }()

        // =========================================================
        // 7) Anchor update WITHOUT poisoning:
        //    very bad accuracy points should NOT become lastLocation
        // =========================================================
        if !accuracyVeryBad {
            lastLocation = loc
        }

        // =========================================================
        // 8) Append point / segment
        // =========================================================
        rawCoords.append(outCoord)

        if isMissingSegment, let from = missingFromCoord {
            appendMissingConnectionSegment(from: from, to: outCoord, at: loc.timestamp)
        } else {
            let style: SegmentStyle = isGapLike ? .dashed : .solid
            appendPointToInternalSegments(coord: outCoord, at: loc.timestamp, preferredStyle: style)
        }

        // update stationary reference anchor only when we actually record a point
        lastRecordedLocationForStationary = loc
        stationarySince = nil

        publishIfNeeded()
        refreshDurations(now: loc.timestamp)
        rebuildRenderCache(force: false)
    }

    private func shouldDeferWeakDriftJump(
        _ loc: CLLocation,
        anchor: CLLocation,
        distanceFromAnchor: CLLocationDistance,
        speedUsed: CLLocationSpeed,
        dynamicMinMove: CLLocationDistance,
        accuracyWeak: Bool
    ) -> Bool {
        guard accuracyWeak else { return false }
        guard stationarySince != nil || isInForegroundStationaryPowerMode else { return false }

        let decisionAge = loc.timestamp.timeIntervalSince(anchor.timestamp)
        guard decisionAge <= weakDriftDecisionWindow else { return false }

        let deferDistance = max(
            dynamicMinMove * stationaryExitMoveMultiplier,
            weakAccuracyBypassMinDistance * 2.6,
            weakDriftDeferMinDistanceMeters
        )
        guard distanceFromAnchor >= deferDistance else { return false }

        let lowConfidenceSpeed = speedUsed < max(stationarySpeedThreshold * 2.3, 1.8)
        return lowConfidenceSpeed
    }

    func elapsedDuration(at now: Date = Date()) -> TimeInterval {
        guard let start = trackingStartedAt else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    func pausedDuration(at now: Date = Date()) -> TimeInterval {
        var paused = max(0, accumulatedPausedDuration)
        if let pauseStart = currentPauseStartedAt {
            paused += max(0, now.timeIntervalSince(pauseStart))
        }
        return paused
    }

    func movingDuration(at now: Date = Date()) -> TimeInterval {
        let elapsed = elapsedDuration(at: now)
        return max(0, elapsed - pausedDuration(at: now))
    }

    func refreshDurations(now: Date = Date()) {
        elapsedSeconds = Int(elapsedDuration(at: now))
        pausedSeconds = Int(pausedDuration(at: now))
        movingSeconds = Int(movingDuration(at: now))
    }

    private func resetLongStationaryReminderState() {
        longStationaryAnchorLocation = nil
        longStationaryAnchorTime = nil
    }

    private func requestLongStationaryNotificationPermissionIfNeeded() {
        guard AppSettings.isLongStationaryReminderEnabled else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: longStationaryNotificationPermissionAskedKey) else { return }
        defaults.set(true, forKey: longStationaryNotificationPermissionAskedKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func evaluateLongStationaryReminder(with location: CLLocation) {
        guard AppSettings.isLongStationaryReminderEnabled else {
            resetLongStationaryReminderState()
            return
        }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 120 else { return }

        if longStationaryAnchorLocation == nil || longStationaryAnchorTime == nil {
            longStationaryAnchorLocation = location
            longStationaryAnchorTime = location.timestamp
            return
        }

        guard let anchor = longStationaryAnchorLocation, let anchorTime = longStationaryAnchorTime else { return }
        guard location.timestamp >= anchorTime else {
            longStationaryAnchorLocation = location
            longStationaryAnchorTime = location.timestamp
            return
        }

        let elapsed = location.timestamp.timeIntervalSince(anchorTime)
        if elapsed < longStationaryWindow { return }

        let startToEnd = location.distance(from: anchor)
        if startToEnd <= longStationaryThresholdMeters {
            scheduleLongStationaryReminderNotification()
        }

        // Whether reminded or not, restart a new 1-hour window from current point.
        longStationaryAnchorLocation = location
        longStationaryAnchorTime = location.timestamp
    }

    private func scheduleLongStationaryReminderNotification() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [longStationaryNotificationID] settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = L10n.t("long_stationary_reminder_title")
            content.body = L10n.t("long_stationary_reminder_body")
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: longStationaryNotificationID,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            center.removePendingNotificationRequests(withIdentifiers: [longStationaryNotificationID])
            center.add(request)
        }
    }

    private func appendMissingConnectionSegment(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, at t: Date) {
        let id = UUID().uuidString
        internalSegments.append(RouteSegment(id: id, style: .dashed, coords: [from, to]))
        internalSegmentsForMap.append(RouteSegment(id: id, style: .dashed, coords: [convertForMap(from), convertForMap(to)]))
        resetSegmentSwitchState()
    }

    private func publishIfNeeded() {
        // ✅ 更新 Live Activity（锁屏追踪卡片）
        updateLiveActivity(memoriesCount: 0)
        flushPublishedState(force: false)
    }

    private func flushPublishedState(force: Bool) {
        pendingPublishWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.coords = self.rawCoords
            if self.isRealtimeRenderingEnabled {
                self.segments = self.internalSegments
            }
            self.renderSegmentsForMap = self.latestRenderSegmentsForMap
            self.renderUnifiedSegmentsForMap = self.latestRenderUnifiedSegmentsForMap
            self.renderLiveTailForMap = self.latestRenderLiveTailForMap
        }
        pendingPublishWork = work
        if force {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + publishDebounceInterval, execute: work)
        }
    }

    // MARK: - Turn helpers

    private func bearing(_ p1: CLLocationCoordinate2D, _ p2: CLLocationCoordinate2D) -> Double {
        let lat1 = p1.latitude * .pi / 180
        let lat2 = p2.latitude * .pi / 180
        let dLon = (p2.longitude - p1.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var brng = atan2(y, x) * 180 / .pi
        if brng < 0 { brng += 360 }
        return brng
    }

    private func isTurn(last2: CLLocationCoordinate2D, last1: CLLocationCoordinate2D, new: CLLocationCoordinate2D, thresholdDeg: Double) -> Bool {
        let b1 = bearing(last2, last1)
        let b2 = bearing(last1, new)
        var delta = abs(b2 - b1)
        if delta > 180 { delta = 360 - delta }
        return delta >= thresholdDeg
    }

    // MARK: - Smoothing (legacy, kept but no longer used for walk/run when OneEuro enabled)

    private func smoothedCoordinate(for newCoord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let n = min(smoothingWindow, acceptedLocations.count)
        guard n > 1 else { return newCoord }

        let slice = acceptedLocations.suffix(n)
        let lat = slice.map { $0.coordinate.latitude }.reduce(0, +) / Double(n)
        let lon = slice.map { $0.coordinate.longitude }.reduce(0, +) / Double(n)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Segments builder

    private func resetSegmentSwitchState() {
        pendingStyle = nil
        pendingStyleStartAt = .distantPast
        pendingStylePointCount = 0
    }

    private func appendPointToInternalSegments(coord: CLLocationCoordinate2D, at t: Date, preferredStyle: SegmentStyle) {
        let mapCoord = convertForMap(coord)

        if internalSegments.isEmpty {
            let id = UUID().uuidString
            internalSegments = [RouteSegment(id: id, style: preferredStyle, coords: [coord])]
            internalSegmentsForMap = [RouteSegment(id: id, style: preferredStyle, coords: [mapCoord])]
            resetSegmentSwitchState()
            return
        }

        // append to last segment if style unchanged
        if internalSegments[internalSegments.count - 1].style == preferredStyle {
            internalSegments[internalSegments.count - 1].coords.append(coord)
            internalSegmentsForMap[internalSegmentsForMap.count - 1].coords.append(mapCoord)
            return
        }

        // style changed, require confirmation before switching
        if pendingStyle != preferredStyle {
            pendingStyle = preferredStyle
            pendingStyleStartAt = t
            pendingStylePointCount = 1
            internalSegments[internalSegments.count - 1].coords.append(coord)
            internalSegmentsForMap[internalSegmentsForMap.count - 1].coords.append(mapCoord)
            return
        }

        pendingStylePointCount += 1
        let pendingSeconds = t.timeIntervalSince(pendingStyleStartAt)
        let shouldConfirm = (pendingSeconds >= segmentConfirmMinSeconds) || (pendingStylePointCount >= segmentConfirmMinPoints)

        guard shouldConfirm else {
            internalSegments[internalSegments.count - 1].coords.append(coord)
            internalSegmentsForMap[internalSegmentsForMap.count - 1].coords.append(mapCoord)
            return
        }

        let id = UUID().uuidString
        internalSegments.append(RouteSegment(id: id, style: preferredStyle, coords: [coord]))
        internalSegmentsForMap.append(RouteSegment(id: id, style: preferredStyle, coords: [mapCoord]))
        resetSegmentSwitchState()
    }

    // MARK: - Power mode helpers

    private func startForegroundHighPower() {
        if hub.isUsingMock { return }
        hub.requestPermissionIfNeeded()
        startRealtimeForCurrentTrackingMode()

        // ensure we're not stuck in stationary power mode when we explicitly request high power
        isInForegroundStationaryPowerMode = false
        stationarySince = nil
    }

    // MARK: - Elevation helpers

    /// Returns altitude delta in meters from `from` to `to` if both points have usable vertical accuracy.
    /// Otherwise returns 0 so distance accumulation stays stable.
    private func elevationDeltaMeters(from: CLLocation, to: CLLocation) -> Double {
        guard from.verticalAccuracy > 0, to.verticalAccuracy > 0 else { return 0 }
        guard from.verticalAccuracy <= maxAcceptableVerticalAccuracy,
              to.verticalAccuracy <= maxAcceptableVerticalAccuracy else { return 0 }
        return to.altitude - from.altitude
    }

    /// Accumulates positive/negative elevation changes with a small deadzone to avoid noise.
    private func accumulateElevation(from: CLLocation, to: CLLocation) {
        let dz = elevationDeltaMeters(from: from, to: to)
        guard abs(dz) >= minElevationDeltaToCount else { return }
        if dz > 0 {
            totalAscent += dz
        } else {
            totalDescent += abs(dz)
        }
    }

    // MARK: - Mode inference
    private func updateModeIfNeeded(now: Date, speed: Double) {
        speedSamples.append((now, speed))
        speedSamples = speedSamples.filter { now.timeIntervalSince($0.t) <= modeWindowSeconds }
        guard speedSamples.count >= 4 else { return }

        if now.timeIntervalSince(lastModeChangeAt) < modeCooldownSeconds { return }

        let speeds = speedSamples.map(\.v).sorted()
        let median = speeds[speeds.count / 2]

        let newMode: TravelMode
        switch median {
        case 0..<2.2:    newMode = .walk
        case 2.2..<5.0:  newMode = .run
        case 5.0..<16.0: newMode = .transit
        case 16..<30.0:  newMode = .bike
        case 30..<55.0:  newMode = .drive
        case 55..<90.0:  newMode = .motorcycle
        default:         newMode = .flight
        }

        guard newMode != mode else { return }
        mode = newMode
        lastModeChangeAt = now

        // ✅ 日常模式下，根据检测到的交通方式动态调整参数
        if trackingMode == .daily {
            let adjustedConfig = modeConfig.adjusted(for: newMode)
            applyModeConfig(adjustedConfig)
        }
        // 运动模式不做动态调整，保持高精度
    }
}
