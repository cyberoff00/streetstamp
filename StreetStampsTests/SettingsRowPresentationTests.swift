import XCTest
@testable import StreetStamps

final class SettingsRowPresentationTests: XCTestCase {
    func test_profileVisibilityFriendsOnly_usesSingleLineTitleAndPersonIcon() {
        let row = SettingsRowPresentation.profileVisibility(.friendsOnly)

        XCTAssertEqual(row.title, L10n.t("settings_profile_visibility_friends"))
        XCTAssertNil(row.subtitle)
        XCTAssertEqual(row.icon, "person.2")
        XCTAssertEqual(row.textStyle, .singleLine)
    }

    func test_profileVisibilityPrivate_usesSingleLineTitleAndPersonIcon() {
        let row = SettingsRowPresentation.profileVisibility(.private)

        XCTAssertEqual(row.title, L10n.t("settings_profile_visibility_private"))
        XCTAssertNil(row.subtitle)
        XCTAssertEqual(row.icon, "person.2")
        XCTAssertEqual(row.textStyle, .singleLine)
    }

    func test_mapDarkMode_usesSingleLineMapCopyAndIcon() {
        let row = SettingsRowPresentation.mapDarkMode

        XCTAssertEqual(row.title, L10n.t("settings_map_dark_mode"))
        XCTAssertNil(row.subtitle)
        XCTAssertEqual(row.icon, "map")
        XCTAssertEqual(row.textStyle, .singleLine)
    }

    func test_stationaryReminder_keepsSupportingTextStyle() {
        let row = SettingsRowPresentation.stationaryReminder

        XCTAssertEqual(row.title, L10n.t("settings_stationary_reminder_title"))
        XCTAssertEqual(row.subtitle, L10n.t("settings_stationary_reminder_desc"))
        XCTAssertEqual(row.icon, "bell.badge")
        XCTAssertEqual(row.textStyle, .supporting)
    }
}
