import Foundation
import CoreLocation

/// Post-finish distance correction based on recorded polyline geometry.
/// Keeps route points unchanged and only recalculates a cleaner distance value.
enum JourneyPostCorrection {
    private struct Config {
        let minDistinctPointMeters: Double
        let spikeLegMinMeters: Double
        let spikeMinDetourMeters: Double
        let spikeDetourRatio: Double
        let spikeDirectRatioMax: Double
        let maxSegmentMeters: Double
    }

    static func correctedDistance(for route: JourneyRoute) -> Double {
        let coords = route.coordinates.clCoords.filter(CLLocationCoordinate2DIsValid)
        guard coords.count >= 2 else { return max(0, route.distance) }

        let config = config(for: route.trackingMode)
        let cleaned = correctedCoordinates(from: coords, config: config)
        guard cleaned.count >= 2 else { return max(0, route.distance) }

        var total: Double = 0
        let maxSegment = config.maxSegmentMeters
        let hardRejectSegment = maxSegment * 10
        for i in 1..<cleaned.count {
            let d = distance(cleaned[i - 1], cleaned[i])
            guard d.isFinite, d >= 0 else { continue }
            // Extremely huge segments are treated as outliers and ignored.
            if d > hardRejectSegment { continue }
            // Long uncertain segments are skipped instead of capped to avoid inflating distance.
            if d > maxSegment { continue }
            total += d
        }
        return max(0, total)
    }

    static func correctedCoordinates(for route: JourneyRoute) -> [CoordinateCodable] {
        let coords = route.coordinates.clCoords.filter(CLLocationCoordinate2DIsValid)
        guard coords.count >= 2 else { return route.coordinates }
        let config = config(for: route.trackingMode)
        let cleaned = correctedCoordinates(from: coords, config: config)
        guard cleaned.count >= 2 else { return route.coordinates }
        return cleaned.map { CoordinateCodable(lat: $0.latitude, lon: $0.longitude) }
    }

    /// Display-only simplified coordinates: cleaned + Douglas-Peucker simplified.
    /// Use case: park strolls under tree cover have GPS jitter that produces visible
    /// zigzag lines; DP smooths the polyline without affecting `route.distance`
    /// (distance is computed separately from the cleaned-but-not-simplified geometry).
    ///
    /// Epsilon is keyed by average per-point accuracy:
    ///   sport mode → ε=3m (preserve detail; runners want fidelity)
    ///   acc < 30  → ε=5m  (good signal, light simplification)
    ///   acc 30-80 → ε=12m (medium jitter, moderate simplification)
    ///   acc > 80  → ε=25m (heavy jitter, aggressive flattening)
    ///
    /// Persisted per-point `acc` field (PR 3.1) drives this. Legacy data without
    /// `acc` falls back to ε=5m (treats unknown as good signal).
    static func simplifiedForDisplay(for route: JourneyRoute) -> [CoordinateCodable] {
        let coords = route.coordinates.clCoords.filter(CLLocationCoordinate2DIsValid)
        guard coords.count >= 2 else { return route.coordinates }

        let config = config(for: route.trackingMode)
        let cleaned = correctedCoordinates(from: coords, config: config)
        guard cleaned.count >= 2 else { return route.coordinates }

        // Sport mode is already OneEuro-smoothed during recording and its display
        // ε is only 2m, so Douglas-Peucker would drop almost nothing while paying
        // for a full simplification pass. Skip it: the cleaned (dedup + spike-
        // removed) geometry is the display geometry. Daily mode has no OneEuro,
        // so it still needs the jitter-flattening DP pass below.
        if route.trackingMode == .sport {
            return cleaned.map { CoordinateCodable(lat: $0.latitude, lon: $0.longitude) }
        }

        let avgAcc = averageAccuracy(of: route.coordinates)
        let epsilon = epsilonForAvgAccuracy(avgAcc, mode: route.trackingMode)

        let simplified = douglasPeucker(cleaned, epsilon: epsilon)
        let result = simplified.count >= 2 ? simplified : cleaned
        return result.map { CoordinateCodable(lat: $0.latitude, lon: $0.longitude) }
    }

    private static func averageAccuracy(of coords: [CoordinateCodable]) -> Double {
        let accs = coords.compactMap(\.acc).filter { $0 > 0 }
        guard !accs.isEmpty else { return 30 }   // Legacy data without acc → treat as good signal.
        return accs.reduce(0, +) / Double(accs.count)
    }

    private static func epsilonForAvgAccuracy(_ avgAcc: Double, mode: TrackingMode) -> Double {
        // Conservative: prefer keeping real curves over flattening visible jitter.
        // Real S-bends or 8m-radius arcs around buildings stay visible at these values.
        if mode == .sport { return 2 }
        switch avgAcc {
        case ..<30:  return 3    // good signal: barely simplify
        case ..<80:  return 8    // urban: clean small jitter, keep building-detour curves
        default:     return 18   // dense forest / indoor: flatten heavy zigzag, keep major bends
        }
    }

    // MARK: - Douglas-Peucker

