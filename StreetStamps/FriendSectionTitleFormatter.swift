import Foundation

enum FriendSectionTitleFormatter {
    enum Section {
        case journeys
        case cityCards
        case journeyMemories
        case journeyDetail
    }

    static func sectionTitle(for section: Section, friendName: String, locale: Locale = .current) -> String {
        let labelKey: String
        switch section {
        case .journeys:
            labelKey = "journeys_title"
        case .cityCards:
            labelKey = "friend_city_cards_title"
        case .journeyMemories:
            labelKey = "journey_memory"
        case .journeyDetail:
            labelKey = "friend_journey_detail_title"
        }

        let format = L10n.t("friend_section_title_format", locale: locale)
        let label = L10n.t(labelKey, locale: locale)
        return String(format: format, locale: locale, friendName, label)
    }
}
