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
        let merged = journeyEvents + passiveEvents
        return merged.sorted(by: stableEventOrdering)
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

    static func globeJourneys(
        from segments: [TrackTileSegment],
        passiveCountryRuns: [LifelogAttributedCoordinateRun] = [],
        countryISO2: String?
    ) -> [JourneyRoute] {
        let lifelogName = L10n.t("tab_lifelog")

        if passiveCountryRuns.isEmpty {
            let filtered = segments.filter { $0.coordinates.count >= 2 }
            guard !filtered.isEmpty else { return [] }
            return filtered.enumerated().map { index, segment in
                makeGlobeJourney(
                    id: "track.tile.segment.\(segment.sourceType.rawValue).\(index)",
                    lifelogName: lifelogName,
                    countryISO2: countryISO2,
                    coordinates: segment.coordinates
                )
            }
        }

        let nonPassiveRoutes = segments
            .filter { $0.sourceType != .passive && $0.coordinates.count >= 2 }
            .enumerated()
            .map { index, segment in
                makeGlobeJourney(
                    id: "track.tile.segment.\(segment.sourceType.rawValue).\(index)",
                    lifelogName: lifelogName,
                    countryISO2: countryISO2,
                    coordinates: segment.coordinates
                )
            }

        let passiveRoutes = passiveCountryRuns
            .filter { $0.coordsWGS84.count >= 2 }
            .enumerated()
            .map { index, run in
                makeGlobeJourney(
                    id: "track.tile.segment.passive.\(index)",
                    lifelogName: lifelogName,
                    countryISO2: run.countryISO2,
                    coordinates: run.coordsWGS84.map {
                        CoordinateCodable(lat: $0.latitude, lon: $0.longitude)
                    }
                )
            }

        return nonPassiveRoutes + passiveRoutes
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
        route.distance = totalDistanceMeters(for: coordinates)
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
