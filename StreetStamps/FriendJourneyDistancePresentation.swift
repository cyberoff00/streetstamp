import CoreLocation

enum FriendJourneyDistancePresentation {
    static func makeDistanceText(
        currentLocation: CLLocation?,
        lastKnownLocation: CLLocation?,
        journeyEndCoordinate: CLLocationCoordinate2D?
    ) -> String {
        guard let journeyEndCoordinate, journeyEndCoordinate.isValid else {
            return "unknown"
        }

        guard let userLocation = currentLocation ?? lastKnownLocation else {
            return "unknown"
        }

        let friendLocation = CLLocation(
            latitude: journeyEndCoordinate.latitude,
            longitude: journeyEndCoordinate.longitude
        )

        return formatDistance(userLocation.distance(from: friendLocation))
    }

    static func formatDistance(_ distance: CLLocationDistance) -> String {
        let normalizedDistance = max(0, distance)
        let kilometers = normalizedDistance / 1000.0

        if kilometers < 1 {
            return String(format: "%.0f m", normalizedDistance)
        } else if kilometers < 100 {
            return String(format: "%.1f km", kilometers)
        } else {
            return String(format: "%.0f km", kilometers)
        }
    }
}
