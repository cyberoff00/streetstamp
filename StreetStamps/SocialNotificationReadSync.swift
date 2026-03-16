import Foundation

extension Notification.Name {
    static let socialNotificationsDidMarkRead = Notification.Name("socialNotificationsDidMarkRead")
}

enum SocialNotificationReadSync {
    struct Payload: Equatable {
        let ids: Set<String>
        let markAll: Bool
    }

    private static let idsUserInfoKey = "ids"
    private static let markAllUserInfoKey = "markAll"

    static func post(
        ids: [String],
        markAll: Bool,
        notificationCenter: NotificationCenter = .default
    ) {
        let payload = Payload(ids: Set(ids), markAll: markAll)
        notificationCenter.post(
            name: .socialNotificationsDidMarkRead,
            object: nil,
            userInfo: [
                idsUserInfoKey: Array(payload.ids),
                markAllUserInfoKey: payload.markAll
            ]
        )
    }

    static func payload(from notification: Notification) -> Payload? {
        guard let userInfo = notification.userInfo else { return nil }
        let ids = Set(userInfo[idsUserInfoKey] as? [String] ?? [])
        let markAll = userInfo[markAllUserInfoKey] as? Bool ?? false
        guard markAll || !ids.isEmpty else { return nil }
        return Payload(ids: ids, markAll: markAll)
    }

    static func applying(_ payload: Payload, to items: [BackendNotificationItem]) -> [BackendNotificationItem] {
        items.map { item in
            guard payload.markAll || payload.ids.contains(item.id) else { return item }
            guard !item.read else { return item }
            var copy = item
            copy.read = true
            return copy
        }
    }
}
