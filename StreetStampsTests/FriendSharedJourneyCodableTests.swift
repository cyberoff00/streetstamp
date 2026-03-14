import XCTest
@testable import StreetStamps

final class FriendSharedJourneyCodableTests: XCTestCase {
    func test_friendSharedJourney_fromRoute_includesExplicitMemoryCoordinates() {
        let route = JourneyRoute(
            id: "journey-1",
            cityKey: "paris_fr",
            canonicalCity: "Paris",
            coordinates: [CoordinateCodable(lat: 48.8566, lon: 2.3522)],
            memories: [
                JourneyMemory(
                    id: "memory-1",
                    timestamp: Date(timeIntervalSince1970: 1_710_000_000),
                    title: "Bridge",
                    notes: "Blue hour",
                    imageData: nil,
                    remoteImageURLs: ["https://example.com/1.jpg"],
                    cityKey: "paris_fr",
                    cityName: "Paris",
                    coordinate: (48.857, 2.353),
                    type: .memory,
                    locationStatus: .resolved,
                    locationSource: .liveGPS
                )
            ]
        )

        let shared = FriendSharedJourney.from(route: route)

        XCTAssertEqual(shared.memories.first?.latitude, 48.857, accuracy: 0.0001)
        XCTAssertEqual(shared.memories.first?.longitude, 2.353, accuracy: 0.0001)
        XCTAssertEqual(shared.memories.first?.locationStatus, JourneyMemoryLocationStatus.resolved.rawValue)
    }

    func test_friendSharedJourney_decodesLegacyMemoryWithoutCoordinateFields() throws {
        let payload = """
        {
          "id": "journey-1",
          "title": "Paris",
          "distance": 1000,
          "visibility": "private",
          "routeCoordinates": [],
          "memories": [
            {
              "id": "memory-1",
              "title": "Bridge",
              "notes": "Blue hour",
              "timestamp": 1710000000,
              "imageURLs": ["https://example.com/1.jpg"]
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(FriendSharedJourney.self, from: Data(payload.utf8))

        XCTAssertNil(decoded.memories.first?.latitude)
        XCTAssertNil(decoded.memories.first?.longitude)
        XCTAssertNil(decoded.memories.first?.locationStatus)
        XCTAssertEqual(decoded.memories.first?.imageURLs, ["https://example.com/1.jpg"])
    }
}
