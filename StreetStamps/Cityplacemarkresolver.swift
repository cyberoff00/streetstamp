import Foundation
import CoreLocation

enum CityLocalizationDebugTrace {
    static func displayDecision(
        cityKey: String,
        locale: Locale,
        source: String,
        title: String,
        fallbackTitle: String,
        chosenLevel: CityPlacemarkResolver.CardLevel?,
        parentRegionKey: String?,
        availableLevelNames: [CityPlacemarkResolver.CardLevel: String]?
    ) -> String {
        let labels = (availableLevelNames ?? [:])
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ",")
        return "cityKey=\(cityKey) locale=\(locale.identifier) source=\(source) chosenLevel=\(chosenLevel?.rawValue ?? "nil") parentRegionKey=\(parentRegionKey ?? "nil") title=\(title) fallback=\(fallbackTitle) levels=[\(labels)]"
    }

    static func localizedHierarchy(
        locale: Locale,
        cellKey: String,
        result: ReverseGeocodeService.CanonicalResult?
    ) -> String {
        let levels = (result?.availableLevels ?? [:])
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ",")
        return "locale=\(locale.identifier) cell=\(cellKey) cityKey=\(result?.cityKey ?? "nil") cityName=\(result?.cityName ?? "nil") parentRegionKey=\(result?.parentRegionKey ?? "nil") levels=[\(levels)]"
    }

    static func reserveProfileWrite(
        cityKey: String,
        locale: Locale,
        level: CityPlacemarkResolver.CardLevel?,
        parentRegionKey: String?,
        availableLevels: [CityPlacemarkResolver.CardLevel: String]?
    ) -> String {
        let levels = (availableLevels ?? [:])
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ",")
        return "cityKey=\(cityKey) locale=\(locale.identifier) level=\(level?.rawValue ?? "nil") parentRegionKey=\(parentRegionKey ?? "nil") levels=[\(levels)]"
    }
}

enum CityLocalizationDebugLogger {
    static func log(_ domain: String, _ message: String) {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let enabled = args.contains("-CityLocalizationDebug")
            || UserDefaults.standard.bool(forKey: "city.localization.debug.enabled")
        guard enabled else { return }
        print("🌐 [CityLocale][\(domain)] \(message)")
#endif
    }
}

enum CityPlacemarkResolver {

    enum CardLevel: String, Codable, Sendable {
        case island
        case locality
        case subAdmin
        case admin
        case country

        var isUserSelectable: Bool {
            switch self {
            case .locality, .subAdmin, .admin:
                return true
            case .island, .country:
                return false
            }
        }
    }

    struct Canonical: Equatable {
        let city: String
        let iso2: String?
        let level: CardLevel
        let admin: String?
        let subAdmin: String?
        let country: String?
        let parentRegionKey: String?
        let availableLevelNames: [CardLevel: String]
    }

    struct Display: Equatable {
        let title: String
        let subtitle: String?
        let iso2: String?
        let level: CardLevel
        let admin: String?
        let subAdmin: String?
        let country: String?
    }

    private struct LevelCandidates {
        let iso2: String?
        let island: String?
        let locality: String?
        let subAdmin: String?
        let admin: String?
        let country: String?
        let parentRegionKey: String?

        func name(for level: CardLevel) -> String? {
            switch level {
            case .island: return island
            case .locality: return locality
            case .subAdmin: return subAdmin
            case .admin: return admin
            case .country: return country
            }
        }

        var availableLevelNames: [CardLevel: String] {
            var out: [CardLevel: String] = [:]
            if let v = island { out[.island] = v }
            if let v = locality { out[.locality] = v }
            if let v = subAdmin { out[.subAdmin] = v }
            if let v = admin { out[.admin] = v }
            if let v = country { out[.country] = v }
            return out
        }
    }

    static func resolveCanonical(from pm: CLPlacemark, preferredISO2: String? = nil) -> Canonical {
        let candidates = makeLevelCandidates(from: pm, preferredISO2: preferredISO2)
        let level = decideLevel(candidates: candidates, preferred: nil)
        let name = canonicalName(level: level, candidates: candidates)

        return Canonical(
            city: name,
            iso2: candidates.iso2,
            level: level,
            admin: candidates.admin,
            subAdmin: candidates.subAdmin,
            country: candidates.country,
            parentRegionKey: candidates.parentRegionKey,
            availableLevelNames: candidates.availableLevelNames
        )
    }

