import Foundation
import Combine
import QuartzCore

/// Per-user, render-time only mask of journey route point indices that should be
/// excluded from polyline rendering in CityDeepView. Underlying `JourneyRoute`
/// data is never modified — the mask filters at draw time only.
///
/// Indices are interpreted against `JourneyRoute.displayRouteCoordinates`, the
/// same array used by all city polyline rendering. If the user later changes a
/// journey's `preferredRouteSource`, indices may not point at the same world
/// coordinates anymore. CityDeepView does not expose source switching, and
/// `preferredRouteSource` is fixed at finalize time, so this is acceptable.
@MainActor
final class RenderMaskStore: ObservableObject {
    /// Bumps on any mask change so observers re-render.
    @Published private(set) var maskRevision: Int = 0
    @Published private(set) var undoDepth: Int = 0

    private var maskByJourney: [String: Set<Int>] = [:]
    private var paths: StoragePath
    private let saveQueue = DispatchQueue(label: "com.streetstamps.rendermask.save", qos: .utility)

    /// Per-stroke deltas. Each entry is the set of indices that THIS stroke
    /// added to a journey's mask (i.e. weren't already erased). Undo pops one
    /// entry and subtracts it. Lives in memory only — undo doesn't persist.
    private var undoStack: [[String: Set<Int>]] = []
    private var pendingStrokeDelta: [String: Set<Int>] = [:]
    private var isStroking: Bool = false
    /// Throttle window for `maskRevision` updates while a stroke is active.
    /// The mask data itself updates immediately on every sample so brush
    /// hit-tests stay accurate; only the SwiftUI publisher (which causes
    /// expensive polyline rebuilds) is rate-limited.
    private static let strokePublishIntervalSeconds: CFTimeInterval = 0.15
    private var lastPublishedAt: CFTimeInterval = 0

    init(paths: StoragePath) {
        self.paths = paths
        loadFromDisk()
    }

    func rebind(paths: StoragePath) {
        self.paths = paths
        maskByJourney = [:]
        undoStack.removeAll()
        pendingStrokeDelta = [:]
        isStroking = false
        undoDepth = 0
        loadFromDisk()
        maskRevision &+= 1
    }

    // MARK: - Read

    func mask(for journeyID: String) -> Set<Int> {
        maskByJourney[journeyID] ?? []
    }

    /// Read-only snapshot of the entire mask, suitable to pass to
    /// nonisolated thumbnail render code.
    func snapshot() -> [String: Set<Int>] {
        maskByJourney
    }

    func isErased(journeyID: String, index: Int) -> Bool {
        maskByJourney[journeyID]?.contains(index) ?? false
    }

    func hasAnyMask(forJourneyIDs ids: [String]) -> Bool {
        ids.contains { (maskByJourney[$0]?.isEmpty == false) }
    }

    // MARK: - Write

    func toggle(journeyID: String, index: Int) {
        var set = maskByJourney[journeyID] ?? []
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
        if set.isEmpty {
            maskByJourney.removeValue(forKey: journeyID)
        } else {
            maskByJourney[journeyID] = set
        }
        maskRevision &+= 1
        scheduleSave()
    }

    // MARK: - Stroke / undo

    /// Start a brush stroke. Subsequent `erase(...)` calls within the stroke
    /// accumulate into one undo step; `endStroke()` finalizes it.
    func beginStroke() {
        pendingStrokeDelta = [:]
        isStroking = true
        lastPublishedAt = 0
    }

    /// Finalize the in-progress stroke. Pushes it onto the undo stack as a
    /// single step if the stroke actually erased anything new and forces a
    /// final publisher update so the polyline reflects the complete state.
    func endStroke() {
        let wasStroking = isStroking
        let delta = pendingStrokeDelta.filter { !$0.value.isEmpty }
        pendingStrokeDelta = [:]
        isStroking = false

        guard wasStroking else { return }
        if !delta.isEmpty {
            undoStack.append(delta)
            undoDepth = undoStack.count
        }
        // Always bump on stroke end so any throttled mid-stroke updates are
        // rolled into one final visible refresh.
        maskRevision &+= 1
    }

    /// Pop the last stroke and remove its added indices from the mask.
    func undo() {
        guard let last = undoStack.popLast() else { return }
        for (jid, indices) in last {
            var set = maskByJourney[jid] ?? []
            set.subtract(indices)
            if set.isEmpty {
                maskByJourney.removeValue(forKey: jid)
            } else {
                maskByJourney[jid] = set
            }
        }
        undoDepth = undoStack.count
        maskRevision &+= 1
        scheduleSave()
    }

