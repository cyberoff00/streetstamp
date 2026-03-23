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
        let city: String = {
            if let name = item.cityName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            let rawCityID = item.cityID ?? ""
            return rawCityID.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        }()
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
    private static let lastUploadedTokenKey = "streetstamps.apns.last_uploaded_token"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - Remote Notification Registration

    /// Call this after the user logs in or the app becomes active with a valid session.
    static func registerForRemoteNotificationsIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private static let pendingTokenKey = "streetstamps.apns.pending_device_token"

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: Self.pendingTokenKey)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] registration failed: \(error.localizedDescription)")
    }

    /// Call this whenever an access token becomes available (login, app activate, etc.)
    static func uploadPendingPushTokenIfNeeded(accessToken: String?) {
        let defaults = UserDefaults.standard
        guard let hex = defaults.string(forKey: pendingTokenKey), !hex.isEmpty else { return }
        // Already uploaded this exact token
        if defaults.string(forKey: lastUploadedTokenKey) == hex { return }
        guard BackendConfig.isEnabled, let accessToken, !accessToken.isEmpty else { return }

        Task {
            do {
                try await BackendAPIClient.shared.registerPushToken(token: accessToken, pushToken: hex)
                defaults.set(hex, forKey: lastUploadedTokenKey)
            } catch {
                print("[APNs] token upload failed: \(error.localizedDescription)")
            }
        }
    }

    /// Clear cached token on logout so the next login re-uploads.
    static func clearCachedPushToken() {
        UserDefaults.standard.removeObject(forKey: lastUploadedTokenKey)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        // Handle "Continue" action from stationary reminder notification.
        if response.actionIdentifier == "LONG_STATIONARY_CONTINUE" {
            await MainActor.run {
                TrackingService.shared.userDidConfirmContinueTracking()
            }
            return
        }

        guard let url = await MainActor.run(
            resultType: URL?.self,
            body: {
                PostcardNotificationBridge.shared.deepLinkURL(from: response.notification.request.content.userInfo)
            }
        ) else {
            return
        }
        await MainActor.run {
            if let intent = AppDeepLinkStore.parsePostcardInbox(from: url) {
                AppFlowCoordinator.shared.requestOpenPostcardSidebar(intent)
            } else {
                UIApplication.shared.open(url)
            }
        }
    }
}
