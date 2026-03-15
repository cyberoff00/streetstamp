import Foundation

final class LanguagePreference: ObservableObject {
    static let shared = LanguagePreference()

    @Published var currentLanguage: String? {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "app_language")
        }
    }

    private init() {
        currentLanguage = UserDefaults.standard.string(forKey: "app_language")
    }

    var effectiveLanguages: [String] {
        if let lang = currentLanguage {
            return [lang]
        }
        return Locale.preferredLanguages
    }
}