    static func resolveIdentityCanonical(from pm: CLPlacemark, preferredISO2: String? = nil) -> Canonical {
        let candidates = makeLevelCandidates(from: pm, preferredISO2: preferredISO2)
        let level = decideLevel(candidates: candidates, preferred: nil)
        let name = canonicalName(level: level, candidates: candidates)

        return Canonical(
            city: name,
            iso2: candidates.iso2,
            level: level,
            admin: candidates.admin,
            subAdmin: candidates.subAdmin,
            country: candidates.country,
            parentRegionKey: candidates.parentRegionKey,
            availableLevelNames: candidates.availableLevelNames
        )
    }

    static func resolveDisplay(from pm: CLPlacemark, preferredISO2: String? = nil) -> Display {
        let candidates = makeLevelCandidates(from: pm, preferredISO2: preferredISO2)
        let level = decideLevel(candidates: candidates, preferred: nil)
        let useRegionInsteadOfCountry = isRegionStyledISO(candidates.iso2)

        var title: String = L10n.t("unknown")
        var subtitle: String? = nil

        switch level {
        case .country:
            if useRegionInsteadOfCountry {
                title = regionFallbackName(from: candidates) ?? (candidates.country ?? L10n.t("unknown"))
            } else {
                title = localizedSpecialCountryNameIfNeeded(iso2: candidates.iso2, fallbackCountry: candidates.country) ?? (candidates.country ?? L10n.t("unknown"))
            }

        case .admin:
            title = candidates.admin ?? candidates.subAdmin ?? candidates.locality ?? (candidates.country ?? L10n.t("unknown"))
            subtitle = useRegionInsteadOfCountry
                ? regionSubtitle(from: candidates, title: title)
                : candidates.country

        case .subAdmin:
            title = candidates.subAdmin ?? candidates.locality ?? candidates.admin ?? (candidates.country ?? L10n.t("unknown"))
            subtitle = useRegionInsteadOfCountry
                ? regionSubtitle(from: candidates, title: title)
                : candidates.country

        case .island:
            title = candidates.island ?? candidates.locality ?? candidates.subAdmin ?? candidates.admin ?? (candidates.country ?? L10n.t("unknown"))
            subtitle = useRegionInsteadOfCountry
                ? regionSubtitle(from: candidates, title: title)
                : candidates.country

        case .locality:
            if candidates.iso2 == "CN" {
                let localityCandidate: String? = {
                    guard let loc = candidates.locality else { return nil }
                    return isChineseDistrictLike(loc) ? nil : loc
                }()
                title = localityCandidate ?? candidates.subAdmin ?? candidates.admin ?? (candidates.country ?? L10n.t("unknown"))
            } else {
                title = candidates.locality ?? candidates.subAdmin ?? candidates.admin ?? (candidates.country ?? L10n.t("unknown"))
            }

            if candidates.iso2 == "US", let st = candidates.admin, let city = candidates.locality {
                title = "\(city), \(st)"
                subtitle = nil
            } else {
                subtitle = useRegionInsteadOfCountry
                    ? regionSubtitle(from: candidates, title: title)
                    : candidates.country
            }
        }

        return Display(
            title: normalizeUserFacingTitle(title, iso2: candidates.iso2, level: level, locale: LanguagePreference.shared.displayLocale),
            subtitle: subtitle,
            iso2: candidates.iso2,
            level: level,
            admin: candidates.admin,
            subAdmin: candidates.subAdmin,
            country: candidates.country
        )
    }

