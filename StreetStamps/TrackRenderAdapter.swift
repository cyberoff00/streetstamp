import Foundation
import CoreLocation
import MapKit

enum UnifiedLifelogRenderProvider {
    @MainActor
    static func trackRenderEvents(journeyStore: JourneyStore, lifelogStore: LifelogStore) -> [TrackRenderEvent] {
        trackRenderEvents(
            journeyEvents: journeyStore.trackRenderEvents(),
            passiveEvents: lifelogStore.trackRenderEvents()
        )
    }

    static func trackRenderEvents(
        journeyEvents: [TrackRenderEvent],
        passiveEvents: [TrackRenderEvent]
    ) -> [TrackRenderEvent] {
        let filtered = excludeArchivedPassiveDuplicates(
            journeyEvents: journeyEvents,
            passiveEvents: passiveEvents
        )
        let merged = journeyEvents + filtered
        return merged.sorted(by: stableEventOrdering)
    }

    /// Journey coordinates are archived into LifelogStore as passive points
    /// by `archiveJourneyPointsIfNeeded`. Without dedup, both the original
    /// journey events and the archived passive copies are rendered, creating
    /// overlapping/divergent polylines (multiple lines or "rays" from shared
    /// points). This removes passive events whose timestamps fall within a
    /// journey's time range.
    private static func excludeArchivedPassiveDuplicates(
        journeyEvents: [TrackRenderEvent],
        passiveEvents: [TrackRenderEvent]
    ) -> [TrackRenderEvent] {
        guard !journeyEvents.isEmpty, !passiveEvents.isEmpty else {
            return passiveEvents
        }

        // Build sorted, merged time ranges covered by journeys.
        var ranges: [(start: Date, end: Date)] = []
        var currentStart: Date?
        var currentEnd: Date?

        let sorted = journeyEvents.sorted { $0.timestamp < $1.timestamp }
        for event in sorted {
            let ts = event.timestamp
            if let s = currentStart, let e = currentEnd {
                // Extend if contiguous (within 2s tolerance for interpolated timestamps).
                if ts <= e.addingTimeInterval(2) {
                    currentEnd = max(e, ts)
                } else {
                    ranges.append((start: s, end: e))
                    currentStart = ts
                    currentEnd = ts
                }
            } else {
                currentStart = ts
                currentEnd = ts
            }
        }
        if let s = currentStart, let e = currentEnd {
            ranges.append((start: s, end: e))
        }

        guard !ranges.isEmpty else { return passiveEvents }

        // Binary search helper: does `ts` fall inside any journey range?
        func isInsideJourneyRange(_ ts: Date) -> Bool {
            var lo = 0, hi = ranges.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                let r = ranges[mid]
                if ts < r.start {
                    hi = mid - 1
                } else if ts > r.end {
                    lo = mid + 1
                } else {
                    return true
                }
            }
            return false
        }

