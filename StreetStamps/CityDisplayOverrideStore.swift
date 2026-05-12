import Foundation

final class CityDisplayOverrideStore: @unchecked Sendable {
    static let shared = CityDisplayOverrideStore()

    private let persistKey = "cityDisplayOverride.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var overrides: [String: String]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: persistKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.overrides = dict
        } else {
            self.overrides = [:]
        }
    }

    func override(for cityKey: String) -> String? {
        let key = cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        lock.lock()
        let value = overrides[key]
        lock.unlock()
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func setOverride(_ name: String?, for cityKey: String) {
        let key = cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lock.lock()
        if trimmed.isEmpty {
            overrides.removeValue(forKey: key)
        } else {
            overrides[key] = trimmed
        }
        let snapshot = overrides
        lock.unlock()
        persist(snapshot)
    }

    func clear(for cityKey: String) {
        setOverride(nil, for: cityKey)
    }

    private func persist(_ snapshot: [String: String]) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: persistKey)
    }
}
