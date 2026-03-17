import XCTest
@testable import StreetStamps

final class BackendAPIClientJourneyLikesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BackendConfig.baseURLString = "https://example.com"
        BackendAPIClient.shared.resetTestingTransport()
    }

    override func tearDown() {
        BackendAPIClient.shared.resetTestingTransport()
        super.tearDown()
    }

    func test_fetchJourneyLikers_usesDedicatedEndpointAndDecodesUsers() async throws {
        let likedAt = ISO8601DateFormatter.withFractional.string(from: Date(timeIntervalSince1970: 123))

        BackendAPIClient.shared.installTestingTransport { request in
            XCTAssertEqual(request.url?.path, "/v1/journeys/owner-1/journey-1/likes")
            XCTAssertEqual(request.httpMethod, "GET")

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            {
              "items": [
                {
                  "userID": "user-1",
                  "displayName": "Alice",
                  "likedAt": "\(likedAt)"
                }
              ]
            }
            """.data(using: .utf8)!
            return (body, response)
        }

        let likers = try await BackendAPIClient.shared.fetchJourneyLikers(
            token: "token-1",
            ownerUserID: "owner-1",
            journeyID: "journey-1"
        )

        XCTAssertEqual(likers.count, 1)
        XCTAssertEqual(likers.first?.id, "user-1")
        XCTAssertEqual(likers.first?.name, "Alice")
        XCTAssertEqual(
            likers.first?.likedAt.timeIntervalSince1970,
            123,
            accuracy: 0.001
        )
    }
}
