import Foundation

/// Single owner of Douglas-Peucker polyline traversal.
///
/// Both polyline simplifiers in the app — the tolerance-based display
/// jitter-cleanup (`JourneyPostCorrection.simplifiedForDisplay`) and the
/// count-based on-disk storage downsample (`JourneyStore.douglasPeuckerReduce`)
/// — run through the one iterative traversal here. That keeps a single DP
/// implementation instead of two, and crucially keeps it **iterative**: an
/// all-day route of tens of thousands of points can no longer recurse deep
/// enough to overflow the thread stack, because the work list lives on the heap.
///
/// The two callers differ only in policy, expressed through `onSplit`:
///   - tolerance: keep a split point when its distance exceeds ε, and stop
///     subdividing a segment once its peak falls under ε (classic threshold DP);
///   - count: always subdivide fully so every interior point receives a
///     significance value, then the caller keeps the N most significant.
/// The distance metric is also supplied by the caller (meters for the display
/// path, a cheaper cos-scaled relative value for ranking on the storage path),
/// so each keeps its exact existing behavior.
enum PolylineSimplifier {

    /// Iterative Douglas-Peucker traversal over `count` points using an explicit
    /// work stack (no recursion).
    ///
    /// For each visited segment `[a, b]` it finds the interior index of maximum
    /// `distance(i, a, b)` and calls `onSplit(maxIdx, maxDist)`. When `onSplit`
    /// returns `true` the point becomes a split and both halves `[a, maxIdx]` and
    /// `[maxIdx, b]` are pushed; when it returns `false` the segment is left
    /// unsubdivided. Visit order does not affect the result — each segment is
    /// processed independently and decisions are recorded per index by the
    /// caller's closures.
    static func traverse(
        count: Int,
        distance: (_ i: Int, _ a: Int, _ b: Int) -> Double,
        onSplit: (_ idx: Int, _ dist: Double) -> Bool
    ) {
        guard count > 2 else { return }

        var work: [(Int, Int)] = [(0, count - 1)]
        while let (a, b) = work.popLast() {
            guard b - a >= 2 else { continue }

            var maxDist = 0.0
            var maxIdx = a + 1
            for i in (a + 1)..<b {
                let d = distance(i, a, b)
                if d > maxDist {
                    maxDist = d
                    maxIdx = i
                }
            }

            if onSplit(maxIdx, maxDist) {
                work.append((a, maxIdx))
                work.append((maxIdx, b))
            }
        }
    }
}
