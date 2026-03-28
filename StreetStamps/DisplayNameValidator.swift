import Foundation

enum DisplayNameValidator {

    static let maxLength = 24

    /// Returns a localized error message if the display name is invalid, or `nil` if valid.
    static func validate(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L10n.t("profile_name_empty") }
        guard trimmed.count <= maxLength else { return L10n.t("profile_name_too_long") }
        guard !trimmed.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else {
            return L10n.t("profile_name_no_spaces")
        }
        let allowed = CharacterSet.letters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "._-"))
        let valid = trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
        return valid ? nil : L10n.t("profile_name_charset")
    }

    /// Returns the trimmed name, ready for submission.
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
