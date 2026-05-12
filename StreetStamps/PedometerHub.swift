import Foundation
import Combine
#if canImport(CoreMotion)
import CoreMotion
#endif

/// Pedometer hub — wraps `CMPedometer` to provide synchronous "steps in last N seconds"
/// queries from cached samples. Used by `TrackingService.ingest` to validate GPS-reported
/// distance: if GPS says 10m but pedometer says zero steps in the last 30 seconds, that's
/// GPS drift (not user movement).
///
/// Design notes:
///   - `CMPedometer` runs on M-series motion coprocessor; near-zero battery cost.
///   - `startUpdates` callback frequency is iOS-controlled (typically every few seconds
///     when moving, sparser when still). We buffer cumulative-step samples in a sliding
///     window so the synchronous `stepsInLast(_:)` read is O(history size) without async.
///   - On devices without pedometer support (older iPads, Mac Catalyst), `isAvailable`
///     returns false; `stepsInLast(_:)` returns 0; callers should treat 0 as "no info"
///     and fall back to GPS-only behavior.
///
/// Reference: PR 5 design at docs/plans/2026-05-04-coremotion-distance-validation-design.md
@MainActor
final class PedometerHub: ObservableObject {
    static let shared = PedometerHub()

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isRunning: Bool = false

    #if canImport(CoreMotion)
    private let pedometer = CMPedometer()
    #endif

    /// Cumulative step samples: (timestamp, total steps since journey start).
    /// Trimmed to last `historyMaxAge` seconds to bound memory.
    private var stepHistory: [(time: Date, cumSteps: Int)] = []
    private let historyMaxAge: TimeInterval = 90

    private var started: Bool = false
    private var startDate: Date?

    private init() {
        #if canImport(CoreMotion)
        isAvailable = CMPedometer.isStepCountingAvailable()
        #else
        isAvailable = false
        #endif
    }

    func setShouldRun(_ shouldRun: Bool) {
        if shouldRun {
            start(from: Date())
        } else {
            stop()
        }
    }

    /// Start pedometer updates. Idempotent — second call is ignored unless stopped first.
    /// `startDate` is the anchor: cumulative step counts are reported relative to this time.
    func start(from date: Date) {
        guard !started else { return }
        guard isAvailable else { return }

        started = true
        isRunning = true
        startDate = date
        stepHistory.removeAll(keepingCapacity: true)
        // Seed history with zero at start so stepsInLast() returns 0 (not nil) immediately.
        stepHistory.append((time: date, cumSteps: 0))

        #if canImport(CoreMotion)
        pedometer.startUpdates(from: date) { [weak self] data, _ in
            guard let self, let data else { return }
            let count = data.numberOfSteps.intValue
            let now = Date()
            Task { @MainActor in
                self.appendSample(at: now, count: count)
            }
        }
        #endif
    }

    func stop() {
        guard started else { return }
        started = false
        isRunning = false

        #if canImport(CoreMotion)
        pedometer.stopUpdates()
        #endif

        stepHistory.removeAll(keepingCapacity: true)
        startDate = nil
    }

    /// Number of steps recorded in the last `seconds` interval. Read synchronously from
    /// the cached sliding window — safe to call from `ingest` without async.
    /// Returns 0 if history is empty (e.g. journey just started, pedometer not yet available).
    func stepsInLast(_ seconds: TimeInterval) -> Int {
        guard let last = stepHistory.last else { return 0 }
        let cutoff = last.time.addingTimeInterval(-seconds)

        // Find the most recent sample at or before cutoff. That's the baseline cum count
        // we subtract from `last.cumSteps`. If no such sample, use the earliest available.
        var baselineCum = stepHistory.first?.cumSteps ?? 0
        for sample in stepHistory.reversed() {
            if sample.time <= cutoff {
                baselineCum = sample.cumSteps
                break
            }
        }
        return max(0, last.cumSteps - baselineCum)
    }

    // MARK: - Internal

    private func appendSample(at time: Date, count: Int) {
        // CMPedometer guarantees monotonic non-decreasing cumulative count, but
        // defend against weird edge cases (e.g. pedometer reset across permission changes).
        if let lastCount = stepHistory.last?.cumSteps, count < lastCount {
            // Step count went down — pedometer state likely reset. Reseed history.
            stepHistory = [(time: time, cumSteps: count)]
            return
        }

        stepHistory.append((time: time, cumSteps: count))

        // Evict samples older than historyMaxAge. Keep at least one entry to support
        // baseline computation for short-window queries.
        let cutoff = time.addingTimeInterval(-historyMaxAge)
        while stepHistory.count > 1, let first = stepHistory.first, first.time < cutoff {
            stepHistory.removeFirst()
        }
    }
}