    /// Add `indices` to the mask for `journeyID`. Brush strokes call this
    /// continuously; we noop when the union is unchanged so re-renders fire
    /// only on actual state transitions. Newly-added indices are recorded
    /// into the in-progress stroke delta for undo.
    ///
    /// While a stroke is active, the SwiftUI publisher is throttled to
    /// `strokePublishIntervalSeconds` — the underlying mask data is always
    /// current (so brush hit-testing reads correct state), but the polyline
    /// only rebuilds at a rate the renderer can actually keep up with.
    func erase(journeyID: String, indices: Set<Int>) {
        guard !indices.isEmpty else { return }
        let existing = maskByJourney[journeyID] ?? []
        let newlyAdded = indices.subtracting(existing)
        guard !newlyAdded.isEmpty else { return }
        if isStroking {
            pendingStrokeDelta[journeyID, default: []].formUnion(newlyAdded)
        }
        var set = existing
        set.formUnion(newlyAdded)
        maskByJourney[journeyID] = set

        if isStroking {
            let now = CACurrentMediaTime()
            if now - lastPublishedAt >= Self.strokePublishIntervalSeconds {
                lastPublishedAt = now
                maskRevision &+= 1
            }
            // Mid-stroke samples within the throttle window: skip publisher
            // bump but the mask data is still updated. `endStroke()` will
            // emit a final bump so the user always sees the complete result.
        } else {
            maskRevision &+= 1
        }
        scheduleSave()
    }

    func clear(forJourneyIDs ids: [String]) {
        var changed = false
        for id in ids where maskByJourney.removeValue(forKey: id) != nil {
            changed = true
        }
        if changed {
            maskRevision &+= 1
            scheduleSave()
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        let url = paths.renderMaskURL
        guard let data = try? Data(contentsOf: url) else { return }
        guard let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data) else { return }
        maskByJourney = decoded.compactMapValues { values in
            let s = Set(values.filter { $0 >= 0 })
            return s.isEmpty ? nil : s
        }
    }

    private func scheduleSave() {
        let snapshot: [String: [Int]] = maskByJourney.mapValues { Array($0).sorted() }
        let url = paths.renderMaskURL
        let cachesDir = paths.cachesDir
        let fm = paths.fm
        saveQueue.async {
            do {
                var isDir: ObjCBool = false
                if !fm.fileExists(atPath: cachesDir.path, isDirectory: &isDir) || !isDir.boolValue {
                    try? fm.createDirectory(at: cachesDir, withIntermediateDirectories: true)
                }
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                #if DEBUG
                print("⚠️ RenderMaskStore save failed:", error)
                #endif
            }
        }
    }
}

// MARK: - JourneyRoute filtering

extension JourneyRoute {
    /// Splits this journey at the masked indices, returning one synthetic
    /// journey per contiguous run of unmasked points. Rendering each run as
    /// its own polyline is what makes erased regions appear as real gaps —
    /// otherwise the renderer would bridge across the removed indices with
    /// a straight line, defeating the entire eraser.
    ///
    /// Returns `[self]` when the mask is empty so the no-mask path is free.
    func applyingRenderMaskSplit(_ mask: Set<Int>) -> [JourneyRoute] {
        guard !mask.isEmpty else { return [self] }
        let display = self.displayRouteCoordinates
        guard !display.isEmpty else { return [self] }

        var runs: [[CoordinateCodable]] = []
        var current: [CoordinateCodable] = []
        for (idx, coord) in display.enumerated() {
            if mask.contains(idx) {
                if !current.isEmpty {
                    runs.append(current)
                    current = []
                }
            } else {
                current.append(coord)
            }
        }
        if !current.isEmpty { runs.append(current) }

        guard !runs.isEmpty else { return [] }

        return runs.map { run in
            var copy = self
            // Mirror displayRouteCoordinates' fallback decision — write each
            // run into the same slot that was actually being returned.
            switch self.preferredRouteSource {
            case .matched:
                if !self.matchedCoordinates.isEmpty {
                    copy.matchedCoordinates = run
                } else if !self.correctedCoordinates.isEmpty {
                    copy.correctedCoordinates = run
                } else {
                    copy.coordinates = run
                }
            case .corrected:
                if !self.correctedCoordinates.isEmpty {
                    copy.correctedCoordinates = run
                } else {
                    copy.coordinates = run
                }
            case .raw:
                if !self.coordinates.isEmpty {
                    copy.coordinates = run
                } else if !self.correctedCoordinates.isEmpty {
                    copy.correctedCoordinates = run
                } else {
                    copy.matchedCoordinates = run
                }
            }
            return copy
        }
    }
}
