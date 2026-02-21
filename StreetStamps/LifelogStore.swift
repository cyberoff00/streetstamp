import Foundation
import CoreLocation
import Combine

@MainActor
final class LifelogStore: ObservableObject {
    @Published private(set) var coordinates: [CoordinateCodable] = []
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isEnabled: Bool = true
    @Published private(set) var availableDays: [Date] = []

    private struct PersistedPayload: Codable {
        var points: [LifelogTrackPoint]
        var coordinates: [CoordinateCodable]
        var isEnabled: Bool
    }

    private struct LifelogTrackPoint: Codable {
        var lat: Double
        var lon: Double
        var timestamp: Date

        init(lat: Double, lon: Double, timestamp: Date) {
            self.lat = lat
            self.lon = lon
            self.timestamp = timestamp
        }

        init(_ coord: CoordinateCodable, timestamp: Date) {
            self.lat = coord.lat
            self.lon = coord.lon
            self.timestamp = timestamp
        }

        var coord: CoordinateCodable {
            CoordinateCodable(lat: lat, lon: lon)
        }
    }

    private let minDistanceMeters: CLLocationDistance = 25
    private let minIntervalSeconds: TimeInterval = 30

    private var persistURL: URL
    private var bag = Set<AnyCancellable>()
    private var lastAccepted: CLLocation?
    private var lastAcceptedAt: Date = .distantPast
    private var cachedDistanceMeters: Double = 0
    private var cachedGlobePolyline: [CoordinateCodable] = []
    private var cachedGlobePolylineSourceCount: Int = -1
    private var downsampleCache: [Int: [CoordinateCodable]] = [:]
    private var downsampleCacheSourceCount: Int = -1
    private var points: [LifelogTrackPoint] = []
    private let syntheticMaxPoints = 320

    init(paths: StoragePath) {
        self.persistURL = paths.lifelogRouteURL
    }

    func rebind(paths: StoragePath) {
        persistURL = paths.lifelogRouteURL
        bag.removeAll()
        coordinates = []
        currentLocation = nil
        lastAccepted = nil
        lastAcceptedAt = .distantPast
        cachedDistanceMeters = 0
        cachedGlobePolyline = []
        cachedGlobePolylineSourceCount = -1
        downsampleCache = [:]
        downsampleCacheSourceCount = -1
        points = []
        availableDays = []
    }

    func load() {
        guard
            let data = try? Data(contentsOf: persistURL),
            let payload = try? JSONDecoder().decode(PersistedPayload.self, from: data)
        else {
            points = []
            coordinates = []
            isEnabled = true
            cachedDistanceMeters = 0
            cachedGlobePolyline = []
            cachedGlobePolylineSourceCount = 0
            downsampleCache = [:]
            downsampleCacheSourceCount = 0
            availableDays = []
            return
        }

        let loadedPoints: [LifelogTrackPoint]
        if !payload.points.isEmpty {
            loadedPoints = payload.points
        } else {
            // Legacy fallback: old payload has only coordinates.
            let fallbackTS = Date()
            loadedPoints = payload.coordinates.map { LifelogTrackPoint($0, timestamp: fallbackTS) }
        }
        points = loadedPoints
        coordinates = loadedPoints.map(\.coord)
        isEnabled = payload.isEnabled
        cachedDistanceMeters = totalDistanceMeters(coords: coordinates)
        cachedGlobePolyline = []
        cachedGlobePolylineSourceCount = -1
        downsampleCache = [:]
        downsampleCacheSourceCount = -1
        refreshAvailableDays()

        if let last = coordinates.last {
            lastAccepted = CLLocation(latitude: last.lat, longitude: last.lon)
            lastAcceptedAt = Date()
        }
    }