        return passiveEvents.filter { !isInsideJourneyRange($0.timestamp) }
    }

    static func trackRenderEventsAsync(
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore
    ) async -> [TrackRenderEvent] {
        async let journeyEvents = journeyStore.trackRenderEventsAsync()
        async let passiveEvents = lifelogStore.trackRenderEventsAsync()
        let resolvedJourneyEvents = await journeyEvents
        let resolvedPassiveEvents = await passiveEvents
        return await Task.detached(priority: .utility) {
            trackRenderEvents(
                journeyEvents: resolvedJourneyEvents,
                passiveEvents: resolvedPassiveEvents
            )
        }.value
    }

    @MainActor
    static func segments(
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        zoom: Int = TrackRenderAdapter.unifiedRenderZoom,
        day: Date? = nil,
        sourceFilter: Set<TrackSourceType>? = nil
    ) -> [TrackTileSegment] {
        segments(
            journeyEvents: journeyStore.trackRenderEvents(),
            passiveEvents: lifelogStore.trackRenderEvents(),
            zoom: zoom,
            day: day,
            sourceFilter: sourceFilter
        )
    }

    static func segments(
        journeyEvents: [TrackRenderEvent],
        passiveEvents: [TrackRenderEvent],
        zoom: Int = TrackRenderAdapter.unifiedRenderZoom,
        day: Date? = nil,
        sourceFilter: Set<TrackSourceType>? = nil
    ) -> [TrackTileSegment] {
        let segments = TrackTileBuilder.buildSegments(
            events: trackRenderEvents(journeyEvents: journeyEvents, passiveEvents: passiveEvents),
            zoom: zoom
        )
        return TrackRenderAdapter.filteredSegments(from: segments, source: sourceFilter, day: day)
    }

    static func segmentsAsync(
        journeyStore: JourneyStore,
        lifelogStore: LifelogStore,
        zoom: Int = TrackRenderAdapter.unifiedRenderZoom,
        day: Date? = nil,
        sourceFilter: Set<TrackSourceType>? = nil
    ) async -> [TrackTileSegment] {
        async let journeyEvents = journeyStore.trackRenderEventsAsync()
        async let passiveEvents = lifelogStore.trackRenderEventsAsync()
        let resolvedJourneyEvents = await journeyEvents
        let resolvedPassiveEvents = await passiveEvents
        return await Task.detached(priority: .utility) {
            segments(
                journeyEvents: resolvedJourneyEvents,
                passiveEvents: resolvedPassiveEvents,
                zoom: zoom,
                day: day,
                sourceFilter: sourceFilter
            )
        }.value
    }

    private static func stableEventOrdering(_ lhs: TrackRenderEvent, _ rhs: TrackRenderEvent) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        if lhs.sourceType != rhs.sourceType {
            return lhs.sourceType.rawValue < rhs.sourceType.rawValue
        }
        if lhs.coordinate.lat != rhs.coordinate.lat {
            return lhs.coordinate.lat < rhs.coordinate.lat
        }
        return lhs.coordinate.lon < rhs.coordinate.lon
    }
}

enum TrackRenderAdapter {
    static let unifiedRenderZoom = 10

    static func globeSegments(
        from events: [TrackRenderEvent],
        zoom: Int = unifiedRenderZoom,
        sourceFilter: Set<TrackSourceType>? = nil
    ) -> [TrackTileSegment] {
        filteredSegments(
            from: TrackTileBuilder.buildSegments(events: events, zoom: zoom),
            source: sourceFilter,
            day: nil
        )
        .filter { $0.coordinates.count >= 2 }
        .sorted {
            if $0.startTimestamp != $1.startTimestamp {
                return $0.startTimestamp < $1.startTimestamp
            }
            if $0.endTimestamp != $1.endTimestamp {
                return $0.endTimestamp < $1.endTimestamp
            }
            return $0.sourceType.rawValue < $1.sourceType.rawValue
        }
    }

    static func globePassiveSegments(
        from events: [TrackRenderEvent],
        zoom: Int = unifiedRenderZoom
    ) -> [TrackTileSegment] {
        globeSegments(from: events, zoom: zoom, sourceFilter: [.passive])
    }

    /// Globe-level maximum coordinate count. At world zoom the fog reveal
    /// corridor is wide, so sub-100m precision is invisible. Keeping the
    /// total under this cap ensures draw() stays under 16ms per frame.
    private static let globeMaxTotalCoords = 30_000

