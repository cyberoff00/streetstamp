import Foundation
import MapKit
import CoreLocation

actor CityBoundaryService {
    static let shared = CityBoundaryService()

    private var cache: [String: [CLLocationCoordinate2D]] = [:]
    private var inFlight: [String: [CheckedContinuation<[CLLocationCoordinate2D]?, Never>]] = [:]

    private let maxFetchSpanDegrees: CLLocationDegrees = 4.5
    private let maxAnchorDistanceMeters: CLLocationDistance = 250_000

    func boundaryPolygon(
        cityKey: String,
        cityName: String,
        countryISO2: String?,
        anchor: CLLocationCoordinate2D?
    ) async -> [CLLocationCoordinate2D]? {
        if let cached = cache[cityKey] { return cached }

        if inFlight[cityKey] != nil {
            return await withCheckedContinuation { cont in
                inFlight[cityKey]?.append(cont)
            }
        }
        inFlight[cityKey] = []

        let polygon = await fetchBoundaryPolygon(cityName: cityName, countryISO2: countryISO2, anchor: anchor)
        if let polygon {
            cache[cityKey] = polygon
        }

        let waiters = inFlight[cityKey] ?? []
        inFlight[cityKey] = nil
        waiters.forEach { $0.resume(returning: polygon) }
        return polygon
    }

    private func fetchBoundaryPolygon(
        cityName: String,
        countryISO2: String?,
        anchor: CLLocationCoordinate2D?
    ) async -> [CLLocationCoordinate2D]? {
        let trimmed = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let query: String = {
            if let iso = countryISO2?.trimmingCharacters(in: .whitespacesAndNewlines), !iso.isEmpty {
                return "\(trimmed), \(iso)"
            }
            return trimmed
        }()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let anchor {
            request.region = MKCoordinateRegion(
                center: anchor,
                span: MKCoordinateSpan(latitudeDelta: 1.8, longitudeDelta: 1.8)
            )
        }

        let response: MKLocalSearch.Response? = await withCheckedContinuation { cont in
            MKLocalSearch(request: request).start { resp, _ in
                cont.resume(returning: resp)
            }
        }
        guard let response else { return nil }

        let region = response.boundingRegion
        guard region.span.latitudeDelta.isFinite, region.span.longitudeDelta.isFinite else { return nil }
        guard region.span.latitudeDelta > 0, region.span.longitudeDelta > 0 else { return nil }
        guard region.span.latitudeDelta <= maxFetchSpanDegrees, region.span.longitudeDelta <= maxFetchSpanDegrees else { return nil }

        if let anchor {
            let a = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            let c = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            if c.distance(from: a) > maxAnchorDistanceMeters { return nil }
        }

        return regionPolygon(region)
    }

    private func regionPolygon(_ region: MKCoordinateRegion) -> [CLLocationCoordinate2D] {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        return [
            CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            CLLocationCoordinate2D(latitude: minLat, longitude: maxLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: minLon)
        ]
    }
}
