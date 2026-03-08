import Foundation
import Security

enum StableGuestIDStore {
    private static let service = "com.streetstamps.identity"
    private static let account = "stable_guest_id_v1"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let raw = String(data: data, encoding: .utf8),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    static func save(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attrs: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return }

        var create = query
        create[kSecValueData as String] = data
        _ = SecItemAdd(create as CFDictionary, nil)
    }
}
