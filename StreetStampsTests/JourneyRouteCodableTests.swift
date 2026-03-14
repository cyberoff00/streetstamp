import XCTest
@testable import StreetStamps

final class JourneyRouteCodableTests: XCTestCase {
    func test_journeyMemoryLocationMetadata_survives_codable_roundTrip() throws {
        let timestamp = Date(timeIntervalSince1970: 1_710_000_000)
        let route = JourneyRoute(
            memories: [
                JourneyMemory(
                    id: "memory-1",
                    timestamp: timestamp,
                    title: "Clifftop",
                    notes: "Wind picked up quickly",
                    imageData: nil,
                    imagePaths: ["memory-1.jpg"],
                    cityKey: "paris_fr",
                    cityName: "Paris",
                    coordinate: (48.8566, 2.3522),
                    type: .memory,
                    locationStatus: .fallback,
                    locationSource: .trackNearestByTime
                )
            ]
        )

        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(JourneyRoute.self, from: data)

        XCTAssertEqual(decoded.memories.first?.locationStatus, .fallback)
        XCTAssertEqual(decoded.memories.first?.locationSource, .trackNearestByTime)
    }

    func test_journeyMemoryLocationMetadata_defaults_whenFieldsAreAbsent() throws {
        let legacyJSON = """
        {
          "id": "route-1",
          "startTime": 1710000000,
          "endTime": 1710000300,
          "distance": 3500,
          "elevationGain": 0,
          "elevationLoss": 0,
          "isTooShort": false,
          "coordinates": [],
          "memories": [
            {
              "id": "memory-legacy",
              "timestamp": 1710000010,
              "title": "Legacy Memory",
              "notes": "Decoded from old payload",
              "coordinateLat": 48.8566,
              "coordinateLon": 2.3522,
              "type": "memory"
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(JourneyRoute.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded.memories.first?.locationStatus, .resolved)
        XCTAssertEqual(decoded.memories.first?.locationSource, .legacyCoordinate)
    }

    func test_overallMemoryImagePaths_survive_codable_roundTrip() throws {
        let route = JourneyRoute(
            distance: 3_500,
            memories: [],
            overallMemory: "Windy bridge walk",
            overallMemoryImagePaths: ["overall-1.jpg", "overall-2.jpg"]
        )

        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(JourneyRoute.self, from: data)

        XCTAssertEqual(decoded.overallMemory, "Windy bridge walk")
        XCTAssertEqual(decoded.overallMemoryImagePaths, ["overall-1.jpg", "overall-2.jpg"])
    }

    func test_hasJourneyMemoryListContent_isTrueForTrimmedOverallMemoryWithoutJourneyMemories() {
        let route = JourneyRoute(
            memories: [],
            overallMemory: "  Quiet sunset by the river  "
        )

        XCTAssertTrue(route.hasJourneyMemoryListContent)
    }

    func test_hasJourneyMemoryListContent_isFalseWhenNoJourneyMemoriesAndOverallMemoryIsBlank() {
        let route = JourneyRoute(
            memories: [],
            overallMemory: " \n "
        )

        XCTAssertFalse(route.hasJourneyMemoryListContent)
    }
}