    func bind(to hub: LocationHub) {
        bag.removeAll()
        hub.locationStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                self?.ingest(loc)
            }
            .store(in: &bag)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        persistAsync()
    }

    var hasTrack: Bool { coordinates.count >= 2 }

    var syntheticJourney: JourneyRoute {
        var route = JourneyRoute()
        route.id = "lifelog.route.synthetic"
        route.cityName = "Lifelog"
        route.currentCity = "Lifelog"
        route.canonicalCity = "Lifelog"
        route.cityKey = "Lifelog|"
        let polyline = globePolyline(maxPoints: syntheticMaxPoints)
        route.coordinates = polyline
        route.thumbnailCoordinates = polyline
        route.distance = cachedDistanceMeters
        return route
    }

    private func ingest(_ loc: CLLocation) {
        currentLocation = loc
        guard isEnabled else { return }
        guard loc.horizontalAccuracy >= 0 else { return }

        if let last = lastAccepted {
            let moved = loc.distance(from: last)
            let dt = loc.timestamp.timeIntervalSince(lastAcceptedAt)
            if moved < minDistanceMeters && dt < minIntervalSeconds {
                return
            }
        }

        let c = CoordinateCodable(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
        if let prev = coordinates.last,
           abs(prev.lat - c.lat) < 0.0000005,
           abs(prev.lon - c.lon) < 0.0000005 {
            return
        }

        if let prev = coordinates.last {
            let a = CLLocation(latitude: prev.lat, longitude: prev.lon)
            let b = CLLocation(latitude: c.lat, longitude: c.lon)
            cachedDistanceMeters += b.distance(from: a)
        }

        coordinates.append(c)
        points.append(LifelogTrackPoint(c, timestamp: loc.timestamp))
        cachedGlobePolylineSourceCount = -1
        downsampleCacheSourceCount = -1
        lastAccepted = loc
        lastAcceptedAt = loc.timestamp
        refreshAvailableDays()
        persistAsync()
    }

    func sampledCoordinates(maxPoints: Int) -> [CoordinateCodable] {
        sampledCoordinates(day: nil, maxPoints: maxPoints)
    }

    func sampledCoordinates(day: Date?, maxPoints: Int) -> [CoordinateCodable] {
        if day != nil {
            return downsample(coords: coordsFor(day: day), maxPoints: max(maxPoints, 2))
        }
        let target = max(maxPoints, 2)
        if downsampleCacheSourceCount != coordinates.count {
            downsampleCache.removeAll(keepingCapacity: true)
            downsampleCacheSourceCount = coordinates.count
        }
        if let cached = downsampleCache[target] {
            return cached
        }
        let sampled = downsample(coords: coordinates, maxPoints: target)
        downsampleCache[target] = sampled
        return sampled
    }

    func mapPolyline(maxPoints: Int) -> [CLLocationCoordinate2D] {
        mapPolyline(day: nil, maxPoints: maxPoints)
    }

    func mapPolyline(day: Date?, maxPoints: Int) -> [CLLocationCoordinate2D] {
        sampledCoordinates(day: day, maxPoints: maxPoints).map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
    }

    private func persistAsync() {
        let payload = PersistedPayload(points: points, coordinates: coordinates, isEnabled: isEnabled)
        let url = persistURL
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(payload)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            } catch {
                print("❌ lifelog save failed:", error)
            }
        }
    }

    private func totalDistanceMeters(coords: [CoordinateCodable]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].lat, longitude: coords[i - 1].lon)
            let b = CLLocation(latitude: coords[i].lat, longitude: coords[i].lon)
            total += b.distance(from: a)
        }
        return total
    }

    private func globePolyline(maxPoints: Int) -> [CoordinateCodable] {
        guard maxPoints >= 2 else { return coordinates }
        if cachedGlobePolylineSourceCount == coordinates.count {
            return cachedGlobePolyline
        }

        let sampled = downsample(coords: coordinates, maxPoints: maxPoints)
        cachedGlobePolyline = sampled
        cachedGlobePolylineSourceCount = coordinates.count
        return sampled
    }

    private func coordsFor(day: Date?) -> [CoordinateCodable] {
        guard let day else { return coordinates }
        let cal = Calendar.current
        return points
            .filter { cal.isDate($0.timestamp, inSameDayAs: day) }
            .map(\.coord)
    }

    private func refreshAvailableDays() {
        let cal = Calendar.current
        let uniq = Set(points.map { cal.startOfDay(for: $0.timestamp) })
        availableDays = uniq.sorted(by: >)
    }

    private func downsample(coords: [CoordinateCodable], maxPoints: Int) -> [CoordinateCodable] {
        guard coords.count > maxPoints else { return coords }

        let n = coords.count
        var out: [CoordinateCodable] = []
        out.reserveCapacity(maxPoints)

        for i in 0..<maxPoints {
            let t = Double(i) / Double(maxPoints - 1)
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            out.append(coords[min(max(idx, 0), n - 1)])
        }

        var compact: [CoordinateCodable] = []
        compact.reserveCapacity(out.count)
        for c in out {
            if let last = compact.last, last.lat == c.lat, last.lon == c.lon {
                continue
            }
            compact.append(c)
        }
        return compact
    }
}