    static func globeJourneys(
        from segments: [TrackTileSegment],
        passiveCountryRuns: [LifelogAttributedCoordinateRun] = [],
        countryISO2: String?
    ) -> [JourneyRoute] {
        let lifelogName = L10n.t("tab_lifelog")

        let validCountryRuns = passiveCountryRuns.filter { $0.coordsWGS84.count >= 2 }
        let tilePassiveSegments = segments.filter { $0.sourceType == .passive && $0.coordinates.count >= 2 }

        let useCountryRuns = !validCountryRuns.isEmpty
            && validCountryRuns.count >= tilePassiveSegments.count

        if !useCountryRuns {
            let filtered = segments.filter { $0.coordinates.count >= 2 }
            guard !filtered.isEmpty else { return [] }
            let capped = globeDownsample(filtered.map(\.coordinates))
            return capped.enumerated().map { index, coords in
                makeGlobeJourney(
                    id: "track.tile.segment.all.\(index)",
                    lifelogName: lifelogName,
                    countryISO2: countryISO2,
                    coordinates: coords
                )
            }
        }

        // Non-passive segments are actual journey routes — always include them.
        // Country runs replace passive tile segments (better attribution, no duplication),
        // but they do NOT contain journey routes that weren't archived to lifelog.
        let nonPassiveSegments = segments.filter { $0.sourceType != .passive && $0.coordinates.count >= 2 }
        let nonPassiveCoords = globeDownsample(nonPassiveSegments.map(\.coordinates))
        let nonPassiveRoutes = nonPassiveCoords.enumerated().map { index, coords in
            makeGlobeJourney(
                id: "track.tile.segment.journey.\(index)",
                lifelogName: lifelogName,
                countryISO2: countryISO2,
                coordinates: coords
            )
        }

        let passiveCoordArrays: [[CoordinateCodable]] = validCountryRuns.map { run in
            run.coordsWGS84.map { CoordinateCodable(lat: $0.latitude, lon: $0.longitude) }
        }
        let passiveCapped = globeDownsample(passiveCoordArrays)
        let passiveRoutes = passiveCapped.enumerated().map { index, coords in
            makeGlobeJourney(
                id: "track.tile.segment.passive.\(index)",
                lifelogName: lifelogName,
                countryISO2: validCountryRuns.indices.contains(index) ? validCountryRuns[index].countryISO2 : countryISO2,
                coordinates: coords
            )
        }

        return nonPassiveRoutes + passiveRoutes
    }

    /// Primary tolerance: keep detail above ~50m deviation.
    private static let globeRdpEpsilonDegrees: Double = 50.0 / 111_000.0
    /// Emergency ceiling — escalate epsilon if even the fixed pass leaves more
    /// than this many total points (pathological heavy users).
    private static let globeEmergencyPointCap: Int = 120_000

    /// Downsamples coordinate arrays with Ramer-Douglas-Peucker at a fixed ~50m
    /// tolerance. Preserves city-scale detail. Falls back to escalating epsilon
    /// only if the emergency ceiling is exceeded.
    private static func globeDownsample(_ arrays: [[CoordinateCodable]]) -> [[CoordinateCodable]] {
        var result = arrays.map { rdpSimplify($0, epsilon: globeRdpEpsilonDegrees) }
        var total = result.reduce(0) { $0 + $1.count }
        guard total > globeEmergencyPointCap else { return result }

        var epsilon = globeRdpEpsilonDegrees
        for _ in 0..<20 {
            epsilon *= 1.8
            result = arrays.map { rdpSimplify($0, epsilon: epsilon) }
            total = result.reduce(0) { $0 + $1.count }
            if total <= globeEmergencyPointCap { break }
        }
        return result
    }

    /// Iterative Ramer-Douglas-Peucker — never recurses, so it's safe for
    /// multi-thousand-point journeys. Epsilon is in degrees.
    private static func rdpSimplify(_ coords: [CoordinateCodable], epsilon: Double) -> [CoordinateCodable] {
        let n = coords.count
        guard n > 2 else { return coords }

        var keep = Array(repeating: false, count: n)
        keep[0] = true
        keep[n - 1] = true

        // Explicit stack of (start, end) inclusive index ranges to process.
        var stack: [(Int, Int)] = [(0, n - 1)]
        stack.reserveCapacity(32)

        while let (start, end) = stack.popLast() {
            guard end - start >= 2 else { continue }

            let a = coords[start]
            let b = coords[end]
            var maxDist = 0.0
            var maxIdx = start
            for i in (start + 1)..<end {
                let d = perpendicularDistance(coords[i], lineStart: a, lineEnd: b)
                if d > maxDist {
                    maxDist = d
                    maxIdx = i
                }
            }

            if maxDist > epsilon {
                keep[maxIdx] = true
                stack.append((start, maxIdx))
                stack.append((maxIdx, end))
            }
        }

        var out: [CoordinateCodable] = []
        out.reserveCapacity(n)
        for i in 0..<n where keep[i] {
            out.append(coords[i])
        }
        return out
    }

