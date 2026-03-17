import Foundation
import CoreLocation

/// Centralized reverse-geocode coordinator.
///
/// P0 fixes:
/// - Global rate limit: at least ~1–2s between reverseGeocode requests (default 1.5s)
/// - Cell-level cache + in-flight de-dupe: same rounded cell only requests once
/// - City-level de-dupe for display localization: same cityKey only localizes once
/// - When system throttles (GEOErrorDomain Code=-3), skip requests until reset
///
/// Notes:
/// - We intentionally "skip" (do not wait/sleep) when rate-limited, to avoid build-ups.
/// - Callers should treat `nil` as "no fresh result yet" and keep last known city.
actor ReverseGeocodeService {

    static let shared = ReverseGeocodeService()

    // MARK: - Tunables
    private let minIntervalSeconds: TimeInterval = 1.5
    private let cellRoundingPlaces: Int = 2     // ~1.1km grid; enough for "same city" de-dupe

    // MARK: - State
    private var lastRequestAt: Date = .distantPast
    private var throttledUntil: Date = .distantPast

    private var canonicalCacheByCell: [String: CanonicalResult] = [:]
    private var canonicalInFlight: [String: [CheckedContinuation<CanonicalResult?, Never>]] = [:]
    private var localizedHierarchyCacheByLocaleCell: [String: CanonicalResult] = [:]
    private var localizedHierarchyInFlightByLocaleCell: [String: [CheckedContinuation<CanonicalResult?, Never>]] = [:]

    /// Display localization cache is locale-dependent.
    ///
    /// Why: A user can change device language (or run in a different preferred language)
    /// and we must not keep returning a previously cached title from another locale.
    ///
    /// Key format: "<cityKey>|<localeIdentifier>".
    private var displayCacheByLocaleKey: [String: String] = [:]
    private var displayInFlightByLocaleKey: [String: [CheckedContinuation<String?, Never>]] = [:]

    private let canonicalGeocoder = CLGeocoder()
    private let displayGeocoder = CLGeocoder()
    private let fixedLocale = Locale(identifier: "en_US")

    // MARK: - Persistent cache (display titles)
    // Persist display localization cache across app launches to avoid re-geocoding every cold start.
    private let sharedDefaults = UserDefaults(suiteName: "group.com.streetstamps.shared") ?? .standard
    private let persistKey = "reverseGeocode.displayCacheByLocaleKey.v2"
    private var persistTask: Task<Void, Never>? = nil

    init() {
        // Load persisted cache (best-effort).
        if let data = sharedDefaults.data(forKey: persistKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.displayCacheByLocaleKey = dict
        }
    }

    private func schedulePersist() {
        // Debounce to avoid frequent disk writes.
        persistTask?.cancel()
        persistTask = Task { [persistKey] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            persistNow(persistKey: persistKey)
        }
    }

    private func persistNow(persistKey: String) {
        guard let data = try? JSONEncoder().encode(displayCacheByLocaleKey) else { return }
        sharedDefaults.set(data, forKey: persistKey)
    }


    // MARK: - Models
    struct CanonicalResult: Sendable {
        let cityName: String
        let iso2: String?
        let cityKey: String
        let level: CityPlacemarkResolver.CardLevel
        let parentRegionKey: String?
        let availableLevels: [CityPlacemarkResolver.CardLevel: String]
        let localeIdentifier: String

        init(
            cityName: String,
            iso2: String?,
            cityKey: String,
            level: CityPlacemarkResolver.CardLevel,
            parentRegionKey: String?,
            availableLevels: [CityPlacemarkResolver.CardLevel: String],
            localeIdentifier: String = LanguagePreference.shared.effectiveLocaleIdentifier
        ) {
            self.cityName = cityName
            self.iso2 = iso2
            self.cityKey = cityKey
            self.level = level
            self.parentRegionKey = parentRegionKey
            self.availableLevels = availableLevels
            self.localeIdentifier = localeIdentifier
        }
    }
    // MARK: - Public API

    /// Canonical geocode (stable key). Uses fixedLocale.
    /// Returns cached result if available; otherwise returns nil if rate-limited/throttled.
    func canonical(for location: CLLocation) async -> CanonicalResult? {
        let cell = cellKey(for: location)

        // Fast path: cache hit
        if let cached = canonicalCacheByCell[cell] {
            return cached
        }

        // In-flight de-dupe
        if canonicalInFlight[cell] != nil {
            return await withCheckedContinuation { cont in
                canonicalInFlight[cell]?.append(cont)
            }
        }

        // Global throttle / cooldown
        let now = Date()
        if now < throttledUntil {
            return nil
        }
        if now.timeIntervalSince(lastRequestAt) < minIntervalSeconds {
            return nil
        }
        lastRequestAt = now

        canonicalInFlight[cell] = []

        let result: CanonicalResult? = await withCheckedContinuation { cont in
            canonicalGeocoder.reverseGeocodeLocation(location, preferredLocale: fixedLocale) { placemarks, error in
                if let nsErr = error as NSError? {
                    // Completion may be invoked off-actor; hop back before mutating actor state.
                    Task { await self.handlePossibleThrottle(nsErr) }
                }
                guard let pm = placemarks?.first else {
                    cont.resume(returning: nil)
                    return
                }
                let canon = CityPlacemarkResolver.resolveIdentityCanonical(from: pm)
                cont.resume(returning: CanonicalResult(
                    cityName: canon.city,
                    iso2: canon.iso2,
                    cityKey: canon.cityKey,
                    level: canon.level,
                    parentRegionKey: canon.parentRegionKey,
                    availableLevels: canon.availableLevelNames,
                    localeIdentifier: self.fixedLocale.identifier
                ))
            }
        }

        if let result {
            canonicalCacheByCell[cell] = result
        }

        // Resume all waiters
        let waiters = canonicalInFlight[cell] ?? []
        canonicalInFlight[cell] = nil
        waiters.forEach { $0.resume(returning: result) }
        return result
    }

    /// Localized hierarchy snapshot for UI labels. Uses `Locale.current`.
    func localizedHierarchy(for location: CLLocation) async -> CanonicalResult? {
        let displayLocale = LanguagePreference.shared.displayLocale
        let localeCell = "\(cellKey(for: location))|\(displayLocale.identifier)"

        if let cached = localizedHierarchyCacheByLocaleCell[localeCell] {
            return cached
        }

        if localizedHierarchyInFlightByLocaleCell[localeCell] != nil {
            return await withCheckedContinuation { cont in
                localizedHierarchyInFlightByLocaleCell[localeCell]?.append(cont)
            }
        }

        let now = Date()
        if now < throttledUntil {
            return nil
        }
        if now.timeIntervalSince(lastRequestAt) < minIntervalSeconds {
            return nil
        }
        lastRequestAt = now

        localizedHierarchyInFlightByLocaleCell[localeCell] = []

        let result: CanonicalResult? = await withCheckedContinuation { cont in
            canonicalGeocoder.reverseGeocodeLocation(location, preferredLocale: displayLocale) { placemarks, error in
                if let nsErr = error as NSError? {
                    Task { await self.handlePossibleThrottle(nsErr) }
                }
                guard let pm = placemarks?.first else {
                    cont.resume(returning: nil)
                    return
                }
                let canon = CityPlacemarkResolver.resolveCanonical(from: pm)
                cont.resume(returning: CanonicalResult(
                    cityName: canon.city,
                    iso2: canon.iso2,
                    cityKey: canon.cityKey,
                    level: canon.level,
                    parentRegionKey: canon.parentRegionKey,
                    availableLevels: canon.availableLevelNames,
                    localeIdentifier: displayLocale.identifier
                ))
            }
        }

        if let result {
            localizedHierarchyCacheByLocaleCell[localeCell] = result
            CityLocalizationDebugLogger.log(
                "localizedHierarchy",
                CityLocalizationDebugTrace.localizedHierarchy(
                    locale: displayLocale,
                    cellKey: localeCell,
                    result: result
                )
            )
        }

        let waiters = localizedHierarchyInFlightByLocaleCell[localeCell] ?? []
        localizedHierarchyInFlightByLocaleCell[localeCell] = nil
        waiters.forEach { $0.resume(returning: result) }
        return result
    }

    /// Localized display title.
    /// - Only does reverse geocode once per cityKey.
    /// - Uses Locale.current.
    /// - Returns cached title immediately; otherwise nil if rate-limited/throttled.
    func displayTitle(for location: CLLocation, cityKey: String, parentRegionKey: String? = nil) async -> String? {
        let displayLocale = LanguagePreference.shared.displayLocale
        let localeKey = displayCacheKey(cityKey: cityKey, locale: displayLocale, parentRegionKey: parentRegionKey)
        if let cached = displayCacheByLocaleKey[localeKey] {
            return cached
        }

        if displayInFlightByLocaleKey[localeKey] != nil {
            return await withCheckedContinuation { cont in
                displayInFlightByLocaleKey[localeKey]?.append(cont)
            }
        }

        let now = Date()
        if now < throttledUntil {
            return nil
        }
        if now.timeIntervalSince(lastRequestAt) < minIntervalSeconds {
            return nil
        }
        lastRequestAt = now

        displayInFlightByLocaleKey[localeKey] = []

        let title: String? = await withCheckedContinuation { cont in
            displayGeocoder.reverseGeocodeLocation(location, preferredLocale: displayLocale) { placemarks, error in
                if let nsErr = error as NSError? {
                    // Completion may be invoked off-actor; hop back before mutating actor state.
                    Task { await self.handlePossibleThrottle(nsErr) }
                }
                guard let pm = placemarks?.first else {
                    cont.resume(returning: nil)
                    return
                }
                let disp = CityPlacemarkResolver.resolveDisplay(from: pm)
                let title = CityPlacemarkResolver.displayTitle(
                    cityKey: cityKey,
                    iso2: disp.iso2,
                    fallbackTitle: disp.title,
                    parentRegionKey: parentRegionKey,
                    preferredLevel: disp.level,
                    locale: displayLocale
                )
                cont.resume(returning: title)
            }
        }

        if let title {
            displayCacheByLocaleKey[localeKey] = title
            CityLocalizationDebugLogger.log(
                "displayCacheWrite",
                "locale=\(displayLocale.identifier) cacheKey=\(localeKey) title=\(title)"
            )
            schedulePersist()
        }

        let waiters = displayInFlightByLocaleKey[localeKey] ?? []
        displayInFlightByLocaleKey[localeKey] = nil
        waiters.forEach { $0.resume(returning: title) }
        return title
    }

    /// Optional helper: get cached display title without making a request.
    func cachedDisplayTitle(cityKey: String, parentRegionKey: String? = nil, locale: Locale = .current) -> String? {
        displayCacheByLocaleKey[displayCacheKey(cityKey: cityKey, locale: locale, parentRegionKey: parentRegionKey)]
    }

    // MARK: - Internals

    private func cellKey(for location: CLLocation) -> String {
        // NOTE: Avoid depending on a project-wide `Double.rounded(to:)` helper.
        // Some builds annotate that helper with `@MainActor`, which makes it illegal to
        // call from this actor synchronously. Keep this rounding local and actor-safe.
        let lat = roundPlaces(location.coordinate.latitude, places: cellRoundingPlaces)
        let lon = roundPlaces(location.coordinate.longitude, places: cellRoundingPlaces)
        return "\(lat),\(lon)"
    }

    private func displayCacheKey(cityKey: String, locale: Locale, parentRegionKey: String?) -> String {
        let id = locale.identifier
        let scope = CityLevelPreferenceStore.shared.displayCacheScope(for: parentRegionKey)
        return "\(cityKey)|\(id)|\(scope)"
    }

    private func roundPlaces(_ value: Double, places: Int) -> Double {
        guard places >= 0 else { return value }
        let p = pow(10.0, Double(places))
        return (value * p).rounded() / p
    }

    private func handlePossibleThrottle(_ err: NSError) {
        // iOS reverse-geocode throttling shows as GEOErrorDomain Code=-3
        guard err.domain == "GEOErrorDomain", err.code == -3 else { return }

        let reset = parseThrottleResetSeconds(err) ?? 10
        let until = Date().addingTimeInterval(max(1, reset))
        if until > throttledUntil {
            throttledUntil = until
        }
    }

    private func parseThrottleResetSeconds(_ err: NSError) -> TimeInterval? {
        if let t = err.userInfo["timeUntilReset"] as? NSNumber {
            return t.doubleValue
        }
        if let details = err.userInfo["details"] as? [[String: Any]] {
            if let t = details.first?["timeUntilReset"] as? NSNumber { return t.doubleValue }
            if let t = details.first?["timeUntilReset"] as? TimeInterval { return t }
        }
        return nil
    }
}
