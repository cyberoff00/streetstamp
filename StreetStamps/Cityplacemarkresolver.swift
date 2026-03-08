import Foundation
import CoreLocation

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
        let preferred = CityLevelPreferenceStore.shared.preferredLevel(for: candidates.parentRegionKey)
        let level = decideLevel(candidates: candidates, preferred: preferred)
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
        let preferred = CityLevelPreferenceStore.shared.preferredLevel(for: candidates.parentRegionKey)
        let level = decideLevel(candidates: candidates, preferred: preferred)
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
            title: title,
            subtitle: subtitle,
            iso2: candidates.iso2,
            level: level,
            admin: candidates.admin,
            subAdmin: candidates.subAdmin,
            country: candidates.country
        )
    }

    private static let strategyCountry: Set<String> = ["SG", "HK", "MO", "MC", "VA", "LI", "AD", "LU", "MT", "BH", "SC", "MV", "SM"]
    private static let strategySubAdmin: Set<String> = ["CN", "GB", "AU", "NZ", "FR", "IT", "ES", "NL", "CH", "ID", "PH", "VN", "MY", "BE", "SE", "NO", "DK"]

    private static func decideLevel(candidates: LevelCandidates, preferred: CardLevel?) -> CardLevel {
        if candidates.island != nil { return .island }

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
        let candidate = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        let lower = candidate.lowercased()
        let looksLikeIsland = lower.contains(" island") || lower.contains(" islands") || candidate.contains("岛")
        if !looksLikeIsland { return nil }

        let compareTargets = [locality, subAdmin, admin].compactMap { $0?.lowercased() }
        if compareTargets.contains(lower) { return nil }

        return candidate
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
            .lowercased()
    }

    private static func clean(_ s: String?) -> String? {
        let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

extension CityPlacemarkResolver.Canonical {
    var cityKey: String {
        let iso = (iso2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "\(city)|\(iso)"
    }
}
