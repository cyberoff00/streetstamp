import XCTest
@testable import StreetStamps

final class BackendAPIClientAuthErrorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BackendConfig.baseURLString = "https://example.com"
        BackendAPIClient.shared.resetTestingTransport()
    }

    override func tearDown() {
        BackendAPIClient.shared.resetTestingTransport()
        super.tearDown()
    }

    func test_login401PreservesServerMessage() async throws {
        BackendAPIClient.shared.installTestingTransport { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/login")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = #"{"message":"wrong email or password"}"#.data(using: .utf8)!
            return (body, response)
        }

        do {
            _ = try await BackendAPIClient.shared.login(email: "test@example.com", password: "wrong")
            XCTFail("Expected login to throw")
        } catch let error as BackendAPIError {
            guard case let .server(message) = error else {
                return XCTFail("Expected server error, got \(error)")
            }
            XCTAssertEqual(message, "wrong email or password")
        }
    }

    func test_protectedRequest401StillMapsToUnauthorized() async throws {
        BackendAPIClient.shared.installTestingTransport { request in
            XCTAssertEqual(request.url?.path, "/v1/friends")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = #"{"message":"unauthorized"}"#.data(using: .utf8)!
            return (body, response)
        }

        do {
            _ = try await BackendAPIClient.shared.fetchFriends(token: "expired-token")
            XCTFail("Expected fetchFriends to throw")
        } catch let error as BackendAPIError {
            guard case .unauthorized = error else {
                return XCTFail("Expected unauthorized error, got \(error)")
            }
        }
    }

    func test_postcardQuotaConflictPreservesServerCode() async throws {
        BackendAPIClient.shared.installTestingTransport { request in
            XCTAssertEqual(request.url?.path, "/v1/postcards/send")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 409,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = #"{"code":"city_friend_quota_exceeded","message":"postcard quota exceeded"}"#.data(using: .utf8)!
            return (body, response)
        }

        do {
            _ = try await BackendAPIClient.shared.sendPostcard(
                token: "test-token",
                req: SendPostcardRequest(
                    clientDraftID: "draft-1",
                    toUserID: "friend-1",
                    cityID: "paris",
                    cityName: "Paris",
                    messageText: "hello",
                    photoURL: "https://example.com/p.jpg",
                    allowedCityIDs: ["paris"]
                )
            )
            XCTFail("Expected postcard send to throw")
        } catch let error as BackendAPIError {
            guard case let .serverCode(code, message) = error else {
                return XCTFail("Expected serverCode error, got \(error)")
            }
            XCTAssertEqual(code, "city_friend_quota_exceeded")
            XCTAssertEqual(message, "postcard quota exceeded")
        }
    }
}
