import Foundation
import CoreLocation
import MapKit

struct LifelogRenderSnapshotRequest: Sendable {
    let selectedDay: Date
    let countryISO2: String?
    let renderMaxPoints: Int

    static let highQualityRenderMaxPoints = 800

    static func daySnapshot(selectedDay: Date, countryISO2: String?) -> LifelogRenderSnapshotRequest {
        LifelogRenderSnapshotRequest(
            selectedDay: Calendar.current.startOfDay(for: selectedDay),
            countryISO2: countryISO2,
            renderMaxPoints: highQualityRenderMaxPoints
        )
    }

    static func viewportRender(selectedDay: Date, countryISO2: String?) -> LifelogRenderSnapshotRequest {
        daySnapshot(selectedDay: selectedDay, countryISO2: countryISO2)
    }
}

struct LifelogRenderSnapshot: Sendable {
    let selectedDay: Date?
    let cachedPathCoordsWGS84: [CLLocationCoordinate2D]
    let farRouteSegments: [RenderRouteSegment]
    let footprintRuns: [[CLLocationCoordinate2D]]
    let selectedDayCenterCoordinate: CLLocationCoordinate2D?
    let isHighQuality: Bool

    static let empty = LifelogRenderSnapshot(
        selectedDay: nil,
        cachedPathCoordsWGS84: [],
        farRouteSegments: [],
        footprintRuns: [],
        selectedDayCenterCoordinate: nil,
        isHighQuality: false
    )
}

struct LifelogRenderGenerationState: Sendable {
    private(set) var latestGeneration: Int = 0

    mutating func issue() -> Int {
        latestGeneration &+= 1
        return latestGeneration
    }

    func accepts(_ generation: Int) -> Bool {
        generation == latestGeneration
    }
}

struct LifelogDaySnapshotKey: Hashable, Sendable {
    let day: Date
    let countryISO2: String?
    let journeyRevision: Int
    let lifelogRevision: Int

    init(day: Date, countryISO2: String?, journeyRevision: Int, lifelogRevision: Int) {
        self.day = Calendar.current.startOfDay(for: day)
        self.countryISO2 = LifelogDaySnapshotKey.normalizedISO2(countryISO2)
        self.journeyRevision = journeyRevision
        self.lifelogRevision = lifelogRevision
    }

    private static func normalizedISO2(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let iso = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return iso.isEmpty ? nil : iso
    }
}

struct LifelogViewportBucket: Hashable, Sendable {
    let minLatE4: Int
    let maxLatE4: Int
    let minLonE4: Int
    let maxLonE4: Int

    static func bucket(for viewport: TrackTileViewport?) -> LifelogViewportBucket? {
        guard let viewport else { return nil }
        return LifelogViewportBucket(
            minLatE4: quantize(viewport.minLat),
            maxLatE4: quantize(viewport.maxLat),
            minLonE4: quantize(viewport.minLon),
            maxLonE4: quantize(viewport.maxLon)
        )
    }

    private static func quantize(_ value: Double) -> Int {
        Int((value * 10_000).rounded())
    }
}

struct LifelogViewportRenderKey: Hashable, Sendable {
    let dayKey: LifelogDaySnapshotKey
    let viewportBucket: LifelogViewportBucket?
}

struct LifelogSegmentedDaySnapshot: Sendable {
    let key: LifelogDaySnapshotKey
    let segments: [TrackTileSegment]
    let farRouteGroups: [[RenderRouteSegment]]
    let footprintGroups: [[CLLocationCoordinate2D]]
    let selectedDayCenterCoordinate: CLLocationCoordinate2D?

    var allDayRenderSnapshot: LifelogRenderSnapshot {
        let runs = segments.map { segment in
            segment.coordinates.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
        }
        return LifelogRenderSnapshot(
            selectedDay: key.day,
            cachedPathCoordsWGS84: runs.flatMap { $0 },
            farRouteSegments: farRouteGroups.flatMap { $0 },
            footprintRuns: footprintGroups.filter { !$0.isEmpty },
            selectedDayCenterCoordinate: selectedDayCenterCoordinate,
            isHighQuality: true
        )
    }

