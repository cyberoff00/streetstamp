import Foundation

/// Persists manual city-card hierarchy preferences per user + parent region.
/// Example: user chooses `admin` for a state/province; future trips in that
/// parent region reuse that preferred level.
final class CityLevelPreferenceStore {
    static let shared = CityLevelPreferenceStore()

    private let defaults = UserDefaults(suiteName: "group.com.streetstamps.shared") ?? .standard
    private let storageKey = "city.levelPreferenceByRegion.v1"
    private var currentUserID: String = "local"

    private init() {}

    func setCurrentUserID(_ userID: String) {
        currentUserID = userID
    }

    func preferredLevel(for parentRegionKey: String?) -> CityPlacemarkResolver.CardLevel? {
        guard let scopedRegionKey = scopedRegionKey(for: parentRegionKey) else { return nil }
        guard let raw = readAll()[scopedRegionKey] else { return nil }
        guard let level = CityPlacemarkResolver.CardLevel(rawValue: raw) else { return nil }
        return level.isUserSelectable ? level : nil
    }

    func setPreferredLevel(_ level: CityPlacemarkResolver.CardLevel, for parentRegionKey: String?) {
        guard level.isUserSelectable else { return }
        guard let scopedRegionKey = scopedRegionKey(for: parentRegionKey) else { return }
        var dict = readAll()
        dict[scopedRegionKey] = level.rawValue
        defaults.set(dict, forKey: storageKey)
    }

    func clearAll() {
        defaults.removeObject(forKey: storageKey)
    }

    func displayCacheScope(for parentRegionKey: String?) -> String {
        preferredLevel(for: parentRegionKey)?.rawValue ?? "default"
    }

    private func readAll() -> [String: String] {
        defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    private func scopedRegionKey(for parentRegionKey: String?) -> String? {
        let key = (parentRegionKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return "\(currentUserID)|\(key)"
    }
}
