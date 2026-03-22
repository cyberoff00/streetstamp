import XCTest
@testable import StreetStamps

@MainActor
final class SocialNotificationStoreTests: XCTestCase {

    func test_applyReadSync_marksMatchingNotificationsAsRead() {
        let store = SocialNotificationStore()
        store.setNotifications([
            makeNotification(id: "a", read: false),
            makeNotification(id: "b", read: false),
            makeNotification(id: "c", read: true),
        ])
        XCTAssertEqual(store.unreadCount, 2)

        let note = Notification(
            name: .socialNotificationsDidMarkRead,
            object: nil,
            userInfo: ["ids": ["a"], "markAll": false]
        )
        store.applyReadSync(note)

        XCTAssertEqual(store.unreadCount, 1)
        XCTAssertTrue(store.notifications.first(where: { $0.id == "a" })?.read == true)
        XCTAssertTrue(store.notifications.first(where: { $0.id == "b" })?.read == false)
    }

    func test_applyReadSync_markAll_marksAllAsRead() {
        let store = SocialNotificationStore()
        store.setNotifications([
            makeNotification(id: "a", read: false),
            makeNotification(id: "b", read: false),
        ])
        XCTAssertEqual(store.unreadCount, 2)

        let note = Notification(
            name: .socialNotificationsDidMarkRead,
            object: nil,
            userInfo: ["ids": [String](), "markAll": true]
        )
        store.applyReadSync(note)

        XCTAssertEqual(store.unreadCount, 0)
    }

    func test_refresh_withNilToken_clearsNotifications() async {
        let store = SocialNotificationStore()
        store.setNotifications([makeNotification(id: "x", read: false)])

        await store.refresh(token: nil)

        XCTAssertTrue(store.notifications.isEmpty)
        XCTAssertEqual(store.unreadCount, 0)
    }

    func test_refresh_withEmptyToken_clearsNotifications() async {
        let store = SocialNotificationStore()
        store.setNotifications([makeNotification(id: "x", read: false)])

        await store.refresh(token: "")

        XCTAssertTrue(store.notifications.isEmpty)
        XCTAssertEqual(store.unreadCount, 0)
    }

    // MARK: - Helpers

    private func makeNotification(id: String, read: Bool) -> BackendNotificationItem {
        BackendNotificationItem(
            id: id,
            type: "journey_like",
            fromUserID: nil,
            fromDisplayName: nil,
            journeyID: nil,
            journeyTitle: nil,
            message: "",
            createdAt: Date(),
            read: read,
            postcardMessageID: nil,
            cityID: nil,
            cityName: nil,
            photoURL: nil,
            messageText: nil
        )
    }
}
