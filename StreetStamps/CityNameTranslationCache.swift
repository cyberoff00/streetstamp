import Foundation
import CoreLocation

// MARK: - City Name Translation Cache
//
// The ONLY place where locale-dependent city names are resolved.
// Model layer (CachedCity) stores only en_US identity data.
//
// Translation rules:
//   - Only Chinese cities (iso2 == CN) are translated
//   - Only for zh-Hans / zh-Hant users
//   - Geocode always uses zh-Hans; zh-Hant users get CFStringTransform conversion
//   - All other locales / countries → English name, zero geocode
//
// Sync read: cachedName() — returns cached value or nil, zero cost
// Async fill: translate() — geocodes and stores

final class CityNameTranslationCache: @unchecked Sendable {
    static let shared = CityNameTranslationCache()

    private let lock = NSLock()
    private var cache: [String: String] = [:]  // "cityKey|zh" → simplified Chinese name
    private let persistKey = "cityNameTranslation.cache.v3"
    private let sharedDefaults = UserDefaults(suiteName: "group.com.streetstamps.shared") ?? .standard

    private let geocoder = CLGeocoder()
    private var lastRequestAt: Date = .distantPast
    private var throttledUntil: Date = .distantPast
    private let minIntervalSeconds: TimeInterval = 1.5

    private init() {
        if let data = sharedDefaults.data(forKey: persistKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
        }
        // One-time cleanup of old cache keys.
        // v2 contained polluted entries (e.g. Huzhou|CN → "浙江") from a past
        // bug where translate() was called with the wrong CardLevel. Dropping
        // v2 forces re-translation with the now-correct inferIdentityLevel path.
        for oldKey in [
            "cityNameTranslation.cache.v1",
            "cityNameTranslation.cache.v2",
            "reverseGeocode.displayCacheByLocaleKey.v7",
            "reverseGeocode.displayCacheByLocaleKey.v2"
        ] {
            if sharedDefaults.data(forKey: oldKey) != nil {
                sharedDefaults.removeObject(forKey: oldKey)
            }
        }
    }