    static func displayTitle(
        cityKey: String,
        iso2: String?,
        fallbackTitle: String,
        availableLevelNames: [CardLevel: String]? = nil,
        parentRegionKey: String? = nil,
        preferredLevel: CardLevel? = nil,
        localizedDisplayNameByLocale: [String: String]? = nil,
        locale: Locale = LanguagePreference.shared.displayLocale
    ) -> String {
        let regionStyledKey = isRegionStyledDisplayKey(cityKey: cityKey, iso2: iso2)
        let chosenLevel = resolvedDisplayLevel(
            cityKey: cityKey,
            availableLevelNames: availableLevelNames,
            parentRegionKey: parentRegionKey,
            preferredLevel: preferredLevel
        )

        // Selected level must win over generic localized/cache titles.
        if let chosenLevel,
           let levelTitle = availableLevelNames?[chosenLevel]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !levelTitle.isEmpty,
           shouldUseStoredLevelTitle(levelTitle, locale: locale) {
            let resolved = normalizeUserFacingTitle(levelTitle, iso2: iso2, level: chosenLevel, locale: locale)
            CityLocalizationDebugLogger.log(
                "displayTitle",
                CityLocalizationDebugTrace.displayDecision(
                    cityKey: cityKey,
                    locale: locale,
                    source: "availableLevelNames[\(chosenLevel.rawValue)]",
                    title: resolved,
                    fallbackTitle: fallbackTitle,
                    chosenLevel: chosenLevel,
                    parentRegionKey: parentRegionKey,
                    availableLevelNames: availableLevelNames
                )
            )
            return resolved
        }

        // Fast path: use persisted localized name if available for this locale.
        if let localized = localizedDisplayNameByLocale?[locale.identifier]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !localized.isEmpty,
           (!regionStyledKey || matchesRegionAlias(localized, iso2: iso2 ?? "")),
           shouldUseStoredDisplayTitle(localized, locale: locale) {
            let resolved = normalizeUserFacingTitle(localized, iso2: iso2, level: nil, locale: locale)
            CityLocalizationDebugLogger.log(
                "displayTitle",
                CityLocalizationDebugTrace.displayDecision(
                    cityKey: cityKey,
                    locale: locale,
                    source: "localizedDisplayNameByLocale",
                    title: resolved,
                    fallbackTitle: fallbackTitle,
                    chosenLevel: nil,
                    parentRegionKey: parentRegionKey,
                    availableLevelNames: availableLevelNames
                )
            )
            return resolved
        }

        // Second chance: sync lookup from ReverseGeocodeService UserDefaults cache.
        if let cached = syncCachedDisplayTitle(cityKey: cityKey, parentRegionKey: parentRegionKey, locale: locale),
           (!regionStyledKey || matchesRegionAlias(cached, iso2: iso2 ?? "")),
           shouldUseStoredDisplayTitle(cached, locale: locale) {
            let resolved = normalizeUserFacingTitle(cached, iso2: iso2, level: nil, locale: locale)
            CityLocalizationDebugLogger.log(
                "displayTitle",
                CityLocalizationDebugTrace.displayDecision(
                    cityKey: cityKey,
                    locale: locale,
                    source: "displayCacheByLocaleKey.v2",
                    title: resolved,
                    fallbackTitle: fallbackTitle,
                    chosenLevel: nil,
                    parentRegionKey: parentRegionKey,
                    availableLevelNames: availableLevelNames
                )
            )
            return resolved
        }

        let decision: (source: String, rawTitle: String) = {
            let trimmedFallback = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedFallback.isEmpty {
                return ("fallbackTitle", trimmedFallback)
            }

            let cityNameFromKey = cityKey.components(separatedBy: "|").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !cityNameFromKey.isEmpty {
                return ("cityKey", cityNameFromKey)
            }

            return ("fallbackTitle.raw", fallbackTitle)
        }()

        let resolved = normalizeUserFacingTitle(decision.rawTitle, iso2: iso2, level: chosenLevel, locale: locale)
        CityLocalizationDebugLogger.log(
            "displayTitle",
            CityLocalizationDebugTrace.displayDecision(
                cityKey: cityKey,
                locale: locale,
                source: decision.source,
                title: resolved,
                fallbackTitle: fallbackTitle,
                chosenLevel: chosenLevel,
                parentRegionKey: parentRegionKey,
                availableLevelNames: availableLevelNames
            )
        )
        return resolved
    }

    static func displayTitle(
        cityKey: String,
        iso2: String?,
        fallbackTitle: String,
        availableLevelNamesRaw: [String: String]?,
        storedAvailableLevelNamesLocaleID: String? = nil,
        parentRegionKey: String? = nil,
        preferredLevel: CardLevel? = nil,
        localizedDisplayNameByLocale: [String: String]? = nil,
        locale: Locale = LanguagePreference.shared.displayLocale
    ) -> String {
        let decoded = preferredAvailableLevelNamesForDisplay(
            availableLevelNamesRaw,
            storedLocaleIdentifier: storedAvailableLevelNamesLocaleID,
            locale: locale
        )
        return displayTitle(
            cityKey: cityKey,
            iso2: iso2,
            fallbackTitle: fallbackTitle,
            availableLevelNames: decoded,
            parentRegionKey: parentRegionKey,
            preferredLevel: preferredLevel,
            localizedDisplayNameByLocale: localizedDisplayNameByLocale,
            locale: locale
        )
    }

