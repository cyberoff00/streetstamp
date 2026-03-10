import Foundation
import CoreLocation
import MapKit

struct LifelogAttributedCoordinateRun: Equatable, Sendable {
    let sourceType: TrackSourceType
    let coordsWGS84: [CLLocationCoordinate2D]
    let countryISO2: String?
    let cityKey: String?
    let startTimestamp: Date
    let endTimestamp: Date

    init(
        sourceType: TrackSourceType,
        coordsWGS84: [CLLocationCoordinate2D],
        countryISO2: String?,
        cityKey: String? = nil,
        startTimestamp: Date,
        endTimestamp: Date
    ) {
        self.sourceType = sourceType
        self.coordsWGS84 = coordsWGS84
        self.countryISO2 = countryISO2
        self.cityKey = cityKey
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
    }
}

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

struct LifelogSegmentedRenderGroup: Sendable {
    let sourceType: TrackSourceType
    let rawCoordsWGS84: [CLLocationCoordinate2D]
    let startTimestamp: Date
    let endTimestamp: Date
    let farRouteSegments: [RenderRouteSegment]
    let footprintRun: [CLLocationCoordinate2D]
}

struct LifelogSegmentedDaySnapshot: Sendable {
    let key: LifelogDaySnapshotKey
    let segments: [TrackTileSegment]
    let renderGroups: [LifelogSegmentedRenderGroup]
    let selectedDayCenterCoordinate: CLLocationCoordinate2D?

    var farRouteGroups: [[RenderRouteSegment]] {
        renderGroups.map(\.farRouteSegments)
    }

    var footprintGroups: [[CLLocationCoordinate2D]] {
        renderGroups.map(\.footprintRun)
    }

    var allDayRenderSnapshot: LifelogRenderSnapshot {
        let runs = renderGroups.map(\.rawCoordsWGS84)
        return LifelogRenderSnapshot(
            selectedDay: key.day,
            cachedPathCoordsWGS84: runs.flatMap { $0 },
            farRouteSegments: renderGroups.flatMap(\.farRouteSegments),
            footprintRuns: renderGroups.map(\.footprintRun).filter { !$0.isEmpty },
            selectedDayCenterCoordinate: selectedDayCenterCoordinate,
            isHighQuality: true
        )
    }

