//
//  MainThreadHeartbeat.swift
//  StreetStamps
//
//  Diagnostic: detects main-thread stalls. A @MainActor task sleeps ~16ms per
//  iteration; when it resumes it measures how long actually elapsed. If the gap
//  exceeds the threshold, the main thread was blocked for that long (the sleep
//  continuation couldn't be serviced), so we log it.
//
//  This is the right way to find "taps need several presses" / freeze bugs:
//  it measures main-thread *occupancy*, not wall-clock of any one function.
//  See CLAUDE.md → "Swift Concurrency Pitfalls".
//
//  DEBUG-only by convention — call `start()` from a screen's `.onAppear` while
//  reproducing the jank, then read the console.
//

import Foundation
import QuartzCore

@MainActor
final class MainThreadHeartbeat {
    static let shared = MainThreadHeartbeat()

    private var task: Task<Void, Never>?
    private(set) var isRunning = false

    /// Start monitoring. `thresholdMs` is the gap above which a stall is logged
    /// (32ms ≈ two dropped 60fps frames). Idempotent.
    func start(label: String = "main", thresholdMs: Double = 32) {
        guard !isRunning else { return }
        isRunning = true
        let sleepNanos: UInt64 = 16_000_000   // 16ms
        task = Task { @MainActor [weak self] in
            var last = CACurrentMediaTime()
            var worst = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: sleepNanos)
                let now = CACurrentMediaTime()
                let gapMs = (now - last) * 1000.0
                last = now
                if gapMs > thresholdMs {
                    worst = max(worst, gapMs)
                    print("⚠️ [Heartbeat:\(label)] main-thread stall \(String(format: "%.0f", gapMs))ms (worst \(String(format: "%.0f", worst))ms)")
                }
                _ = self // keep the task tied to the singleton's lifetime
            }
        }
        print("💓 [Heartbeat:\(label)] started (threshold \(Int(thresholdMs))ms)")
    }

    func stop() {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        isRunning = false
        print("💔 [Heartbeat] stopped")
    }
}