    static func displayTitle(
        for cachedCity: CachedCity,
        locale: Locale = LanguagePreference.shared.displayLocale,
        preferredLevelOverride: CardLevel? = nil,
        localizedCandidate: String? = nil
    ) -> String {
        let localeID = locale.identifier
        var localizedMap = cachedCity.localizedDisplayNameByLocale ?? [:]
        if let localizedCandidate {
            let trimmed = localizedCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                localizedMap[localeID] = trimmed
            }
        }

        let identityLevel = preferredLevelOverride
            ?? cachedCity.identityLevelRaw.flatMap { CardLevel(rawValue: $0) }
            ?? inferIdentityLevel(cityKey: cachedCity.id, iso2: cachedCity.countryISO2)

        return displayTitle(
            cityKey: cachedCity.id,
            iso2: cachedCity.countryISO2,
            fallbackTitle: cachedCity.name,
            availableLevelNamesRaw: cachedCity.availableLevelNames,
            storedAvailableLevelNamesLocaleID: cachedCity.availableLevelNamesLocaleID,
            parentRegionKey: cachedCity.parentScopeKey,
            preferredLevel: identityLevel,
            localizedDisplayNameByLocale: localizedMap,
            locale: locale
        )
    }

    static func stableCityKey(
        selectedLevel: CardLevel?,
        canonicalAvailableLevels: [CardLevel: String],
        fallbackCityKey: String,
        iso2: String?
    ) -> String {
        let fallback = fallbackCityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedISO = (iso2 ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if let selectedLevel,
           let canonicalName = canonicalAvailableLevels[selectedLevel]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !canonicalName.isEmpty {
            return normalizedISO.isEmpty ? canonicalName : "\(canonicalName)|\(normalizedISO)"
        }

        return fallback
    }

    static func preferredStableCityKey(
        canonicalResult: ReverseGeocodeService.CanonicalResult
    ) -> String {
        stableCityKey(
            selectedLevel: nil,
            canonicalAvailableLevels: canonicalResult.availableLevels,
            fallbackCityKey: canonicalResult.cityKey,
            iso2: canonicalResult.iso2
        )
    }

    static func stableCityName(from cityKey: String, fallback: String) -> String {
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let split = cityKey
            .components(separatedBy: "|")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return split.isEmpty ? trimmedFallback : split
    }

    static func identityLevel(
        cityKey: String,
        availableLevelNames: [CardLevel: String]?,
        iso2: String? = nil
    ) -> CardLevel? {
        let cityNameFromKey = cityKey.components(separatedBy: "|").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedKeyName = normalizeForMatching(cityNameFromKey)
        guard !normalizedKeyName.isEmpty else { return nil }

        for level in [CardLevel.island, .locality, .subAdmin, .admin, .country] {
            let title = availableLevelNames?[level]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty, normalizeForMatching(title) == normalizedKeyName {
                return level
            }
        }

        let inferredISO2Source: String? = iso2 ?? cityKey
            .components(separatedBy: "|")
            .dropFirst()
            .first
            .map { String($0) }
        let inferredISO2 = inferredISO2Source?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .uppercased()
        if isRegionStyledDisplayKey(cityKey: cityKey, iso2: inferredISO2),
           let countryTitle = availableLevelNames?[.country]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !countryTitle.isEmpty {
            return .country
        }

        return nil
    }

    /// Infer identity level from city key + ISO2 using country-specific strategies,
    /// without requiring a placemark. Used as fallback when `identityLevelRaw` is nil.
    static func inferIdentityLevel(cityKey: String, iso2: String?) -> CardLevel {
        guard let iso2 = iso2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !iso2.isEmpty else {
            return .locality
        }
        if strategyCountry.contains(iso2) { return .country }
        let cityName = cityKey.components(separatedBy: "|").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if iso2 == "CN", isChineseMunicipality(cityName) { return .admin }
        if iso2 == "JP", cityName.contains("Tokyo") { return .admin }
        if iso2 == "KR", cityName.contains("Seoul") || cityName.contains("Busan") { return .admin }
        if iso2 == "TH", cityName.contains("Bangkok") { return .admin }
        if strategySubAdmin.contains(iso2) { return .subAdmin }
        return .locality
    }

    private static let strategyCountry: Set<String> = ["SG", "HK", "MO", "TW", "MC", "VA", "LI", "AD", "LU", "MT", "BH", "SC", "MV", "SM"]
    private static let strategySubAdmin: Set<String> = ["CN", "GB", "AU", "NZ", "FR", "IT", "ES", "NL", "CH", "ID", "PH", "VN", "MY", "BE", "SE", "NO", "DK"]

    private static func decideLevel(candidates: LevelCandidates, preferred: CardLevel?) -> CardLevel {
        // Island detection disabled — skip straight to preference / country strategy.

        if let preferred,
           preferred.isUserSelectable,
           let preferredName = candidates.name(for: preferred),
           !preferredName.isEmpty {
            return preferred
        }

        guard let iso2 = candidates.iso2 else {
            if candidates.locality != nil { return .locality }
            if candidates.subAdmin != nil { return .subAdmin }
            if candidates.admin != nil { return .admin }
            return .country
        }

        if strategyCountry.contains(iso2) { return .country }
        if iso2 == "CN", isChineseMunicipality(candidates.admin) { return .admin }
        if iso2 == "JP", candidates.admin?.contains("Tokyo") == true || candidates.admin?.contains("東京都") == true { return .admin }
        if iso2 == "KR", candidates.admin?.contains("Seoul") == true || candidates.admin?.contains("Busan") == true { return .admin }
        if iso2 == "TH", candidates.admin?.contains("Bangkok") == true { return .admin }

        if strategySubAdmin.contains(iso2), candidates.subAdmin != nil {
            return .subAdmin
        }

        if candidates.locality != nil { return .locality }
        if candidates.subAdmin != nil { return .subAdmin }
        if candidates.admin != nil { return .admin }

        return .country
    }

    private static func canonicalName(level: CardLevel, candidates: LevelCandidates) -> String {
        let rawName: String

        switch level {
        case .island:
            rawName = candidates.island ?? candidates.locality ?? candidates.subAdmin ?? candidates.admin ?? candidates.country ?? L10n.t("unknown")
        case .country:
            rawName = candidates.country ?? L10n.t("unknown")
        case .admin:
            rawName = candidates.admin ?? L10n.t("unknown")
        case .subAdmin:
            rawName = candidates.subAdmin ?? candidates.locality ?? candidates.admin ?? L10n.t("unknown")
        case .locality:
            rawName = candidates.locality ?? candidates.subAdmin ?? candidates.admin ?? L10n.t("unknown")
        }

        return stripAdminSuffix(rawName)
    }

    private static func makeLevelCandidates(from pm: CLPlacemark, preferredISO2: String?) -> LevelCandidates {
        let iso2 = clean(preferredISO2 ?? pm.isoCountryCode)?.uppercased()

        let locality = clean(pm.locality)
        let subAdmin = clean(pm.subAdministrativeArea)
        let admin = clean(pm.administrativeArea)
        let country = clean(pm.country)

        let islandFromFields = clean(pm.name)
        let island = detectIslandName(from: islandFromFields, locality: locality, subAdmin: subAdmin, admin: admin)

        let parentRegionBase = admin ?? country
        let parentRegionKey: String? = {
            guard let base = parentRegionBase else { return nil }
            let iso = iso2 ?? ""
            return "\(base)|\(iso)"
        }()

        return LevelCandidates(
            iso2: iso2,
            island: island,
            locality: locality,
            subAdmin: subAdmin.map(stripAdminSuffix),
            admin: admin.map(stripAdminSuffix),
            country: country,
            parentRegionKey: parentRegionKey
        )
    }

    private static func detectIslandName(from name: String?, locality: String?, subAdmin: String?, admin: String?) -> String? {
        // Island detection disabled — islands now use normal city-level resolution
        // (locality → subAdmin → admin → country) to avoid unstable CLGeocoder pm.name
        // causing level drift between island/locality/country.
        return nil
    }

    private static func isChineseMunicipality(_ admin: String?) -> Bool {
        guard let a = admin else { return false }
        let municipalities = ["Beijing", "Shanghai", "Tianjin", "Chongqing", "北京市", "上海市", "天津市", "重庆市"]
        return municipalities.contains { a.contains($0) }
    }

    private static func isChineseDistrictLike(_ s: String) -> Bool {
        let suffixes = ["区", "县", "旗", "新区", "市辖区", "自治县", "自治旗"]
        if suffixes.contains(where: { s.hasSuffix($0) }) { return true }

        let containsTokens = ["街道", "镇", "乡", "苏木", "嘎查", "开发区", "工业园", "高新区"]
        if containsTokens.contains(where: { s.contains($0) }) { return true }

        return false
    }

    private static func stripAdminSuffix(_ s: String) -> String {
        let suffixes = [" City", " Shi", " Prefecture", " District", "市", "区", "县"]
        var result = s
        for suffix in suffixes where result.hasSuffix(suffix) {
            result = String(result.dropLast(suffix.count))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func localizedSpecialCountryNameIfNeeded(iso2: String?, fallbackCountry: String?) -> String? {
        guard let iso2 else { return fallbackCountry }
        switch iso2 {
        case "HK": return fallbackCountry ?? "Hong Kong"
        case "MO": return fallbackCountry ?? "Macau"
        case "SG": return fallbackCountry ?? "Singapore"
        default: return fallbackCountry
        }
    }

    private static func isRegionStyledISO(_ iso2: String?) -> Bool {
        guard let iso2 else { return false }
        return ["HK", "MO", "TW"].contains(iso2.uppercased())
    }

    private static func decodedKeyedLevels(_ availableLevelNamesRaw: [String: String]?) -> [(CardLevel, String)] {
        guard let availableLevelNamesRaw else { return [] }
        return availableLevelNamesRaw.compactMap { key, value in
            guard let level = CardLevel(rawValue: key) else { return nil }
            return (level, value)
        }
    }

    private static func decodeAvailableLevelNames(_ availableLevelNamesRaw: [String: String]?) -> [CardLevel: String] {
        var decoded: [CardLevel: String] = [:]
        for (level, value) in decodedKeyedLevels(availableLevelNamesRaw) {
            decoded[level] = value
        }
        return decoded
    }

    static func preferredAvailableLevelNamesForDisplay(
        _ availableLevelNamesRaw: [String: String]?,
        storedLocaleIdentifier: String? = nil,
        locale: Locale = LanguagePreference.shared.displayLocale
    ) -> [CardLevel: String]? {
        let decoded = decodeAvailableLevelNames(availableLevelNamesRaw)
        guard !decoded.isEmpty else { return nil }

        // Always check per-value locale compatibility.
        // Even when storedLocaleIdentifier matches, individual values may have been
        // written at different times under different locales (mixed-locale data).
        let hasIncompatibleValue = decoded.values.contains { value in
            !shouldUseStoredDisplayTitle(value, locale: locale)
        }
        if hasIncompatibleValue { return nil }

        if let storedLocaleIdentifier,
           localeDisplayLanguageIdentifier(storedLocaleIdentifier) == localeDisplayLanguageIdentifier(locale.identifier) {
            return decoded
        }
        if storedLocaleIdentifier != nil {
            return nil
        }

        return decoded
    }

    /// Resolve stable per-level labels for the current locale.
    /// Priority:
    /// 1) Stored labels if they match current locale language.
    /// 2) Freshly resolved labels when stored labels look flattened/inconsistent.
    /// 3) Freshly resolved labels (first-time initialization or language switch).
    static func resolvedStableLevelNamesForDisplay(
        storedAvailableLevelNamesRaw: [String: String]?,
        storedLocaleIdentifier: String?,
        freshlyResolvedLevelNames: [CardLevel: String],
        locale: Locale = LanguagePreference.shared.displayLocale
    ) -> [CardLevel: String] {
        if let stored = preferredAvailableLevelNamesForDisplay(
            storedAvailableLevelNamesRaw,
            storedLocaleIdentifier: storedLocaleIdentifier,
            locale: locale
        ), !stored.isEmpty,
           !looksFlattenedComparedToFresh(stored: stored, fresh: freshlyResolvedLevelNames) {
            return stored
        }
        return freshlyResolvedLevelNames
    }

    private static func looksFlattenedComparedToFresh(
        stored: [CardLevel: String],
        fresh: [CardLevel: String]
    ) -> Bool {
        let levels: [CardLevel] = [.locality, .subAdmin, .admin]

        func uniqueCount(_ labels: [CardLevel: String]) -> Int {
            let values = levels.compactMap { level -> String? in
                let trimmed = (labels[level] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return normalizeForMatching(trimmed)
            }
            return Set(values).count
        }

        let storedUnique = uniqueCount(stored)
        let freshUnique = uniqueCount(fresh)
        return storedUnique <= 1 && freshUnique > 1
    }

    private static func resolvedDisplayLevel(
        cityKey: String,
        availableLevelNames: [CardLevel: String]?,
        parentRegionKey: String?,
        preferredLevel: CardLevel?
    ) -> CardLevel? {
        if let preferredLevel,
           let title = availableLevelNames?[preferredLevel]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return preferredLevel
        }

        // Use country-strategy rules to infer the correct level from cityKey + iso2.
        // This is locale-independent and matches the level that decideLevel() would pick.
        let iso2 = cityKey.components(separatedBy: "|").dropFirst().first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        let inferred = inferIdentityLevel(cityKey: cityKey, iso2: iso2)
        if let title = availableLevelNames?[inferred]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return inferred
        }

        return nil
    }

    static func isRegionStyledDisplayKey(cityKey: String, iso2: String?) -> Bool {
        guard let iso2, isRegionStyledISO(iso2) else { return false }
        let cityNameFromKey = cityKey.components(separatedBy: "|").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return matchesRegionAlias(cityNameFromKey, iso2: iso2)
    }

    private static func normalizeUserFacingTitle(
        _ rawTitle: String,
        iso2: String?,
        level: CardLevel?,
        locale: Locale
    ) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L10n.t("unknown", locale: locale) }

        guard let iso2, isRegionStyledISO(iso2) else {
            return trimmed
        }

        let shouldCanonicalizeRegion = level == .admin || level == .country || matchesRegionAlias(trimmed, iso2: iso2)
        if shouldCanonicalizeRegion, let localized = localizedRegionName(iso2: iso2, locale: locale) {
            return localized
        }

        return trimmed
    }

    private static func matchesRegionAlias(_ rawTitle: String, iso2: String) -> Bool {
        let normalized = normalizeForMatching(rawTitle)
        guard !normalized.isEmpty else { return false }

        let aliases: [String]
        switch iso2.uppercased() {
        case "TW":
            aliases = [
                "taiwan", "taiwanprovince", "台湾", "台灣", "中国台湾",
                "中國台灣", "台湾省", "台灣省"
            ]
        case "HK":
            aliases = [
                "hongkong", "hongkongsar", "chinahongkongsar",
                "hongkongspecialadministrativeregion", "香港", "中国香港",
                "中國香港", "香港特别行政区", "香港特別行政區",
                "中国香港特别行政区", "中國香港特別行政區",
                "中国香港特区", "中國香港特區"
            ]
        case "MO":
            aliases = [
                "macau", "macao", "macaosar", "chinamacaosar",
                "macaospecialadministrativeregion", "澳门", "澳門",
                "中国澳门", "中國澳門", "澳门特别行政区",
                "澳門特別行政區", "中国澳门特别行政区", "中國澳門特別行政區"
            ]
        default:
            aliases = []
        }

        return aliases.contains(normalized)
    }

    private static func localizedRegionName(iso2: String?, locale: Locale) -> String? {
        guard let iso2 else { return nil }
        let languageCode = locale.identifier.lowercased()
        let isTraditionalChinese = languageCode.hasPrefix("zh-hant") || languageCode.hasPrefix("zh-hk") || languageCode.hasPrefix("zh-tw")
        let isChinese = languageCode.hasPrefix("zh")

        switch iso2.uppercased() {
        case "TW":
            if isTraditionalChinese { return "台灣" }
            if isChinese { return "台湾" }
            return "Taiwan"
        case "HK":
            if isChinese { return "香港" }
            return "Hong Kong"
        case "MO":
            if isTraditionalChinese { return "澳門" }
            if isChinese { return "澳门" }
            return "Macau"
        default:
            return nil
        }
    }

    private static func regionFallbackName(from candidates: LevelCandidates) -> String? {
        candidates.admin ?? candidates.subAdmin ?? candidates.locality ?? candidates.country
    }

    private static func regionSubtitle(from candidates: LevelCandidates, title: String) -> String? {
        let normalizedTitle = normalizeForMatching(title)
        let regionCandidates = [candidates.admin, candidates.subAdmin, candidates.locality]
        for candidate in regionCandidates {
            let trimmed = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if normalizeForMatching(trimmed) != normalizedTitle {
                return trimmed
            }
        }
        return nil
    }

    private static func normalizeForMatching(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .lowercased()
    }

    private static func shouldUseStoredLevelTitle(_ title: String, locale: Locale) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return shouldUseStoredDisplayTitle(trimmed, locale: locale)
    }

    private static func looksASCIIOnly(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (scalar.properties.isAlphabetic || scalar.properties.isWhitespace || scalar.properties.generalCategory == .dashPunctuation)
        }
    }

    private static func shouldUseStoredDisplayTitle(_ title: String, locale: Locale) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let languageCode = localeDisplayLanguageIdentifier(locale.identifier)
        if ["zh", "ja", "ko"].contains(languageCode) {
            return !looksASCIIOnly(trimmed)
        }
        if languageCode == "en" {
            return !containsCJKCharacters(trimmed)
        }
        return true
    }

    private static func localeDisplayLanguageIdentifier(_ localeIdentifier: String) -> String {
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        return normalized.split(separator: "-").first.map(String.init)?.lowercased() ?? normalized.lowercased()
    }

    private static func containsCJKCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0x3040...0x309F, 0x30A0...0x30FF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    private static func clean(_ s: String?) -> String? {
        let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    // MARK: - Sync UserDefaults cache lookup

    /// Lazy-loaded cache from ReverseGeocodeService's persisted UserDefaults.
    /// Avoids repeated disk reads on every `displayTitle()` call.
    private static let geocodeDefaultsCache: [String: String] = {
        let defaults = UserDefaults(suiteName: "group.com.streetstamps.shared") ?? .standard
        guard let data = defaults.data(forKey: "reverseGeocode.displayCacheByLocaleKey.v2"),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }()

    /// Synchronous lookup of a display title from ReverseGeocodeService's persisted cache.
    private static func syncCachedDisplayTitle(cityKey: String, parentRegionKey: String?, locale: Locale) -> String? {
        let scope = CityLevelPreferenceStore.shared.displayCacheScope(for: parentRegionKey)
        let cacheKey = "\(cityKey)|\(locale.identifier)|\(scope)"
        guard let title = geocodeDefaultsCache[cacheKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }
        return title
    }
}

