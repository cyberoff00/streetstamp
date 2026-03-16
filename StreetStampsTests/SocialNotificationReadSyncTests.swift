import XCTest
@testable import StreetStamps

final class SocialNotificationReadSyncTests: XCTestCase {
    func test_applying_marks_specified_notifications_read() {
        let updated = SocialNotificationReadSync.applying(
            .init(ids: ["n2"], markAll: false),
            to: sampleItems()
        )

        XCTAssertFalse(updated[0].read)
        XCTAssertTrue(updated[1].read)
        XCTAssertTrue(updated[2].read)
    }

    func test_applying_marks_all_notifications_read_when_markAll_enabled() {
        let updated = SocialNotificationReadSync.applying(
            .init(ids: [], markAll: true),
            to: sampleItems()
        )

        XCTAssertTrue(updated.allSatisfy(\.read))
    }

    private func sampleItems() -> [BackendNotificationItem] {
        [
            makeItem(id: "n1", read: false),
            makeItem(id: "n2", read: false),
            makeItem(id: "n3", read: true)
        ]
    }

    private func makeItem(id: String, read: Bool) -> BackendNotificationItem {
        BackendNotificationItem(
            id: id,
            type: "friend_request",
            fromUserID: nil,
            fromDisplayName: nil,
            journeyID: nil,
            journeyTitle: nil,
            message: "hello",
            createdAt: Date(timeIntervalSince1970: 1),
            read: read,
            postcardMessageID: nil,
            cityID: nil,
            cityName: nil,
            photoURL: nil,
            messageText: nil
        )
    }
}
