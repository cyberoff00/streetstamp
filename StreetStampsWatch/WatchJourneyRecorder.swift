import Foundation
import CoreLocation
import HealthKit

enum WatchRecordState: String, Codable {
    case idle
    case recording
    case paused
}

final class WatchJourneyRecorder: NSObject, ObservableObject {
    @Published private(set) var state: WatchRecordState = .idle
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var pointCount: Int = 0
    @Published private(set) var statusText: String = ""
    @Published var inactivityAlertPresented: Bool = false
    @Published private(set) var inactivityAlertMessage: String = ""

    private enum PendingStartMode {
        case none
        case newJourney
        case recover
    }

    private struct PersistedRecorderState: Codable {
        var journeyID: String
        var startedAt: Date
        var recordingBeganAt: Date?
        var state: WatchRecordState
        var distanceMeters: Double
        var recordedPoints: [WatchJourneyPoint]
        var pendingPoints: [WatchJourneyPoint]
        var lastAcceptedPoint: WatchJourneyPoint?
        var savedAt: Date
    }

    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    private var journeyID: String?
    private var startedAt: Date?
    private var recordingBeganAt: Date?

    private var recordedPoints: [WatchJourneyPoint] = []
    private var pendingPoints: [WatchJourneyPoint] = []

    private var lastAcceptedLocation: CLLocation?
    private var lastProgressSentAt: Date = .distantPast
    private var lastBoundaryCheckAt: Date = .distantPast
    private var lastInactivityReminderAt: Date = .distantPast
    private var inactivitySuppressedUntil: Date = .distantPast

    private var pendingStartMode: PendingStartMode = .none
    private var isRecoveringFromDisk = false
    private var lastStatePersistedAt: Date = .distantPast
    private var lastLocationErrorAt: Date = .distantPast

    private let minMoveMeters: Double = 5
    private let minSecondsBetweenSamples: TimeInterval = 4
    private let firstFixMaxAccuracyMeters: Double = 65
    private let stationarySpeedThreshold: Double = 0.45
    private let weakAccuracyThresholdMeters: Double = 55
    private let weakAccuracyMinSpeed: Double = 0.9
    private let weakAccuracyMinDistance: Double = 18
    private let maxPlausibleSpeedMetersPerSecond: Double = 12
    private let maxJumpDistanceMeters: Double = 140
    private let progressBatchSize: Int = 8
    private let progressFlushSeconds: TimeInterval = 10
    private let endedChunkPointSize: Int = 120
    private let maxSegmentPointCount: Int = 30_000
    private let maxRecordingDuration: TimeInterval = 24 * 3600
    private let lowMovementWindow: TimeInterval = 60 * 60
    private let lowMovementThresholdMeters: Double = 100
    private let lowMovementMaxAccuracyMeters: Double = 100
    private let lowMovementReminderCooldown: TimeInterval = 60 * 60
    private let lowMovementReminderSnooze: TimeInterval = 60 * 60
    private let boundaryCheckInterval: TimeInterval = 20

    private let stateSaveInterval: TimeInterval = 8
    private var usesWorkoutSession: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.distanceFilter = kCLDistanceFilterNone

