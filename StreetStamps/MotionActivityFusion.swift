import Foundation
import Combine
#if canImport(CoreMotion)
import CoreMotion
#endif

enum MotionActivityKind: String, Equatable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown
}

enum MotionActivityConfidence: Int, Equatable {
    case low
    case medium
    case high
}

struct MotionActivitySnapshot: Equatable {
    let kind: MotionActivityKind
    let confidence: MotionActivityConfidence

    init(kind: MotionActivityKind, confidence: MotionActivityConfidence) {
        self.kind = kind
        self.confidence = confidence
    }

    static let unknown = MotionActivitySnapshot(kind: .unknown, confidence: .low)

    var indicatesMovement: Bool {
        switch kind {
        case .walking, .running, .cycling, .automotive:
            return true
        case .stationary, .unknown:
            return false
        }
    }

    var contradictsStationary: Bool {
        indicatesMovement && confidence != .low
    }

    var stronglyIndicatesMovement: Bool {
        indicatesMovement && confidence == .high
    }

    #if canImport(CoreMotion)
    init(activity: CMMotionActivity) {
        if activity.automotive {
            kind = .automotive
        } else if activity.cycling {
            kind = .cycling
        } else if activity.running {
            kind = .running
        } else if activity.walking {
            kind = .walking
        } else if activity.stationary {
            kind = .stationary
        } else {
            kind = .unknown
        }

        switch activity.confidence {
        case .high:
            confidence = .high
        case .medium:
            confidence = .medium
        @unknown default:
            confidence = .low
        }
    }
    #endif
}

enum TrackingMotionFusion {
    static func shouldTreatAsStationary(
        gpsStationaryCandidate: Bool,
        motion: MotionActivitySnapshot
    ) -> Bool {
        guard gpsStationaryCandidate else { return false }
        return !motion.contradictsStationary
    }

    static func shouldExitStationary(
        gpsExitCandidate: Bool,
        motion: MotionActivitySnapshot
    ) -> Bool {
        gpsExitCandidate || motion.stronglyIndicatesMovement
    }
}

enum PassiveMotionFusion {
    static func shouldEnterStationary(
        gpsStationaryCandidate: Bool,
        motion: MotionActivitySnapshot
    ) -> Bool {
        guard gpsStationaryCandidate else { return false }
        return !motion.contradictsStationary
    }

    static func shouldExitStationary(
        gpsExitCandidate: Bool,
        motion: MotionActivitySnapshot
    ) -> Bool {
        gpsExitCandidate || (motion.indicatesMovement && motion.confidence != .low)
    }
}

@MainActor
final class MotionActivityHub: ObservableObject {
    static let shared = MotionActivityHub()

    @Published private(set) var snapshot: MotionActivitySnapshot = .unknown

    #if canImport(CoreMotion)
    private let activityManager = CMMotionActivityManager()
    private let activityQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.streetstamps.motion-activity"
        queue.qualityOfService = .utility
        return queue
    }()
    #endif

    private var started = false

    private init() {
        start()
    }

    func start() {
        guard !started else { return }
        started = true

        #if canImport(CoreMotion)
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: activityQueue) { [weak self] activity in
            guard let self, let activity else { return }
            let next = MotionActivitySnapshot(activity: activity)
            Task { @MainActor in
                self.snapshot = next
            }
        }
        #endif
    }
}
