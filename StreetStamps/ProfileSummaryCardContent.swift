import Foundation

struct ProfileSummaryCardContent: Equatable {
    let level: Int
    let cityCount: Int
    let memoryCount: Int
    let locale: Locale

    var levelText: String {
        "Lv.\(level)"
    }

    var statsText: String {
        String(
            format: L10n.t("profile_summary_stats_format", locale: locale),
            locale: locale,
            cityCount,
            memoryCount
        )
    }

    init(level: Int, cityCount: Int, memoryCount: Int, locale: Locale = .current) {
        self.level = level
        self.cityCount = cityCount
        self.memoryCount = memoryCount
        self.locale = locale
    }
}