extension CityPlacemarkResolver.Canonical {
    var cityKey: String {
        let iso = (iso2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "\(city)|\(iso)"
    }
}

enum JourneyCityNamePresentation {
    static func parentRegionKey(
        for journey: JourneyRoute,
        cachedCitiesByKey: [String: CachedCity]
    ) -> String? {
        let key = journey.stableCityKey ?? ""
        guard !key.isEmpty else { return nil }
        return cachedCitiesByKey[key]?.parentScopeKey
    }

    static func title(for journey: JourneyRoute, localizedCityNameByKey: [String: String]) -> String {
        title(
            for: journey,
            localizedCityNameByKey: localizedCityNameByKey,
            cachedCitiesByKey: [:],
            locale: LanguagePreference.shared.displayLocale
        )
    }

    static func title(
        for journey: JourneyRoute,
        localizedCityNameByKey: [String: String],
        cachedCitiesByKey: [String: CachedCity],
        locale: Locale = LanguagePreference.shared.displayLocale
    ) -> String {
        let key = (journey.stableCityKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let localized = localizedCityNameByKey[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localized.isEmpty {
            return localized
        }
        if let cachedCity = cachedCitiesByKey[key] {
            let title = cachedCity.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
        }
        return key.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? journey.displayCityName
    }
}

enum CityDisplayTitlePresentation {
    static func title(
        cityKey: String?,
        iso2: String?,
        fallbackTitle: String?,
        localizedCityNameByKey: [String: String] = [:],
        availableLevelNamesRaw: [String: String]? = nil,
        parentRegionKey: String? = nil,
        localizedDisplayNameByLocale: [String: String]? = nil,
        locale: Locale = LanguagePreference.shared.displayLocale
    ) -> String {
        let trimmedKey = (cityKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let localized = localizedCityNameByKey[trimmedKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localized.isEmpty {
            return localized
        }

        let trimmedFallback = (fallbackTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return trimmedFallback.isEmpty ? L10n.t("unknown") : trimmedFallback
        }

        return CityPlacemarkResolver.displayTitle(
            cityKey: trimmedKey,
            iso2: iso2,
            fallbackTitle: trimmedFallback.isEmpty ? trimmedKey : trimmedFallback,
            availableLevelNamesRaw: availableLevelNamesRaw,
            parentRegionKey: parentRegionKey,
            localizedDisplayNameByLocale: localizedDisplayNameByLocale,
            locale: locale
        )
    }
}