    func renderSnapshot(in viewport: TrackTileViewport?) -> LifelogRenderSnapshot {
        guard let viewport else { return allDayRenderSnapshot }

        let visibleIndices = segments.indices.filter { index in
            TrackRenderAdapter.segmentIntersectsViewport(segments[index], viewport: viewport)
        }

        let visibleRuns = visibleIndices.map { index in
            segments[index].coordinates.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
        }

        return LifelogRenderSnapshot(
            selectedDay: key.day,
            cachedPathCoordsWGS84: visibleRuns.flatMap { $0 },
            farRouteSegments: visibleIndices.flatMap { farRouteGroups[$0] },
            footprintRuns: visibleIndices.compactMap { index in
                let run = footprintGroups[index]
                return run.isEmpty ? nil : run
            },
            selectedDayCenterCoordinate: selectedDayCenterCoordinate,
            isHighQuality: true
        )
    }
}

enum LifelogRenderWarmupPlanner {
    static func recentDays(anchorDay: Date, count: Int = 7) -> [Date] {
        let base = Calendar.current.startOfDay(for: anchorDay)
        let clampedCount = max(0, count)
        guard clampedCount > 0 else { return [] }
        return (0..<clampedCount).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: base)
        }
    }
}

enum LifelogSegmentIncrementalMergePlanner {
    static func reusePrefixCount(existing: [TrackTileSegment], latest: [TrackTileSegment]) -> Int? {
        guard !existing.isEmpty else { return 0 }
        guard latest.count >= existing.count else { return nil }

        var prefix = 0
        while prefix < min(existing.count, latest.count), existing[prefix] == latest[prefix] {
            prefix += 1
        }

        if prefix == existing.count {
            return prefix
        }

        guard prefix == existing.count - 1 else { return nil }
        guard canReplaceTail(existingTail: existing[prefix], latestTail: latest[prefix]) else { return nil }
        return prefix
    }

    private static func canReplaceTail(existingTail: TrackTileSegment, latestTail: TrackTileSegment) -> Bool {
        guard existingTail.sourceType == latestTail.sourceType else { return false }
        guard existingTail.startTimestamp == latestTail.startTimestamp else { return false }
        guard latestTail.endTimestamp >= existingTail.endTimestamp else { return false }
        guard latestTail.coordinates.count >= existingTail.coordinates.count else { return false }
        return Array(latestTail.coordinates.prefix(existingTail.coordinates.count)) == existingTail.coordinates
    }
}

enum LifelogRenderSnapshotBuilder {
    static func buildDaySnapshot(
        key: LifelogDaySnapshotKey,
        segments: [TrackTileSegment]
    ) -> LifelogSegmentedDaySnapshot {
        let runs = TrackRenderAdapter.rawCoordinateRuns(from: segments)
        let validRuns = runs.filter { $0.count >= 2 }
        let perRunBudget = max(2, LifelogRenderSnapshotRequest.highQualityRenderMaxPoints / max(1, validRuns.count))

        let farRouteGroups = runs.map { run in
            buildFarRouteGroup(
                from: run,
                perRunBudget: perRunBudget,
                countryISO2: key.countryISO2
            )
        }
        let footprintGroups = runs.map { run in
            buildFootprintGroup(
                from: run,
                countryISO2: key.countryISO2
            )
        }
        let center = runs
            .last?
            .last
            .map { MapCoordAdapter.forMapKit($0, countryISO2: key.countryISO2) }

        return LifelogSegmentedDaySnapshot(
            key: key,
            segments: segments,
            farRouteGroups: farRouteGroups,
            footprintGroups: footprintGroups,
            selectedDayCenterCoordinate: center
        )
    }

