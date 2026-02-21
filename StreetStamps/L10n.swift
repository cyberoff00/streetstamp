import Foundation
import SwiftUI

/// Minimal i18n helper.
///
/// Backed by `Localizable.strings` in each language.
enum L10n {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /// Convenience for `Text`.
    static func key(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }
}
