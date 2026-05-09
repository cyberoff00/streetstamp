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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
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
            content.badge = 1
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

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == "com.streetstamps.media-upload.v1" {
            BackendAPIClient.backgroundSessionCompletionHandler = completionHandler
        } else {
            completionHandler()
        }
    }

    // MARK: - Remote Notification Registration

    /// Call this after the user logs in or the app becomes active with a valid session.
    /// On a build-number transition we first call `unregisterForRemoteNotifications()`
    /// so iOS discards any cached APNs token from a previous build (e.g. a token
    /// registered against `aps-environment=development` that would now be a sandbox
    /// token on a production endpoint). Without this, iOS may keep returning the
    /// stale token across App Store updates and the device never starts receiving
    /// pushes again.
    static func registerForRemoteNotificationsIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async {
                let currentBuild = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
                let lastBuild = UserDefaults.standard.string(forKey: lastRegistrationBuildKey)
                if !currentBuild.isEmpty && lastBuild != currentBuild {
                    UIApplication.shared.unregisterForRemoteNotifications()
                    UserDefaults.standard.removeObject(forKey: pendingTokenKey)
                    UserDefaults.standard.set(currentBuild, forKey: lastRegistrationBuildKey)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                } else {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    private static let pendingTokenKey = "streetstamps.apns.pending_device_token"
    private static let lastRegistrationBuildKey = "streetstamps.apns.last_registration_build.v1"

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
    /// Unconditionally re-uploads the current device token on every call. The register
    /// endpoint is an idempotent upsert, and unconditional upload is the only reliable
    /// way to recover from server-side token deletion (e.g., APNs BadDeviceToken cleanup).
    static func uploadPendingPushTokenIfNeeded(accessToken: String?) {
        let defaults = UserDefaults.standard
        guard let hex = defaults.string(forKey: pendingTokenKey), !hex.isEmpty else { return }
        guard BackendConfig.isEnabled, let accessToken, !accessToken.isEmpty else { return }

        Task {
            do {
                try await BackendAPIClient.shared.registerPushToken(token: accessToken, pushToken: hex)
            } catch {
                print("[APNs] token upload failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
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
            guard FeatureFlagStore.shared.socialEnabled else { return }
            if let intent = AppDeepLinkStore.parsePostcardInbox(from: url) {
                AppFlowCoordinator.shared.requestOpenPostcardSidebar(intent)
            } else {
                UIApplication.shared.open(url)
            }
        }
    }
}