    private static func perpendicularDistance(_ point: CoordinateCodable, lineStart: CoordinateCodable, lineEnd: CoordinateCodable) -> Double {
        let dx = lineEnd.lon - lineStart.lon
        let dy = lineEnd.lat - lineStart.lat
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else {
            let px = point.lon - lineStart.lon
            let py = point.lat - lineStart.lat
            return sqrt(px * px + py * py)
        }
        let t = max(0, min(1, ((point.lon - lineStart.lon) * dx + (point.lat - lineStart.lat) * dy) / lengthSq))
        let projLon = lineStart.lon + t * dx
        let projLat = lineStart.lat + t * dy
        let ex = point.lon - projLon
        let ey = point.lat - projLat
        return sqrt(ex * ex + ey * ey)
    }

    static func polylineCoordinates(
        from segments: [TrackTileSegment],
        source: TrackSourceType? = nil,
        day: Date? = nil,
        maxPoints: Int
    ) -> [CLLocationCoordinate2D] {
        let filteredByDay = filter(segments: segments, for: day)
        let merged: [CoordinateCodable]
        if let source {
            merged = filteredByDay
                .filter { $0.sourceType == source }
                .flatMap(\.coordinates)
        } else {
            merged = filteredByDay.flatMap(\.coordinates)
        }

        guard !merged.isEmpty else { return [] }
        let sampled = downsample(coords: merged, maxPoints: max(maxPoints, 2))
        return sampled.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    static func rawCoordinates(
        from segments: [TrackTileSegment],
        source: TrackSourceType? = nil,
        day: Date? = nil
    ) -> [CLLocationCoordinate2D] {
        let filteredByDay = filter(segments: segments, for: day)
        let merged: [CoordinateCodable]
        if let source {
            merged = filteredByDay
                .filter { $0.sourceType == source }
                .flatMap(\.coordinates)
        } else {
            merged = filteredByDay.flatMap(\.coordinates)
        }
        return merged.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    static func rawCoordinateRuns(
        from segments: [TrackTileSegment],
        source: TrackSourceType? = nil,
        day: Date? = nil
    ) -> [[CLLocationCoordinate2D]] {
        let filteredByDay = filter(segments: segments, for: day)
        let filteredBySource: [TrackTileSegment]
        if let source {
            filteredBySource = filteredByDay.filter { $0.sourceType == source }
        } else {
            filteredBySource = filteredByDay
        }

        return filteredBySource.compactMap { segment in
            let coords = segment.coordinates.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
            return coords.isEmpty ? nil : coords
        }
    }

    static func filteredSegments(
        from segments: [TrackTileSegment],
        source: Set<TrackSourceType>? = nil,
        day: Date? = nil
    ) -> [TrackTileSegment] {
        let filteredByDay = filter(segments: segments, for: day)
        guard let source else { return filteredByDay }
        return filteredByDay.filter { source.contains($0.sourceType) }
    }

    static func viewport(from region: MKCoordinateRegion?) -> TrackTileViewport? {
        guard let region else { return nil }
        let halfLat = region.span.latitudeDelta / 2.0
        let halfLon = region.span.longitudeDelta / 2.0
        return TrackTileViewport(
            minLat: region.center.latitude - halfLat,
            maxLat: region.center.latitude + halfLat,
            minLon: region.center.longitude - halfLon,
            maxLon: region.center.longitude + halfLon
        )
    }

    static func segmentIntersectsViewport(_ segment: TrackTileSegment, viewport: TrackTileViewport) -> Bool {
        guard !segment.coordinates.isEmpty else { return false }

        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for coord in segment.coordinates {
            minLat = min(minLat, coord.lat)
            maxLat = max(maxLat, coord.lat)
            minLon = min(minLon, coord.lon)
            maxLon = max(maxLon, coord.lon)
        }

        return !(maxLat < viewport.minLat ||
                 minLat > viewport.maxLat ||
                 maxLon < viewport.minLon ||
                 minLon > viewport.maxLon)
    }

    static func zoomForLifelogLOD(_ lodLevel: Int) -> Int {
        _ = lodLevel
        return unifiedRenderZoom
    }

    private static func filter(segments: [TrackTileSegment], for day: Date?) -> [TrackTileSegment] {
        guard let day else { return segments }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return segments.compactMap { clip($0, start: start, end: end) }
    }

    private static func clip(_ segment: TrackTileSegment, start: Date, end: Date) -> TrackTileSegment? {
        // No temporal overlap with target day.
        if !(segment.startTimestamp < end && segment.endTimestamp >= start) {
            return nil
        }
        // Fully inside target day, keep as-is.
        if segment.startTimestamp >= start && segment.endTimestamp < end {
            return segment
        }

        let coords = segment.coordinates
        guard coords.count >= 2 else { return nil }

        let totalSpan = max(0, segment.endTimestamp.timeIntervalSince(segment.startTimestamp))
        let denom = max(1, coords.count - 1)

        var kept: [CoordinateCodable] = []
        kept.reserveCapacity(coords.count)

        for (index, coord) in coords.enumerated() {
            let t = Double(index) / Double(denom)
            let ts = segment.startTimestamp.addingTimeInterval(totalSpan * t)
            if ts >= start && ts < end {
                kept.append(coord)
            }
        }

        guard kept.count >= 2 else { return nil }
        let clippedStart = max(start, segment.startTimestamp)
        let clippedEnd = min(end, segment.endTimestamp)
        return TrackTileSegment(
            id: segment.id,
            sourceType: segment.sourceType,
            coordinates: kept,
            startTimestamp: clippedStart,
            endTimestamp: clippedEnd
        )
    }

    private static func totalDistanceMeters(for coords: [CoordinateCodable]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var total: Double = 0
        for index in 1..<coords.count {
            let a = CLLocation(latitude: coords[index - 1].lat, longitude: coords[index - 1].lon)
            let b = CLLocation(latitude: coords[index].lat, longitude: coords[index].lon)
            total += b.distance(from: a)
        }
        return total
    }

    private static func makeGlobeJourney(
        id: String,
        lifelogName: String,
        countryISO2: String?,
        coordinates: [CoordinateCodable]
    ) -> JourneyRoute {
        var route = JourneyRoute()
        route.id = id
        route.cityName = lifelogName
        route.currentCity = lifelogName
        route.canonicalCity = lifelogName
        route.cityKey = "\(lifelogName)|"
        route.countryISO2 = countryISO2
        route.coordinates = coordinates
        route.thumbnailCoordinates = coordinates
        // Skip totalDistanceMeters — Globe fog rendering doesn't display
        // distance. Computing it for 25K+ segments with 240K+ coords was
        // taking minutes (CLLocation creation + Haversine per pair).
        route.distance = 0
        return route
    }

    private static func downsample(coords: [CoordinateCodable], maxPoints: Int) -> [CoordinateCodable] {
        guard coords.count > maxPoints else { return coords }
        let n = coords.count
        let m = maxPoints
        var out: [CoordinateCodable] = []
        out.reserveCapacity(m)

        for i in 0..<m {
            let t = Double(i) / Double(max(m - 1, 1))
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            out.append(coords[min(max(idx, 0), n - 1)])
        }

        var compact: [CoordinateCodable] = []
        compact.reserveCapacity(out.count)
        for c in out {
            if let last = compact.last, last == c { continue }
            compact.append(c)
        }
        return compact
    }
}
