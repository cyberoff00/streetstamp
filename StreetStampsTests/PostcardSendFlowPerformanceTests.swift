import XCTest
@testable import StreetStamps

final class PostcardSendFlowPerformanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BackendConfig.baseURLString = "https://example.com"
        BackendAPIClient.shared.resetTestingTransport()
    }

    override func tearDown() {
        BackendAPIClient.shared.resetTestingTransport()
        super.tearDown()
    }

    @MainActor
    func test_enqueueSend_doesNotBlockOnPostSendInboxRefresh() async throws {
        let postcardCenter = PostcardCenter(userID: "perf-user-\(UUID().uuidString)")
        let localImageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("postcard-test-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: localImageURL, options: .atomic)

        BackendAPIClient.shared.installTestingTransport { request in
            let path = request.url?.path ?? ""
            let url = try XCTUnwrap(request.url)
            let headers = ["Content-Type": "application/json"]

            if path == "/v1/media/upload" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
                let body = #"{"objectKey":"obj-1","url":"https://example.com/postcard.jpg"}"#.data(using: .utf8)!
                return (body, response)
            }

            if path == "/v1/postcards/send" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
                let body = #"{"messageID":"msg-1","sentAt":"2026-01-01T00:00:00.000Z"}"#.data(using: .utf8)!
                return (body, response)
            }

            if path == "/v1/postcards" {
                try await Task.sleep(nanoseconds: 700_000_000)
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
                let body = #"{"items":[]}"#.data(using: .utf8)!
                return (body, response)
            }

            XCTFail("Unexpected request path: \(path)")
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: headers)!
            let body = #"{"message":"not found"}"#.data(using: .utf8)!
            return (body, response)
        }

        let draft = postcardCenter.createDraft(
            toUserID: "friend-1",
            toDisplayName: "Friend",
            cityID: "city-1",
            cityName: "London",
            photoLocalPath: localImageURL.path,
            message: "hello"
        )

        let start = Date()
        await postcardCenter.enqueueSend(
            draftID: draft.draftID,
            token: "token-1",
            allowedCityIDs: ["city-1"],
            cityJourneyCount: 1
        )
        let elapsed = Date().timeIntervalSince(start)

        let updated = try XCTUnwrap(postcardCenter.drafts.first(where: { $0.draftID == draft.draftID }))
        XCTAssertEqual(updated.status, .sent)
        XCTAssertNotNil(updated.sendDiagnostics)
        XCTAssertGreaterThan(updated.sendDiagnostics?.uploadDurationMs ?? 0, 0)
        XCTAssertGreaterThan(updated.sendDiagnostics?.sendRequestDurationMs ?? 0, 0)
        XCTAssertGreaterThan(updated.sendDiagnostics?.totalDurationMs ?? 0, 0)
        XCTAssertLessThan(
            elapsed,
            1.0,
            "enqueueSend should return without waiting for sent/received refresh requests to finish"
        )
    }
}
