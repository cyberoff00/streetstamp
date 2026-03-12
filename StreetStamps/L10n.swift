import Foundation
import SwiftUI

/// Minimal i18n helper.
///
/// Backed by `Localizable.strings` in each language.
enum L10n {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func t(_ key: String, locale: Locale) -> String {
        localizedBundle(for: locale)?
            .localizedString(forKey: key, value: nil, table: nil)
            ?? NSLocalizedString(key, comment: "")
    }

    static func upper(_ key: String, locale: Locale = .current) -> String {
        uppercasedValue(t(key, locale: locale), locale: locale)
    }

    /// Convenience for `Text`.
    static func key(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }

    private static func localizedBundle(for locale: Locale) -> Bundle? {
        let candidates = localizationCandidates(for: locale)
        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
    }

    private static func uppercasedValue(_ value: String, locale: Locale) -> String {
        value.uppercased(with: locale)
    }

    private static func localizationCandidates(for locale: Locale) -> [String] {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        var values: [String] = []

        if !identifier.isEmpty {
            values.append(identifier)
            let parts = identifier.split(separator: "-").map(String.init)
            if parts.count >= 2 {
                values.append(parts.prefix(2).joined(separator: "-"))
            }
            if let first = parts.first, !first.isEmpty {
                values.append(first)
            }
        }

        var unique: [String] = []
        for value in values where !unique.contains(value) {
            unique.append(value)
        }
        return unique
    }
}
