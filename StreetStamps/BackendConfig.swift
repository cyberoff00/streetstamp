import Foundation

enum BackendConfig {
    private static let baseURLKey = "streetstamps.backend.base_url"
    private static let googleIOSClientIDKey = "streetstamps.google.ios_client_id"
    private static let firebaseInfoPlistName = "GoogleService-Info"
    private static let firebaseBackupEnabledKey = "streetstamps.firebase.backup_runtime_enabled"

    /// Domestic (China mainland) users connect directly to Tokyo server (gray-cloud, no Cloudflare proxy).
    /// Overseas users go through Cloudflare CDN (orange-cloud), origin now points to Tokyo.
    private static let domesticBaseURL = "https://jp-api.cyberkkk.cn"
    private static let globalBaseURL = "https://worldo-api.cyberkkk.cn"

    static var isChineseMainlandDevice: Bool {
        return TimeZone.current.identifier == "Asia/Shanghai"
    }

    static var defaultBaseURL: String {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !fromPlist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fromPlist
        }
        return isChineseMainlandDevice ? domesticBaseURL : globalBaseURL
    }

    /// The other endpoint to try when the primary one fails with a network error.
    static var fallbackBaseURL: String {
        return isChineseMainlandDevice ? globalBaseURL : domesticBaseURL
    }

    /// When fallback succeeds, remember it so subsequent requests go there directly.
    static func activateFallback() {
        UserDefaults.standard.set(fallbackBaseURL, forKey: baseURLKey)
        print("[BackendConfig] Activated fallback: \(fallbackBaseURL)")
    }

    /// Clear remembered URL on launch so it re-evaluates from scratch.
    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: baseURLKey)
    }

    static var baseURLString: String {
        get {
            let v = UserDefaults.standard.string(forKey: baseURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !v.isEmpty { return v }
            return defaultBaseURL
        }
        set {
            let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(v, forKey: baseURLKey)
        }
    }

    static var baseURL: URL? {
        let v = baseURLString
        guard !v.isEmpty else { return nil }
        return URL(string: v)
    }

    static var isEnabled: Bool { baseURL != nil }

    static var firebaseBackupRuntimeEnabled: Bool {
        if UserDefaults.standard.object(forKey: firebaseBackupEnabledKey) != nil {
            return UserDefaults.standard.bool(forKey: firebaseBackupEnabledKey)
        }
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "FIREBASE_BACKUP_RUNTIME_ENABLED") as? Bool {
            return fromPlist
        }
        return false
    }

    static var defaultGoogleIOSClientID: String {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_IOS_CLIENT_ID") as? String,
           !fromPlist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fromPlist
        }
        return ""
    }

    static var googleIOSClientID: String {
        get {
            let v = UserDefaults.standard.string(forKey: googleIOSClientIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !v.isEmpty { return v }
            return defaultGoogleIOSClientID
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: googleIOSClientIDKey) }
    }

    static var googleServiceInfoURL: URL? {
        Bundle.main.url(forResource: firebaseInfoPlistName, withExtension: "plist")
    }

    static var firebaseProjectID: String {
        firebaseString(forKey: "PROJECT_ID")
    }

    static var firebaseConfiguredBundleID: String {
        firebaseString(forKey: "BUNDLE_ID")
    }

    static func firebaseSetupIssue(bundleID: String? = Bundle.main.bundleIdentifier) -> String? {
        guard googleServiceInfoURL != nil else {
            return "缺少 GoogleService-Info.plist，请先把 Firebase iOS 配置文件加入 App target。"
        }
        if firebaseProjectID.isEmpty {
            return "GoogleService-Info.plist 缺少 PROJECT_ID，无法确认 Firebase project。"
        }
        if firebaseConfiguredBundleID.isEmpty {
            return "GoogleService-Info.plist 缺少 BUNDLE_ID，无法校验 Firebase iOS app 配置。"
        }
        if let bundleID,
           !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           firebaseConfiguredBundleID != bundleID {
            return "Firebase BUNDLE_ID (\(firebaseConfiguredBundleID)) 与当前 App Bundle ID (\(bundleID)) 不一致。"
        }
        return nil
    }

    private static func firebaseString(forKey key: String) -> String {
        guard let url = googleServiceInfoURL,
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let value = plist[key] as? String else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
