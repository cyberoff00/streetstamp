import Foundation

enum BackendConfig {
    private static let baseURLKey = "streetstamps.backend.base_url"
    private static let googleIOSClientIDKey = "streetstamps.google.ios_client_id"

    static var defaultBaseURL: String {
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !fromPlist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fromPlist
        }
        return ""
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

    static var googleIOSClientID: String {
        get { UserDefaults.standard.string(forKey: googleIOSClientIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: googleIOSClientIDKey) }
    }
}
