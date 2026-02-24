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

        var cleaned = dedupeTinySteps(coords, minDistinctMeters: config.minDistinctPointMeters)
        guard cleaned.count >= 2 else { return max(0, route.distance) }

        // A few passes catch isolated GPS spikes while keeping normal turns.
        for _ in 0..<2 {
            cleaned = removeSinglePointSpikes(cleaned, config: config)
            if cleaned.count < 2 { break }
        }
        guard cleaned.count >= 2 else { return max(0, route.distance) }

        var total: Double = 0
        let maxSegment = config.maxSegmentMeters
        let hardRejectSegment = maxSegment * 10
        for i in 1..<cleaned.count {
            let d = distance(cleaned[i - 1], cleaned[i])
            guard d.isFinite, d >= 0 else { continue }
            // Keep realistic long segments with a cap instead of dropping them to zero.
            // Extremely huge segments are still treated as outliers and ignored.
            if d > hardRejectSegment { continue }
            if d > maxSegment {
                total += maxSegment
                continue
            }
            total += d
        }
        return max(0, total)
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
                maxSegmentMeters: 3_000
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
