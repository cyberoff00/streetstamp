import Foundation
import CoreLocation
import Network

/// Centralized reverse-geocode coordinator.
///
/// - Global rate limit: at least ~1–2s between reverseGeocode requests (default 1.5s)
/// - Cell-level cache + in-flight de-dupe: same rounded cell only requests once
/// - When system throttles (GEOErrorDomain Code=-3), skip requests until reset
/// - Network-aware: detects connectivity loss and waits for recovery
///
/// Notes:
/// - We intentionally "skip" (do not wait/sleep) when rate-limited, to avoid build-ups.
/// - Callers should treat `nil` as "no fresh result yet" and keep last known city.
actor ReverseGeocodeService {

    static let shared = ReverseGeocodeService()

    // MARK: - Network monitoring
    private let networkMonitor = NWPathMonitor()
    private nonisolated(unsafe) var _networkSatisfied: Bool = true

    /// Whether the device currently has network connectivity.
    nonisolated var isNetworkAvailable: Bool { _networkSatisfied }

    /// Posted on any network path change (e.g. VPN toggle, Wi-Fi ↔ cellular).
    /// Observers can retry failed geocoding when the routing changes.
    static let networkPathDidChange = Notification.Name("ReverseGeocodeService.networkPathDidChange")

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let wasSatisfied = self?._networkSatisfied ?? true
            let nowSatisfied = path.status == .satisfied
            self?._networkSatisfied = nowSatisfied
            // Post on ANY path change (covers VPN toggle, interface switch, reconnect)
            if wasSatisfied != nowSatisfied || nowSatisfied {
                NotificationCenter.default.post(name: ReverseGeocodeService.networkPathDidChange, object: nil)
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "ReverseGeocodeService.network", qos: .utility))
    }

    /// Wait up to `timeout` seconds for network to become available.
    /// Returns true if network is available, false if timed out.
    nonisolated func waitForNetwork(timeout: TimeInterval = 60) async -> Bool {
        if isNetworkAvailable { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // check every 1s
            if isNetworkAvailable { return true }
        }
        return false
    }

    private init() {
        startNetworkMonitor()
    }

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

    private let canonicalGeocoder = CLGeocoder()
    private let fixedLocale = Locale(identifier: "en_US")

    /// Separate geocoder for fine place labels so it never cancels an in-flight
    /// city-level lookup (CLGeocoder serializes per instance). Cache keyed by a
    /// ~110m cell so adjacent neighborhoods resolve distinctly.
    private let labelGeocoder = CLGeocoder()
    private var placeLabelCacheByLocaleCell: [String: String] = [:]
    private var placePartsCacheByLocaleCell: [String: PlaceParts] = [:]

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

        // Only cache results that actually resolved to a real city. A degenerate
        // result (missing admin/locality on an early imprecise fix → "Unknown|XX"
        // or localized "未知|XX") must NOT poison the cell cache, or every later
        // request for this ~1.1km cell would keep returning the placeholder even
        // once a better fix is available.
        if let result, !Self.isDegenerateCityKey(result.cityKey) {
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

    // MARK: - Retry helpers

    func canonicalWithRetry(for location: CLLocation, maxAttempts: Int = 2) async -> CanonicalResult? {
        for attempt in 0..<maxAttempts {
            if let result = await canonical(for: location) { return result }
            guard attempt + 1 < maxAttempts else { break }
            try? await Task.sleep(nanoseconds: UInt64(minIntervalSeconds * 1_100_000_000))
        }
        return nil
    }

    func localizedHierarchyWithRetry(for location: CLLocation, maxAttempts: Int = 2) async -> CanonicalResult? {
        for attempt in 0..<maxAttempts {
            if let result = await localizedHierarchy(for: location) { return result }
            guard attempt + 1 < maxAttempts else { break }
            try? await Task.sleep(nanoseconds: UInt64(minIntervalSeconds * 1_100_000_000))
        }
        return nil
    }

    /// Fine-grained place label for the 「你的小世界」 retrospective: a recognizable
    /// POI / street / neighborhood, NOT the city (city-level names collide across
    /// every place in the same town and read as fake). Returns nil when
    /// rate-limited or unresolved — callers keep their fallback and may retry.
    func placeLabel(for location: CLLocation) async -> String? {
        let displayLocale = LanguagePreference.shared.displayLocale
        let cell = "\(fineCellKey(for: location))|\(displayLocale.identifier)"
        if let cached = placeLabelCacheByLocaleCell[cell] { return cached }

        let now = Date()
        if now < throttledUntil { return nil }
        if now.timeIntervalSince(lastRequestAt) < minIntervalSeconds { return nil }
        lastRequestAt = now

        let geocoder = labelGeocoder
        let label: String? = await withCheckedContinuation { cont in
            geocoder.reverseGeocodeLocation(location, preferredLocale: displayLocale) { placemarks, error in
                if let nsErr = error as NSError? {
                    Task { await self.handlePossibleThrottle(nsErr) }
                }
                guard let pm = placemarks?.first else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: Self.fineLabel(from: pm))
            }
        }
        if let label, !label.isEmpty { placeLabelCacheByLocaleCell[cell] = label }
        return label
    }

    /// Localized (city, district) pair for the retrospective cards. Both come
    /// from a single geocode in the user's display locale, so the city shows in
    /// Chinese (not the stored English fallback) and the district is the real 区.
    struct PlaceParts: Sendable, Equatable { let city: String?; let district: String? }

    func localizedPlace(for location: CLLocation) async -> PlaceParts? {
        let displayLocale = LanguagePreference.shared.displayLocale
        let cell = "P|\(fineCellKey(for: location))|\(displayLocale.identifier)"
        if let cached = placePartsCacheByLocaleCell[cell] { return cached }

        let now = Date()
        if now < throttledUntil { return nil }
        if now.timeIntervalSince(lastRequestAt) < minIntervalSeconds { return nil }
        lastRequestAt = now

        let geocoder = labelGeocoder
        let parts: PlaceParts? = await withCheckedContinuation { cont in
            geocoder.reverseGeocodeLocation(location, preferredLocale: displayLocale) { placemarks, error in
                if let nsErr = error as NSError? { Task { await self.handlePossibleThrottle(nsErr) } }
                guard let pm = placemarks?.first else { cont.resume(returning: nil); return }
                func clean(_ s: String?) -> String? {
                    guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
                    return s
                }
                let city = clean(pm.locality) ?? clean(pm.subAdministrativeArea)
                let district = clean(pm.subLocality) ?? clean(pm.subAdministrativeArea)
                cont.resume(returning: PlaceParts(city: city, district: district))
            }
        }
        if let parts { placePartsCacheByLocaleCell[cell] = parts }
        return parts
    }

    /// District-level label (区/县), NOT street-level — street names are noisy and
    /// over-specific for a retrospective. Prefer the administrative district
    /// (徐汇区 / a county), then a sub-locality, then the city as a last resort.
    nonisolated static func fineLabel(from pm: CLPlacemark) -> String? {
        func clean(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        if let district = clean(pm.subAdministrativeArea) { return district }
        if let sub = clean(pm.subLocality) { return sub }
        if let loc = clean(pm.locality) { return loc }
        return clean(pm.administrativeArea)
    }

    /// ~110m cell so neighboring places cache separately (finer than `cellKey`).
    private func fineCellKey(for location: CLLocation) -> String {
        let lat = roundPlaces(location.coordinate.latitude, places: 3)
        let lon = roundPlaces(location.coordinate.longitude, places: 3)
        return "\(lat),\(lon)"
    }

    /// Seconds remaining until the throttle window expires, or 0 if not throttled.
    func throttleRemainingSeconds() -> TimeInterval {
        max(0, throttledUntil.timeIntervalSinceNow)
    }

    // MARK: - Internals

    /// A cityKey whose city component is missing or a placeholder ("Unknown" /
    /// localized "未知" / empty). Such results are never worth caching.
    nonisolated static func isDegenerateCityKey(_ rawKey: String) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return true }
        let cityPart = (key.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cityPart.isEmpty { return true }
        if cityPart.caseInsensitiveCompare("Unknown") == .orderedSame { return true }
        if cityPart == L10n.t("unknown") { return true }
        return false
    }

    private func cellKey(for location: CLLocation) -> String {
        // NOTE: Avoid depending on a project-wide `Double.rounded(to:)` helper.
        // Some builds annotate that helper with `@MainActor`, which makes it illegal to
        // call from this actor synchronously. Keep this rounding local and actor-safe.
        let lat = roundPlaces(location.coordinate.latitude, places: cellRoundingPlaces)
        let lon = roundPlaces(location.coordinate.longitude, places: cellRoundingPlaces)
        return "\(lat),\(lon)"
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