    static func buildViewportSnapshot(
        daySnapshot: LifelogSegmentedDaySnapshot,
        request: LifelogRenderSnapshotRequest,
        viewport: TrackTileViewport?
    ) -> LifelogRenderSnapshot {
        _ = request
        return daySnapshot.renderSnapshot(in: viewport)
    }

    static func mergeDaySnapshot(
        existing: LifelogSegmentedDaySnapshot,
        latestKey: LifelogDaySnapshotKey,
        latestSegments: [TrackTileSegment]
    ) -> LifelogSegmentedDaySnapshot {
        guard let reusePrefix = LifelogSegmentIncrementalMergePlanner.reusePrefixCount(
            existing: existing.segments,
            latest: latestSegments
        ) else {
            return buildDaySnapshot(key: latestKey, segments: latestSegments)
        }

        if reusePrefix == 0 {
            return buildDaySnapshot(key: latestKey, segments: latestSegments)
        }

        let tailSegments = Array(latestSegments.dropFirst(reusePrefix))
        if tailSegments.isEmpty, reusePrefix == existing.segments.count {
            return LifelogSegmentedDaySnapshot(
                key: latestKey,
                segments: existing.segments,
                farRouteGroups: existing.farRouteGroups,
                footprintGroups: existing.footprintGroups,
                selectedDayCenterCoordinate: existing.selectedDayCenterCoordinate
            )
        }

        let tailSnapshot = buildDaySnapshot(key: latestKey, segments: tailSegments)
        let mergedSegments = Array(existing.segments.prefix(reusePrefix)) + tailSegments
        let mergedFarGroups = Array(existing.farRouteGroups.prefix(reusePrefix)) + tailSnapshot.farRouteGroups
        let mergedFootprintGroups = Array(existing.footprintGroups.prefix(reusePrefix)) + tailSnapshot.footprintGroups
        let center = tailSnapshot.selectedDayCenterCoordinate ?? existing.selectedDayCenterCoordinate

        return LifelogSegmentedDaySnapshot(
            key: latestKey,
            segments: mergedSegments,
            farRouteGroups: mergedFarGroups,
            footprintGroups: mergedFootprintGroups,
            selectedDayCenterCoordinate: center
        )
    }

    private static func buildFarRouteGroup(
        from run: [CLLocationCoordinate2D],
        perRunBudget: Int,
        countryISO2: String?
    ) -> [RenderRouteSegment] {
        guard run.count >= 2 else { return [] }
        let sampled = uniformSampledCoords(run, maxPoints: perRunBudget)
        let input = RouteRenderingPipeline.Input(
            coordsWGS84: sampled,
            applyGCJForChina: false,
            gapDistanceMeters: 8_000,
            countryISO2: countryISO2
        )
        return RouteRenderingPipeline.buildSegments(input, surface: .mapKit).segments
    }

    private static func buildFootprintGroup(
        from run: [CLLocationCoordinate2D],
        countryISO2: String?
    ) -> [CLLocationCoordinate2D] {
        guard run.count > 1 else {
            return MapCoordAdapter.forMapKit(run, countryISO2: countryISO2)
        }

        let sampled = LifelogFootprintSampler.sample(
            route: run,
            stepMeters: LifelogRenderModeSelector.footprintStepMeters,
            gapBreakMeters: 8_000
        )
        return MapCoordAdapter.forMapKit(sampled, countryISO2: countryISO2)
    }

    private static func uniformSampledCoords(
        _ coords: [CLLocationCoordinate2D],
        maxPoints: Int
    ) -> [CLLocationCoordinate2D] {
        guard maxPoints >= 2 else { return coords }
        guard coords.count > maxPoints else { return coords }

        let n = coords.count
        return (0..<maxPoints).map { index in
            let t = Double(index) / Double(maxPoints - 1)
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            return coords[min(max(idx, 0), n - 1)]
        }
    }
}