        restoreStateIfPossible()
        #if targetEnvironment(simulator)
        if state != .idle {
            resetToIdle(clearPersisted: true)
        }
        #endif
        recoverRecordingIfNeeded()
    }

    func start() {
        guard state == .idle else { return }

        let auth = locationManager.authorizationStatus
        switch auth {
        case .authorizedAlways, .authorizedWhenInUse:
            requestWorkoutAuthorizationAndStart(isRecovery: false)
        case .notDetermined:
            pendingStartMode = .newJourney
            statusText = "请先允许定位权限"
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            statusText = "请先允许手表定位权限"
        @unknown default:
            statusText = "定位权限状态未知"
        }
    }

    func pause() {
        guard state == .recording else { return }
        clearInactivityAlert()

        state = .paused
        statusText = "已暂停"
        locationManager.stopUpdatingLocation()
        if usesWorkoutSession {
            workoutSession?.pause()
        }

        flushProgressIfNeeded(force: true)
        sendEvent(.paused, points: [])
        persistState(force: true)
    }

    func resume() {
        guard state == .paused else { return }
        clearInactivityAlert()

        guard let startedAt else {
            statusText = "恢复失败，请重新开始"
            resetToIdle(clearPersisted: true)
            return
        }

        if usesWorkoutSession {
            do {
                try startWorkoutSessionIfNeeded(startAt: startedAt)
            } catch {
                statusText = "恢复失败: \(error.localizedDescription)"
                return
            }
        }

        state = .recording
        statusText = "录制中"
        if usesWorkoutSession {
            workoutSession?.resume()
        }
        locationManager.startUpdatingLocation()

        flushProgressIfNeeded(force: true)
        sendEvent(.resumed, points: [])
        persistState(force: true)
    }

    func end() {
        guard state != .idle else { return }
        clearInactivityAlert()

        locationManager.stopUpdatingLocation()
        flushProgressIfNeeded(force: true)

        let finalPoints = recordedPoints
        sendEndedInChunks(finalPoints, endedAt: Date())
        endWorkoutSession()

        statusText = "已结束，等待手机同步"
        resetToIdle(clearPersisted: true)
    }

    func elapsedText(now: Date = Date()) -> String {
        guard let startedAt else { return "00:00" }

        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60

        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    func handleTimerTick(now: Date = Date()) {
        guard state == .recording else { return }
        guard now.timeIntervalSince(lastBoundaryCheckAt) >= boundaryCheckInterval else { return }
        lastBoundaryCheckAt = now

        if shouldAutoEndForDuration(now: now) {
            autoEndDueToDuration(now: now)
            return
        }

        maybePromptLowMovement(now: now)
    }

    func continueAfterInactivityAlert() {
        inactivityAlertPresented = false
        inactivityAlertMessage = ""
        statusText = "继续录制中"
    }

    func pauseFromInactivityAlert() {
        inactivityAlertPresented = false
        inactivityAlertMessage = ""
        pause()
    }

    func snoozeInactivityAlert() {
        inactivityAlertPresented = false
        inactivityAlertMessage = ""
        inactivitySuppressedUntil = Date().addingTimeInterval(lowMovementReminderSnooze)
        statusText = "30分钟后再提醒"
    }

    private func recoverRecordingIfNeeded() {
        guard state == .recording,
              journeyID != nil,
              startedAt != nil
        else { return }

        isRecoveringFromDisk = true
        statusText = "恢复录制中..."

        let auth = locationManager.authorizationStatus
        switch auth {
        case .authorizedAlways, .authorizedWhenInUse:
            requestWorkoutAuthorizationAndStart(isRecovery: true)
        case .notDetermined:
            pendingStartMode = .recover
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            statusText = "已恢复记录，请先允许定位后继续"
            state = .paused
            persistState(force: true)
        @unknown default:
            statusText = "恢复失败，权限状态未知"
            state = .paused
            persistState(force: true)
        }
    }

    private func requestWorkoutAuthorizationAndStart(isRecovery: Bool) {
        guard usesWorkoutSession else {
            if isRecovery {
                resumeRecoveredSession()
            } else {
                beginNewJourneySession()
            }
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            statusText = "当前设备不支持健康数据"
            if !isRecovery { resetToIdle(clearPersisted: true) }
            return
        }

        let writeTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: writeTypes, read: []) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.statusText = "健康权限失败: \(error.localizedDescription)"
                    if !isRecovery {
                        self.resetToIdle(clearPersisted: true)
                    }
                    return
                }

                guard success else {
                    self.statusText = "请允许健康权限后再开始"
                    if !isRecovery {
                        self.resetToIdle(clearPersisted: true)
                    }
                    return
                }

                if isRecovery {
                    self.resumeRecoveredSession()
                } else {
                    self.beginNewJourneySession()
                }
            }
        }
    }

    private func beginNewJourneySession() {
        journeyID = UUID().uuidString
        startedAt = Date()
        recordingBeganAt = startedAt
        state = .recording
        distanceMeters = 0
        pointCount = 0
        statusText = "录制中"
        clearInactivityAlert()
        lastInactivityReminderAt = .distantPast
        inactivitySuppressedUntil = .distantPast
        lastBoundaryCheckAt = .distantPast

        recordedPoints.removeAll(keepingCapacity: true)
        pendingPoints.removeAll(keepingCapacity: true)
        lastAcceptedLocation = nil
        lastProgressSentAt = .distantPast

        if usesWorkoutSession {
            guard let startedAt else { return }
            do {
                try startWorkoutSessionIfNeeded(startAt: startedAt)
            } catch {
                statusText = "无法启动后台追踪: \(error.localizedDescription)"
                resetToIdle(clearPersisted: true)
                return
            }
        }

        locationManager.startUpdatingLocation()
        sendEvent(.started, points: [])
        persistState(force: true)
    }

    private func resumeRecoveredSession() {
        guard let startedAt else {
            resetToIdle(clearPersisted: true)
            return
        }
        if recordingBeganAt == nil {
            recordingBeganAt = startedAt
        }

        if usesWorkoutSession {
            do {
                try startWorkoutSessionIfNeeded(startAt: startedAt)
            } catch {
                statusText = "恢复后台会话失败: \(error.localizedDescription)"
                state = .paused
                persistState(force: true)
                return
            }
        }

        state = .recording
        statusText = "录制中"
        isRecoveringFromDisk = false
        clearInactivityAlert()
        locationManager.startUpdatingLocation()

        flushProgressIfNeeded(force: true)
        sendEvent(.resumed, points: [])
        persistState(force: true)
    }

    private func startWorkoutSessionIfNeeded(startAt: Date) throws {
        if workoutSession != nil { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .walking
        config.locationType = .outdoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

        session.delegate = self
        builder.delegate = self

        session.startActivity(with: startAt)
        builder.beginCollection(withStart: startAt) { _, _ in }

        workoutSession = session
        workoutBuilder = builder
    }

    private func endWorkoutSession() {
        guard usesWorkoutSession else {
            workoutSession = nil
            workoutBuilder = nil
            return
        }

        guard let session = workoutSession else { return }
        let builder = workoutBuilder

        session.end()
        if let builder {
            builder.endCollection(withEnd: Date()) { _, _ in
                builder.discardWorkout()
            }
        }

        workoutSession = nil
        workoutBuilder = nil
    }

    private func flushProgressIfNeeded(force: Bool) {
        guard !pendingPoints.isEmpty else { return }

        let shouldFlush = force
            || pendingPoints.count >= progressBatchSize
            || Date().timeIntervalSince(lastProgressSentAt) >= progressFlushSeconds

        guard shouldFlush else { return }

        let batch = pendingPoints
        pendingPoints.removeAll(keepingCapacity: true)
        lastProgressSentAt = Date()
        sendEvent(.progress, points: batch)
        persistState(force: true)
    }

    private func accept(_ location: CLLocation) {
        guard state == .recording else { return }
        let accuracy = location.horizontalAccuracy
        guard accuracy >= 0, accuracy <= 120 else { return }

        if let last = lastAcceptedLocation {
            let deltaDistance = location.distance(from: last)
            let deltaTime = max(0.001, location.timestamp.timeIntervalSince(last.timestamp))
            let impliedSpeed = deltaDistance / deltaTime
            let speedUsed: Double = {
                if location.speed >= 0 { return location.speed }
                return impliedSpeed
            }()

            if deltaDistance < minMoveMeters && deltaTime < minSecondsBetweenSamples {
                return
            }

            let dynamicMinMove = max(minMoveMeters, 0.85 * max(0, accuracy))
            let stationaryCandidate = deltaDistance < dynamicMinMove && speedUsed < stationarySpeedThreshold
            if stationaryCandidate {
                return
            }

            let weakAccuracy = accuracy >= weakAccuracyThresholdMeters
            if weakAccuracy && speedUsed < weakAccuracyMinSpeed && deltaDistance < weakAccuracyMinDistance {
                return
            }

            if deltaDistance > maxJumpDistanceMeters && impliedSpeed > maxPlausibleSpeedMetersPerSecond {
                return
            }

            if deltaDistance.isFinite, deltaDistance >= 0 {
                distanceMeters += deltaDistance
            }
        } else {
            // Require a reasonably good first fix so the initial anchor is not a noisy point.
            guard accuracy <= firstFixMaxAccuracyMeters else { return }
        }

        let point = WatchJourneyPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            altitude: location.altitude
        )

        guard point.isValidCoordinate else { return }

        lastAcceptedLocation = point.asLocation
        recordedPoints.append(point)
        pendingPoints.append(point)
        pointCount = recordedPoints.count

        if pointCount >= maxSegmentPointCount {
            rotateSegmentDueToPointLimit(at: point.timestamp)
            return
        }

        if shouldAutoEndForDuration(now: point.timestamp) {
            autoEndDueToDuration(now: point.timestamp)
            return
        }

        flushProgressIfNeeded(force: false)
        persistStateIfNeededAfterPointAppend()
        maybePromptLowMovement(now: point.timestamp)
    }

    private func sendEvent(_ event: WatchJourneyEvent, points: [WatchJourneyPoint], endedAt: Date? = nil) {
        guard let journeyID else { return }

        let envelope = WatchJourneyEnvelope(
            journeyID: journeyID,
            event: event,
            startedAt: startedAt,
            endedAt: endedAt,
            trackingModeRaw: "sport",
            points: points,
            totalPointCount: nil,
            chunkIndex: nil,
            chunkCount: nil
        )
        WatchConnectivityTransport.shared.send(envelope)
    }

    private func sendEndedInChunks(_ points: [WatchJourneyPoint], endedAt: Date) {
        guard let journeyID else { return }

        let uniqueTotal = uniquePointCount(points)
        let chunks = points.chunked(size: endedChunkPointSize)

        if chunks.isEmpty {
            let envelope = WatchJourneyEnvelope(
                journeyID: journeyID,
                event: .ended,
                startedAt: startedAt,
                endedAt: endedAt,
                trackingModeRaw: "sport",
                points: [],
                totalPointCount: 0,
                chunkIndex: 1,
                chunkCount: 1
            )
            WatchConnectivityTransport.shared.send(envelope)
            return
        }

        let chunkCount = chunks.count
        for (index, chunk) in chunks.enumerated() {
            let isLast = index == chunkCount - 1
            let envelope = WatchJourneyEnvelope(
                journeyID: journeyID,
                event: .ended,
                startedAt: startedAt,
                endedAt: isLast ? endedAt : nil,
                trackingModeRaw: "sport",
                points: chunk,
                totalPointCount: uniqueTotal,
                chunkIndex: index + 1,
                chunkCount: chunkCount
            )
            WatchConnectivityTransport.shared.send(envelope)
        }
    }

    private func uniquePointCount(_ points: [WatchJourneyPoint]) -> Int {
        guard !points.isEmpty else { return 0 }
        var keys = Set<String>()
        keys.reserveCapacity(points.count)

        for point in points {
            let ms = Int((point.timestamp.timeIntervalSince1970 * 1000).rounded())
            let lat = Int((point.latitude * 1_000_000).rounded())
            let lon = Int((point.longitude * 1_000_000).rounded())
            keys.insert("\(ms)-\(lat)-\(lon)")
        }

        return keys.count
    }

    private func rotateSegmentDueToPointLimit(at date: Date) {
        guard state == .recording else { return }
        guard !recordedPoints.isEmpty else { return }

        flushProgressIfNeeded(force: true)
        sendEndedInChunks(recordedPoints, endedAt: date)

        journeyID = UUID().uuidString
        startedAt = date
        distanceMeters = 0
        pointCount = 0
        recordedPoints.removeAll(keepingCapacity: true)
        pendingPoints.removeAll(keepingCapacity: true)
        lastAcceptedLocation = nil
        lastProgressSentAt = .distantPast
        sendEvent(.started, points: [])
        persistState(force: true)
        statusText = "已自动分段继续记录"
    }

    private func shouldAutoEndForDuration(now: Date) -> Bool {
        guard let recordingBeganAt else { return false }
        return now.timeIntervalSince(recordingBeganAt) >= maxRecordingDuration
    }

    private func autoEndDueToDuration(now: Date) {
        guard state == .recording else { return }

        clearInactivityAlert()
        locationManager.stopUpdatingLocation()
        flushProgressIfNeeded(force: true)
        sendEndedInChunks(recordedPoints, endedAt: now)
        endWorkoutSession()
        resetToIdle(clearPersisted: true)
        statusText = "已达到24小时上限，自动结束"
    }

    private func maybePromptLowMovement(now: Date) {
        guard state == .recording else { return }
        guard !inactivityAlertPresented else { return }
        guard now >= inactivitySuppressedUntil else { return }
        guard now.timeIntervalSince(lastInactivityReminderAt) >= lowMovementReminderCooldown else { return }

        let windowStart = now.addingTimeInterval(-lowMovementWindow)
        let candidates = recordedPoints.filter {
            $0.timestamp >= windowStart
            && $0.horizontalAccuracy >= 0
            && $0.horizontalAccuracy <= lowMovementMaxAccuracyMeters
        }

        guard let first = candidates.first,
              let last = candidates.last
        else { return }

        guard last.timestamp.timeIntervalSince(first.timestamp) >= lowMovementWindow else { return }

        let startToEnd = first.asLocation.distance(from: last.asLocation)
        guard startToEnd < lowMovementThresholdMeters else { return }

        guard let diagonal = boundsDiagonalDistance(candidates),
              diagonal < lowMovementThresholdMeters
        else { return }

        lastInactivityReminderAt = now
        inactivityAlertMessage = "近60分钟首尾位移不足100m，是否暂停？"
        inactivityAlertPresented = true
        statusText = "低位移提醒"
    }

    private func boundsDiagonalDistance(_ points: [WatchJourneyPoint]) -> Double? {
        guard !points.isEmpty else { return nil }

        var minLat = points[0].latitude
        var maxLat = points[0].latitude
        var minLon = points[0].longitude
        var maxLon = points[0].longitude

        for point in points.dropFirst() {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }

        let a = CLLocation(latitude: minLat, longitude: minLon)
        let b = CLLocation(latitude: maxLat, longitude: maxLon)
        return b.distance(from: a)
    }

    private func clearInactivityAlert() {
        inactivityAlertPresented = false
        inactivityAlertMessage = ""
    }

    private func persistStateIfNeededAfterPointAppend() {
        let now = Date()
        if pointCount % 5 == 0 || now.timeIntervalSince(lastStatePersistedAt) >= stateSaveInterval {
            persistState(force: true)
        }
    }

    private func persistState(force: Bool) {
        guard state != .idle,
              let journeyID,
              let startedAt
        else { return }

        if !force,
           Date().timeIntervalSince(lastStatePersistedAt) < stateSaveInterval {
            return
        }

        let snapshot = PersistedRecorderState(
            journeyID: journeyID,
            startedAt: startedAt,
            recordingBeganAt: recordingBeganAt,
            state: state,
            distanceMeters: distanceMeters,
            recordedPoints: recordedPoints,
            pendingPoints: pendingPoints,
            lastAcceptedPoint: lastAcceptedLocation.map { WatchJourneyPoint(from: $0) },
            savedAt: Date()
        )

        guard let url = persistedStateURL(),
              let data = try? Self.stateEncoder.encode(snapshot)
        else { return }

        try? data.write(to: url, options: .atomic)
        lastStatePersistedAt = Date()
    }

    private func restoreStateIfPossible() {
        guard let url = persistedStateURL(),
              let data = try? Data(contentsOf: url),
              let snapshot = try? Self.stateDecoder.decode(PersistedRecorderState.self, from: data)
        else { return }

        journeyID = snapshot.journeyID
        startedAt = snapshot.startedAt
        recordingBeganAt = snapshot.recordingBeganAt ?? snapshot.startedAt
        state = snapshot.state
        distanceMeters = max(0, snapshot.distanceMeters)
        recordedPoints = snapshot.recordedPoints
        pendingPoints = snapshot.pendingPoints
        pointCount = snapshot.recordedPoints.count
        lastAcceptedLocation = snapshot.lastAcceptedPoint?.asLocation
        lastProgressSentAt = .distantPast
        lastBoundaryCheckAt = .distantPast
        lastInactivityReminderAt = .distantPast
        inactivitySuppressedUntil = .distantPast
        clearInactivityAlert()

        switch snapshot.state {
        case .idle:
            statusText = ""
            clearPersistedStateFile()
        case .recording:
            statusText = "检测到未完成旅程，正在恢复"
        case .paused:
            statusText = "已暂停（已恢复）"
        }
    }

    private func resetToIdle(clearPersisted: Bool) {
        state = .idle
        statusText = ""
        journeyID = nil
        startedAt = nil
        recordingBeganAt = nil
        distanceMeters = 0
        pointCount = 0

        recordedPoints.removeAll(keepingCapacity: true)
        pendingPoints.removeAll(keepingCapacity: true)
        lastAcceptedLocation = nil
        lastProgressSentAt = .distantPast
        lastBoundaryCheckAt = .distantPast
        lastInactivityReminderAt = .distantPast
        inactivitySuppressedUntil = .distantPast
        pendingStartMode = .none
        isRecoveringFromDisk = false
        clearInactivityAlert()

        workoutSession = nil
        workoutBuilder = nil

        if clearPersisted {
            clearPersistedStateFile()
        }
    }

    private func persistedStateURL() -> URL? {
        do {
            let root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return root.appendingPathComponent("watch_journey_state_v1.json")
        } catch {
            return nil
        }
    }

    private func clearPersistedStateFile() {
        guard let url = persistedStateURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static let stateEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let stateDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension WatchJourneyRecorder: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        if status == .denied || status == .restricted {
            statusText = "定位权限被拒绝"
            clearInactivityAlert()
            if state == .recording {
                state = .paused
                locationManager.stopUpdatingLocation()
                workoutSession?.pause()
                persistState(force: true)
            }
            pendingStartMode = .none
            return
        }

        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }

        switch pendingStartMode {
        case .none:
            break
        case .newJourney:
            pendingStartMode = .none
            requestWorkoutAuthorizationAndStart(isRecovery: false)
        case .recover:
            pendingStartMode = .none
            requestWorkoutAuthorizationAndStart(isRecovery: true)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        _ = manager
        for location in locations {
            accept(location)
        }

        if state == .recording, !locations.isEmpty, statusText != "录制中" {
            statusText = "录制中"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        _ = manager
        if let clError = error as? CLError {
            switch clError.code {
            case .locationUnknown:
                #if targetEnvironment(simulator)
                statusText = "模拟器默认无GPS，请在Xcode设置模拟位置"
                #else
                statusText = "GPS 搜索中..."
                #endif
                return
            case .denied:
                statusText = "定位权限被拒绝"
                return
            case .network:
                statusText = "定位网络不可用，自动重试中"
                return
            default:
                break
            }
        }

        let now = Date()
        if now.timeIntervalSince(lastLocationErrorAt) >= 8 {
            statusText = "定位暂时异常，自动重试中"
            lastLocationErrorAt = now
        }
    }
}

extension WatchJourneyRecorder: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        _ = workoutSession
        _ = fromState
        _ = date

        if toState == .ended {
            workoutBuilder?.endCollection(withEnd: Date()) { [weak self] _, _ in
                self?.workoutBuilder?.discardWorkout()
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        _ = workoutSession
        guard usesWorkoutSession else { return }
        statusText = "Workout 会话失败: \(error.localizedDescription)"

        if state == .recording {
            state = .paused
            locationManager.stopUpdatingLocation()
            persistState(force: true)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        _ = workoutBuilder
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        _ = workoutBuilder
        _ = collectedTypes
    }
}

private extension WatchJourneyPoint {
    var asLocation: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: -1,
            course: -1,
            speed: speed,
            timestamp: timestamp
        )
    }

    init(from location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            altitude: location.altitude
        )
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }

        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)

        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}