    func renderSnapshot(in viewport: TrackTileViewport?) -> LifelogRenderSnapshot {
        guard let viewport else { return allDayRenderSnapshot }

        let visibleIndices = renderGroups.indices.filter { index in
            LifelogRenderSnapshotBuilder.runIntersectsViewport(
                renderGroups[index].rawCoordsWGS84,
                viewport: viewport
            )
        }

        let visibleRuns = visibleIndices.map { renderGroups[$0].rawCoordsWGS84 }

        return LifelogRenderSnapshot(
            selectedDay: key.day,
            cachedPathCoordsWGS84: visibleRuns.flatMap { $0 },
            farRouteSegments: visibleIndices.flatMap { renderGroups[$0].farRouteSegments },
            footprintRuns: visibleIndices.compactMap { index in
                let run = renderGroups[index].footprintRun
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
        segments: [TrackTileSegment],
        passiveCountryRuns: [LifelogAttributedCoordinateRun] = []
    ) -> LifelogSegmentedDaySnapshot {
        let renderRuns = makeRenderRuns(
            key: key,
            segments: segments,
            passiveCountryRuns: passiveCountryRuns
        )
        let validRuns = renderRuns.filter { $0.coordsWGS84.count >= 2 }
        let perRunBudget = max(2, LifelogRenderSnapshotRequest.highQualityRenderMaxPoints / max(1, validRuns.count))

        let renderGroups = renderRuns.map { run in
            let farRouteSegments = buildFarRouteGroup(
                from: run.coordsWGS84,
                perRunBudget: perRunBudget,
                countryISO2: run.countryISO2,
                cityKey: run.cityKey
            )
            let footprintRun = buildFootprintGroup(
                from: run.coordsWGS84,
                countryISO2: run.countryISO2,
                cityKey: run.cityKey
            )
            return LifelogSegmentedRenderGroup(
                sourceType: run.sourceType,
                rawCoordsWGS84: run.coordsWGS84,
                startTimestamp: run.startTimestamp,
                endTimestamp: run.endTimestamp,
                farRouteSegments: farRouteSegments,
                footprintRun: footprintRun
            )
        }
        let center = renderRuns
            .last?
            .coordsWGS84
            .last
            .map {
                MapCoordAdapter.forMapKit(
                    $0,
                    countryISO2: renderRuns.last?.countryISO2,
                    cityKey: renderRuns.last?.cityKey
                )
            }

        return LifelogSegmentedDaySnapshot(
            key: key,
            segments: segments,
            renderGroups: renderGroups,
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
        latestSegments: [TrackTileSegment],
        passiveCountryRuns: [LifelogAttributedCoordinateRun] = []
    ) -> LifelogSegmentedDaySnapshot {
        if !passiveCountryRuns.isEmpty || existing.renderGroups.count != existing.segments.count {
            return buildDaySnapshot(
                key: latestKey,
                segments: latestSegments,
                passiveCountryRuns: passiveCountryRuns
            )
        }

        guard let reusePrefix = LifelogSegmentIncrementalMergePlanner.reusePrefixCount(
            existing: existing.segments,
            latest: latestSegments
        ) else {
            return buildDaySnapshot(
                key: latestKey,
                segments: latestSegments,
                passiveCountryRuns: passiveCountryRuns
            )
        }

        if reusePrefix == 0 {
            return buildDaySnapshot(
                key: latestKey,
                segments: latestSegments,
                passiveCountryRuns: passiveCountryRuns
            )
        }

        let tailSegments = Array(latestSegments.dropFirst(reusePrefix))
        if tailSegments.isEmpty, reusePrefix == existing.segments.count {
            return LifelogSegmentedDaySnapshot(
                key: latestKey,
                segments: existing.segments,
                renderGroups: existing.renderGroups,
                selectedDayCenterCoordinate: existing.selectedDayCenterCoordinate
            )
        }

        let tailSnapshot = buildDaySnapshot(
            key: latestKey,
            segments: tailSegments,
            passiveCountryRuns: passiveCountryRuns
        )
        let mergedSegments = Array(existing.segments.prefix(reusePrefix)) + tailSegments
        let mergedRenderGroups = Array(existing.renderGroups.prefix(reusePrefix)) + tailSnapshot.renderGroups
        let center = tailSnapshot.selectedDayCenterCoordinate ?? existing.selectedDayCenterCoordinate

        return LifelogSegmentedDaySnapshot(
            key: latestKey,
            segments: mergedSegments,
            renderGroups: mergedRenderGroups,
            selectedDayCenterCoordinate: center
        )
    }

    fileprivate static func runIntersectsViewport(
        _ run: [CLLocationCoordinate2D],
        viewport: TrackTileViewport
    ) -> Bool {
        let temp = TrackTileSegment(
            sourceType: .passive,
            coordinates: run.map { CoordinateCodable(lat: $0.latitude, lon: $0.longitude) }
        )
        return TrackRenderAdapter.segmentIntersectsViewport(temp, viewport: viewport)
    }

    private static func makeRenderRuns(
        key: LifelogDaySnapshotKey,
        segments: [TrackTileSegment],
        passiveCountryRuns: [LifelogAttributedCoordinateRun]
    ) -> [LifelogAttributedCoordinateRun] {
        let journeyRuns = segments
            .filter { $0.sourceType != .passive }
            .map { segment in
                LifelogAttributedCoordinateRun(
                    sourceType: segment.sourceType,
                    coordsWGS84: segment.coordinates.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                    },
                    countryISO2: key.countryISO2,
                    startTimestamp: segment.startTimestamp,
                    endTimestamp: segment.endTimestamp
                )
            }

        let passiveRuns: [LifelogAttributedCoordinateRun]
        if passiveCountryRuns.isEmpty {
            passiveRuns = segments
                .filter { $0.sourceType == .passive }
                .map { segment in
                    LifelogAttributedCoordinateRun(
                        sourceType: .passive,
                        coordsWGS84: segment.coordinates.map {
                            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                        },
                        countryISO2: key.countryISO2,
                        startTimestamp: segment.startTimestamp,
                        endTimestamp: segment.endTimestamp
                    )
                }
        } else {
            passiveRuns = passiveCountryRuns
        }

        return (journeyRuns + passiveRuns).sorted {
            if $0.startTimestamp != $1.startTimestamp {
                return $0.startTimestamp < $1.startTimestamp
            }
            return $0.endTimestamp < $1.endTimestamp
        }
    }

    private static func buildFarRouteGroup(
        from run: [CLLocationCoordinate2D],
        perRunBudget: Int,
        countryISO2: String?,
        cityKey: String?
    ) -> [RenderRouteSegment] {
        guard run.count >= 2 else { return [] }
        let sampled = uniformSampledCoords(run, maxPoints: perRunBudget)
        let input = RouteRenderingPipeline.Input(
            coordsWGS84: sampled,
            applyGCJForChina: false,
            gapDistanceMeters: 8_000,
            countryISO2: countryISO2,
            cityKey: cityKey
        )
        return RouteRenderingPipeline.buildSegments(input, surface: .mapKit).segments
    }

    private static func buildFootprintGroup(
        from run: [CLLocationCoordinate2D],
        countryISO2: String?,
        cityKey: String?
    ) -> [CLLocationCoordinate2D] {
        guard run.count > 1 else {
            return MapCoordAdapter.forMapKit(run, countryISO2: countryISO2, cityKey: cityKey)
        }

        let sampled = LifelogFootprintSampler.sample(
            route: run,
            stepMeters: LifelogRenderModeSelector.footprintStepMeters,
            gapBreakMeters: 8_000
        )
        return MapCoordAdapter.forMapKit(sampled, countryISO2: countryISO2, cityKey: cityKey)
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
