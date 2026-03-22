import Foundation
import SwiftUI

/// Minimal i18n helper.
///
/// Backed by `Localizable.strings` in each language.
enum L10n {
    private static let stringsCacheLock = NSLock()
    private static var stringsCache: [String: [String: String]] = [:]

    static func t(_ key: String) -> String {
        let value = localizedValue(for: key, preferredLanguages: LanguagePreference.shared.effectiveLanguages)
        #if DEBUG
        if value == key {
            print("⚠️ Localization missing for key: \(key), locale: \(Locale.current.identifier)")
        }
        #endif
        return value
    }

    static func t(_ key: String, locale: Locale) -> String {
        localizedValue(for: key, preferredLanguages: [locale.identifier], currentLocale: locale)
    }

    static func upper(_ key: String, locale: Locale = .current) -> String {
        uppercasedValue(t(key, locale: locale), locale: locale)
    }

    /// Convenience for `Text`.
    static func key(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }

    static func localizedValue(
        for key: String,
        preferredLanguages: [String] = Locale.preferredLanguages,
        currentLocale: Locale = .current,
        bundle: Bundle = .main
    ) -> String {
        let fallback = bundle.localizedString(forKey: key, value: nil, table: nil)
        let resolved = localizedString(
            for: key,
            preferredLanguages: preferredLanguages,
            currentLocale: currentLocale,
            bundle: bundle
        )

        guard let resolved else { return fallback }
        return resolved == key ? fallback : resolved
    }

    static func preferredLocalizationName(
        preferredLanguages: [String] = Locale.preferredLanguages,
        currentLocale: Locale = .current,
        availableLocalizations: [String] = Bundle.main.localizations
    ) -> String? {
        let discovered = discoveredLocalizations(in: .main)
        let mergedLocalizations = Array(Set(availableLocalizations + discovered))
        let preferences = localizationPreferences(
            preferredLanguages: preferredLanguages,
            currentLocale: currentLocale
        )
        return Bundle
            .preferredLocalizations(from: mergedLocalizations, forPreferences: preferences)
            .first(where: { !$0.isEmpty && $0 != "Base" })
    }

    private static func localizedString(
        for key: String,
        preferredLanguages: [String],
        currentLocale: Locale,
        bundle: Bundle
    ) -> String? {
        let preferences = localizationPreferences(
            preferredLanguages: preferredLanguages,
            currentLocale: currentLocale
        )

        for localization in preferences {
            if let value = localizedString(for: key, localization: localization, bundle: bundle) {
                return value
            }
        }

        if let localization = Bundle
            .preferredLocalizations(
                from: Array(Set(bundle.localizations + discoveredLocalizations(in: bundle))),
                forPreferences: preferences
            ).first(where: { !$0.isEmpty && $0 != "Base" }) {
            return localizedString(for: key, localization: localization, bundle: bundle)
        }

        return nil
    }

    private static func uppercasedValue(_ value: String, locale: Locale) -> String {
        value.uppercased(with: locale)
    }

    private static func localizationPreferences(
        preferredLanguages: [String],
        currentLocale: Locale
    ) -> [String] {
        var values: [String] = []

        for identifier in preferredLanguages + [currentLocale.identifier] {
            for candidate in localizationCandidates(forIdentifier: identifier) where !values.contains(candidate) {
                values.append(candidate)
            }
        }

        return values
    }

    private static func localizationCandidates(forIdentifier identifier: String) -> [String] {
        let normalized = identifier
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var values: [String] = [normalized]
        let lowercased = normalized.lowercased()
        let parts = normalized.split(separator: "-").map(String.init)

        if parts.count >= 2 {
            let languageAndRegion = parts.prefix(2).joined(separator: "-")
            if !values.contains(languageAndRegion) {
                values.append(languageAndRegion)
            }
        }

        if let language = parts.first, !language.isEmpty, !values.contains(language) {
            values.append(language)
        }

        if lowercased.hasPrefix("zh") {
            let isTraditionalChinese =
                lowercased.contains("hant") ||
                lowercased.hasPrefix("zh-tw") ||
                lowercased.hasPrefix("zh-hk") ||
                lowercased.hasPrefix("zh-mo")
            let canonical = isTraditionalChinese ? "zh-Hant" : "zh-Hans"
            if !values.contains(canonical) {
                values.append(canonical)
            }
        }

        return values
    }

    private static func discoveredLocalizations(in bundle: Bundle) -> [String] {
        guard let resourcePath = bundle.resourcePath,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) else {
            return []
        }
        return entries
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }
    }

    private static func localizedString(
        for key: String,
        localization: String,
        bundle: Bundle
    ) -> String? {
        guard let stringsPath = bundle.path(
            forResource: "Localizable",
            ofType: "strings",
            inDirectory: nil,
            forLocalization: localization
        ) else {
            return nil
        }

        guard let strings = stringsDictionary(at: stringsPath),
              let value = strings[key],
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func stringsDictionary(at path: String) -> [String: String]? {
        stringsCacheLock.lock()
        if let cached = stringsCache[path] {
            stringsCacheLock.unlock()
            return cached
        }
        stringsCacheLock.unlock()

        guard let dictionary = NSDictionary(contentsOfFile: path) as? [String: String] else {
            return nil
        }

        stringsCacheLock.lock()
        stringsCache[path] = dictionary
        stringsCacheLock.unlock()
        return dictionary
    }
}
