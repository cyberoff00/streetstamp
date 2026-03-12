import Foundation
import UserNotifications
import UIKit

@MainActor
final class PostcardNotificationBridge {
    static let shared = PostcardNotificationBridge()

    private let askedPermissionKey = "streetstamps.postcard.notification_permission_asked.v1"
    private let deliveredIDsKey = "streetstamps.postcard.delivered_notification_ids.v1"

    private init() {}

    func requestAuthorizationIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: askedPermissionKey) else { return }
        defaults.set(true, forKey: askedPermissionKey)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func surfaceUnreadPostcardNotifications(_ items: [BackendNotificationItem]) {
        let unreadPostcards = items.filter { $0.type == "postcard_received" && !$0.read }
        guard !unreadPostcards.isEmpty else { return }

        requestAuthorizationIfNeeded()

        var delivered = deliveredIDs()
        for item in unreadPostcards where !delivered.contains(item.id) {
            scheduleLocalNotification(for: item)
            delivered.insert(item.id)
        }
        saveDeliveredIDs(delivered)
    }

    func deepLinkURL(from userInfo: [AnyHashable: Any]) -> URL? {
        guard let raw = userInfo["deepLink"] as? String else { return nil }
        return URL(string: raw)
    }

    private func scheduleLocalNotification(for item: BackendNotificationItem) {
        let deepLink = buildDeepLink(for: item)
        let title = (item.fromDisplayName?.isEmpty == false)
            ? String(format: NSLocalizedString("postcard_received_title_format", comment: ""), item.fromDisplayName!)
            : NSLocalizedString("postcard_received_title_fallback", comment: "")
        let city = CityDisplayTitlePresentation.title(
            cityKey: item.cityID,
            iso2: nil,
            fallbackTitle: item.cityName ?? item.cityID
        )
        let body = city.isEmpty
            ? item.message
            : String(format: NSLocalizedString("postcard_received_body_format", comment: ""), city)

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["deepLink": deepLink]

            let request = UNNotificationRequest(
                identifier: "postcard_\(item.id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func buildDeepLink(for item: BackendNotificationItem) -> String {
        var components = URLComponents()
        components.scheme = "streetstamps"
        components.host = "postcards"
        components.queryItems = [
            URLQueryItem(name: "box", value: "received"),
            URLQueryItem(name: "messageID", value: item.postcardMessageID)
        ]
        return components.string ?? "streetstamps://postcards?box=received"
    }

    private func deliveredIDs() -> Set<String> {
        let values = UserDefaults.standard.stringArray(forKey: deliveredIDsKey) ?? []
        return Set(values)
    }

    private func saveDeliveredIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: deliveredIDsKey)
    }
}

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let url = await MainActor.run(
            resultType: URL?.self,
            body: {
                PostcardNotificationBridge.shared.deepLinkURL(from: response.notification.request.content.userInfo)
            }
        ) else {
            return
        }
        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }
}