    /// Clear all cached translations.
    func clearAll() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
        sharedDefaults.removeObject(forKey: persistKey)
    }

    /// Clear cached translations only for specific city keys.
    /// Used by identity repair to invalidate re-keyed cities without wiping
    /// translations for cities whose keys didn't change.
    func clearKeys(_ cityKeys: Set<String>) {
        guard !cityKeys.isEmpty else { return }
        lock.lock()
        for key in cityKeys {
            cache.removeValue(forKey: "\(key)|zh")
        }
        lock.unlock()
        schedulePersist()
    }

    // MARK: - Sync read

    /// Returns translated Chinese name for a CN city, or nil.
    /// For zh-Hant users, automatically converts simplified → traditional.
    func cachedName(cityKey: String, localeID: String) -> String? {
        guard isChinese(localeID), isCNCity(cityKey) else { return nil }
        lock.lock()
        let simplified = cache["\(cityKey)|zh"]
        lock.unlock()
        guard let simplified else { return nil }
        if localeID.hasPrefix("zh-Hant") {
            return toTraditional(simplified)
        }
        return simplified
    }

    // MARK: - Convenience for detail views

    func translateIfNeeded(_ city: CachedCity, locale: Locale) async -> String? {
        let localeID = locale.identifier
        guard isChinese(localeID), isCNCity(city.cityKey) else { return nil }
        if let cached = cachedName(cityKey: city.cityKey, localeID: localeID) { return cached }
        return await translate(cityKey: city.cityKey, anchor: city.anchor?.cl, level: city.identityLevel, locale: locale)
    }

    // MARK: - Async translate

    /// Translate a CN city name to Chinese via reverse geocode (coordinate → placemark).
    /// Always geocodes with zh-Hans; zh-Hant users get CFStringTransform conversion.
    func translate(
        cityKey: String,
        anchor: CLLocationCoordinate2D?,
        level: CityPlacemarkResolver.CardLevel,
        locale: Locale
    ) async -> String? {
        let localeID = locale.identifier
        guard isChinese(localeID), isCNCity(cityKey) else { return nil }
        guard let anchor, CLLocationCoordinate2DIsValid(anchor) else { return nil }

        let cacheKey = "\(cityKey)|zh"

        // Cache hit
        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return localeID.hasPrefix("zh-Hant") ? toTraditional(cached) : cached
        }
        lock.unlock()

        // Rate limit — read/write throttle state under lock
        let waitTime: TimeInterval = {
            lock.lock()
            defer { lock.unlock() }
            let now = Date()
            var delay: TimeInterval = 0
            if now < throttledUntil {
                delay = throttledUntil.timeIntervalSince(now)
            }
            let sinceLast = now.timeIntervalSince(lastRequestAt)
            if sinceLast + delay < minIntervalSeconds {
                delay = max(delay, minIntervalSeconds - sinceLast)
            }
            lastRequestAt = now.addingTimeInterval(delay)
            return delay
        }()
        if waitTime > 0 {
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }

        let location = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        let zhHansLocale = Locale(identifier: "zh-Hans")

        #if DEBUG
        print("🌐 [Translate] START cityKey=\(cityKey) level=\(level.rawValue) coord=\(anchor.latitude),\(anchor.longitude)")
        #endif

        let result: String? = await withCheckedContinuation { cont in
            geocoder.reverseGeocodeLocation(location, preferredLocale: zhHansLocale) { [weak self] placemarks, error in
                if let nsErr = error as NSError? {
                    if nsErr.domain == "GEOErrorDomain" && nsErr.code == -3 {
                        self?.lock.lock()
                        self?.throttledUntil = Date().addingTimeInterval(60)
                        self?.lock.unlock()
                    }
                    #if DEBUG
                    print("🌐 [Translate] ERROR cityKey=\(cityKey) error=\(nsErr.localizedDescription)")
                    #endif
                }
                guard let pm = placemarks?.first else {
                    #if DEBUG
                    print("🌐 [Translate] NO PLACEMARK cityKey=\(cityKey)")
                    #endif
                    cont.resume(returning: nil)
                    return
                }

                #if DEBUG
                print("🌐 [Translate] PLACEMARK cityKey=\(cityKey) locality=\(pm.locality ?? "nil") subAdmin=\(pm.subAdministrativeArea ?? "nil") admin=\(pm.administrativeArea ?? "nil")")
                #endif

                let preferred: String? = {
                    switch level {
                    case .admin:    return pm.administrativeArea
                    case .subAdmin: return pm.subAdministrativeArea ?? pm.locality
                    case .locality: return pm.locality ?? pm.subAdministrativeArea
                    case .country:  return pm.country
                    case .island:   return pm.locality
                    }
                }()
                let translated = preferred
                    ?? pm.locality
                    ?? pm.subAdministrativeArea
                    ?? pm.administrativeArea
                    ?? pm.country

                var trimmed = translated?.trimmingCharacters(in: .whitespacesAndNewlines)

                // Strip Chinese admin suffixes (省/市/区 etc.)
                if let t = trimmed {
                    trimmed = CityPlacemarkResolver.stripAdminSuffixPublic(t)
                }

                // Apple sometimes returns Traditional Chinese even for zh-Hans — force simplify
                if let t = trimmed {
                    let mutable = NSMutableString(string: t)
                    CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
                    trimmed = mutable as String
                }

                #if DEBUG
                print("🌐 [Translate] RESULT cityKey=\(cityKey) level=\(level.rawValue) raw=\(translated ?? "nil") final=\(trimmed ?? "nil")")
                #endif

                guard let trimmed, !trimmed.isEmpty else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: trimmed)
            }
        }

        if let result {
            lock.lock()
            cache[cacheKey] = result
            lock.unlock()
            schedulePersist()
        }

        // Return in the user's script
        if let result, localeID.hasPrefix("zh-Hant") {
            return toTraditional(result)
        }
        return result
    }

    // MARK: - Helpers

    /// Whether a city key + locale combination is eligible for translation.
    /// Used by callers to distinguish "not translatable" from "translate failed".
    static func isTranslatable(cityKey: String, localeID: String) -> Bool {
        localeID.hasPrefix("zh") && cityKey.hasSuffix("|CN")
    }

    private func isChinese(_ localeID: String) -> Bool {
        localeID.hasPrefix("zh")
    }

    private func isCNCity(_ cityKey: String) -> Bool {
        cityKey.hasSuffix("|CN")
    }

    private func toTraditional(_ simplified: String) -> String {
        let mutable = NSMutableString(string: simplified)
        CFStringTransform(mutable, nil, "Simplified-Traditional" as CFString, false)
        return mutable as String
    }

    // MARK: - Persistence

    private func schedulePersist() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.persistNow()
        }
    }

    private func persistNow() {
        lock.lock()
        let snapshot = cache
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        sharedDefaults.set(data, forKey: persistKey)
    }
}