    /// Standard recursive DP. Keeps endpoints; for each segment, finds the point
    /// with max perpendicular distance and either keeps it (and recurses) or
    /// drops the entire interior.
    private static func douglasPeucker(_ coords: [CLLocationCoordinate2D], epsilon: Double) -> [CLLocationCoordinate2D] {
        guard coords.count > 2 else { return coords }
        var keep = Array(repeating: false, count: coords.count)
        keep[0] = true
        keep[coords.count - 1] = true

        // Tolerance policy: keep a split point when its perpendicular distance
        // (in meters) exceeds ε, and stop subdividing once a segment's peak falls
        // under ε. This is the classic threshold Douglas-Peucker. The shared
        // iterative traversal keeps the work list on the heap so a long route
        // can't overflow the stack.
        PolylineSimplifier.traverse(
            count: coords.count,
            distance: { i, a, b in
                perpendicularDistance(point: coords[i], lineStart: coords[a], lineEnd: coords[b])
            },
            onSplit: { idx, dist in
                guard dist > epsilon else { return false }
                keep[idx] = true
                return true
            }
        )

        return zip(coords, keep).compactMap { $1 ? $0 : nil }
    }

    /// Perpendicular distance from point to line segment, in meters.
    /// Uses local-tangent approximation (m/° depends on cos(latitude)) — accurate
    /// for short segments and any latitude up to ~80°. DP doesn't need centimeter precision.
    private static func perpendicularDistance(
        point p: CLLocationCoordinate2D,
        lineStart a: CLLocationCoordinate2D,
        lineEnd b: CLLocationCoordinate2D
    ) -> Double {
        let cosLat = cos(a.latitude * .pi / 180)
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * max(0.01, cosLat)   // cap to avoid div-by-zero near poles

        let ax = a.longitude * metersPerDegLon
        let ay = a.latitude * metersPerDegLat
        let bx = b.longitude * metersPerDegLon
        let by = b.latitude * metersPerDegLat
        let px = p.longitude * metersPerDegLon
        let py = p.latitude * metersPerDegLat

        // Cross-product / line-length formula for point-to-line distance.
        let num = abs((by - ay) * px - (bx - ax) * py + bx * ay - by * ax)
        let den = sqrt((by - ay) * (by - ay) + (bx - ax) * (bx - ax))
        return den > 1e-9 ? num / den : distance(p, a)
    }

    private static func correctedCoordinates(
        from coords: [CLLocationCoordinate2D],
        config: Config
    ) -> [CLLocationCoordinate2D] {
        var cleaned = dedupeTinySteps(coords, minDistinctMeters: config.minDistinctPointMeters)
        guard cleaned.count >= 2 else { return cleaned }

        for _ in 0..<2 {
            cleaned = removeSinglePointSpikes(cleaned, config: config)
            if cleaned.count < 2 { break }
        }
        return cleaned
    }

    private static func config(for mode: TrackingMode) -> Config {
        switch mode {
        case .sport:
            return Config(
                minDistinctPointMeters: 0.8,
                spikeLegMinMeters: 16,
                spikeMinDetourMeters: 55,
                spikeDetourRatio: 2.6,
                spikeDirectRatioMax: 0.75,
                maxSegmentMeters: 1_200
            )
        case .daily:
            return Config(
                minDistinctPointMeters: 1.5,
                spikeLegMinMeters: 24,
                spikeMinDetourMeters: 90,
                spikeDetourRatio: 2.9,
                spikeDirectRatioMax: 0.7,
                // Daily mode may contain long GPS-loss bridges (dashed missing segments).
                // Keep a wider threshold so corrected distance does not erase that mileage.
                maxSegmentMeters: 20_000
            )
        }
    }

    private static func dedupeTinySteps(_ coords: [CLLocationCoordinate2D], minDistinctMeters: Double) -> [CLLocationCoordinate2D] {
        guard !coords.isEmpty else { return [] }
        var out: [CLLocationCoordinate2D] = [coords[0]]
        out.reserveCapacity(coords.count)
        for c in coords.dropFirst() {
            guard let last = out.last else {
                out.append(c)
                continue
            }
            if distance(last, c) >= minDistinctMeters {
                out.append(c)
            }
        }
        if out.count == 1, let last = coords.last, !sameCoordinate(out[0], last) {
            out.append(last)
        }
        return out
    }

    private static func removeSinglePointSpikes(_ coords: [CLLocationCoordinate2D], config: Config) -> [CLLocationCoordinate2D] {
        guard coords.count >= 3 else { return coords }

        var out: [CLLocationCoordinate2D] = [coords[0]]
        out.reserveCapacity(coords.count)

        for i in 1..<(coords.count - 1) {
            guard let prev = out.last else { continue }
            let curr = coords[i]
            let next = coords[i + 1]

            let d1 = distance(prev, curr)
            let d2 = distance(curr, next)
            let direct = distance(prev, next)
            let detour = d1 + d2

            let isSpike =
                d1 >= config.spikeLegMinMeters &&
                d2 >= config.spikeLegMinMeters &&
                detour >= config.spikeMinDetourMeters &&
                direct > 0 &&
                (detour / direct) >= config.spikeDetourRatio &&
                direct <= min(d1, d2) * config.spikeDirectRatioMax

            if !isSpike {
                out.append(curr)
            }
        }

        out.append(coords[coords.count - 1])
        return out
    }

    private static func sameCoordinate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 1e-9 && abs(a.longitude - b.longitude) < 1e-9
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
