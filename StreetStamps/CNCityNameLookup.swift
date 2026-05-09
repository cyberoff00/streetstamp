import Foundation

struct CNCityEntry {
    let zh: String
    let en: String
    let province: String
    let iso2: String
    let aliases: [String]

    init(zh: String, en: String, province: String, iso2: String = "CN", aliases: [String] = []) {
        self.zh = zh
        self.en = en
        self.province = province
        self.iso2 = iso2
        self.aliases = aliases
    }
}

final class CNCityNameLookup {
    static let shared = CNCityNameLookup()

    private struct AliasMatch {
        let zh: String
        let normalizedProvince: String
        let iso2: String
    }

    private let primary: [String: String]
    private let aliasIndex: [String: [AliasMatch]]
    private let byEnSingleton: [String: String]

    private init() {
        var primary: [String: String] = [:]
        var aliasIndex: [String: [AliasMatch]] = [:]
        var enKeyToZhSet: [String: Set<String>] = [:]

        for entry in cnCityMappings {
            let nEn = Self.normalize(entry.en)
            let nProv = Self.normalize(entry.province)
            let iso = entry.iso2.uppercased()

            primary["\(nEn)|\(nProv)|\(iso)"] = entry.zh
            enKeyToZhSet["\(nEn)|\(iso)", default: []].insert(entry.zh)

            for alias in entry.aliases {
                let nAlias = Self.normalize(alias)
                aliasIndex[nAlias, default: []].append(
                    AliasMatch(zh: entry.zh, normalizedProvince: nProv, iso2: iso)
                )
                enKeyToZhSet["\(nAlias)|\(iso)", default: []].insert(entry.zh)
            }
        }

        var byEnSingleton: [String: String] = [:]
        for (key, zhSet) in enKeyToZhSet where zhSet.count == 1 {
            byEnSingleton[key] = zhSet.first
        }

        self.primary = primary
        self.aliasIndex = aliasIndex
        self.byEnSingleton = byEnSingleton

        Self.purgeLegacyTranslationCache()
    }

    private static func purgeLegacyTranslationCache() {
        let sharedDefaults = UserDefaults(suiteName: "group.com.streetstamps.shared") ?? .standard
        for key in [
            "cityNameTranslation.cache.v1",
            "cityNameTranslation.cache.v2",
            "cityNameTranslation.cache.v3",
            "reverseGeocode.displayCacheByLocaleKey.v2",
            "reverseGeocode.displayCacheByLocaleKey.v7"
        ] {
            sharedDefaults.removeObject(forKey: key)
        }
    }

    func zhName(enCity: String, province: String?, iso2: String) -> String? {
        let nEn = Self.normalize(enCity)
        let nProv = province.map(Self.normalize) ?? ""
        let nIso = iso2.uppercased()

        if !nProv.isEmpty, let zh = primary["\(nEn)|\(nProv)|\(nIso)"] {
            return zh
        }
        if let zh = primary["\(nEn)||\(nIso)"] {
            return zh
        }
        if !nProv.isEmpty, let zh = primary["\(nEn)|\(nEn)|\(nIso)"], nEn != nProv {
            return zh
        }

        if let candidates = aliasIndex[nEn] {
            if !nProv.isEmpty,
               let m = candidates.first(where: { $0.iso2 == nIso && $0.normalizedProvince == nProv }) {
                return m.zh
            }
            if nProv.isEmpty,
               let m = candidates.first(where: { $0.iso2 == nIso && $0.normalizedProvince.isEmpty }) {
                return m.zh
            }
        }

        if nProv.isEmpty, let zh = byEnSingleton["\(nEn)|\(nIso)"] {
            return zh
        }

        return nil
    }

    /// Convenience: resolves a Chinese display name from a cityKey + locale.
    /// Returns nil for non-zh locales OR when the city is unmappable.
    /// Caller falls back to its own English title (cityName / fallbackTitle).
    func displayName(for cityKey: String, locale: Locale) -> String? {
        let localeID = locale.identifier
        guard localeID.hasPrefix("zh") else { return nil }
        let parts = cityKey.split(separator: "|", omittingEmptySubsequences: false)
        let enCity = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let iso2 = parts.dropFirst().first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        guard !enCity.isEmpty, !iso2.isEmpty else { return nil }
        guard let zh = zhName(enCity: enCity, province: nil, iso2: iso2) else { return nil }
        return localeID.hasPrefix("zh-Hant") ? Self.toTraditional(zh) : zh
    }

    static func toTraditional(_ simplified: String) -> String {
        let mutable = NSMutableString(string: simplified)
        CFStringTransform(mutable, nil, "Simplified-Traditional" as CFString, false)
        return mutable as String
    }

    static func normalize(_ s: String) -> String {
        var lower = s.lowercased()

        let toRemove = [
            " city", " municipality", " province", " prefecture",
            " league", " region", " autonomous",
            " uyghur", " zhuang", " hui", " tibetan", " qiang", " mongolian", " yi", " bai", " miao",
            " shi"
        ]
        for token in toRemove {
            lower = lower.replacingOccurrences(of: token, with: "")
        }

        let punctuation: [Character] = [" ", "-", "'", "\u{2019}", ".", ","]
        return lower.filter { !punctuation.contains($0) }
    }
}
