import XCTest
@testable import StreetStamps

final class SettingsGeneralPresentationTests: XCTestCase {
    func test_rows_doNotIncludeFriendUIPreview() {
        let titles = SettingsGeneralPresentation.rows().map(\.title)

        XCTAssertFalse(titles.contains("FRIEND UI PREVIEW"))
    }

    func test_rows_includeBaseGeneralEntries() {
        let rows = SettingsGeneralPresentation.rows()

        XCTAssertEqual(rows.map(\.destination), debugExpectedDestinations)
        XCTAssertEqual(rows.first?.title, L10n.t("settings_import_gpx_row"))
        XCTAssertEqual(rows.dropFirst().first?.title, L10n.t("settings_notifications_title"))
    }

    func test_trackingAssistRows_areEmptyWhenNotificationTogglesMoveToNotificationsPage() {
        let rows = SettingsTrackingAssistPresentation.toggleRows()

        XCTAssertTrue(rows.isEmpty)
    }

    func test_notificationToggleRows_includeLiveActivityAndStationaryReminder() {
        let rows = SettingsNotificationsPresentation.toggleRows(isLiveActivityAvailable: true)

        XCTAssertEqual(rows.map(\.title), [
            L10n.t("settings_live_activity_title"),
            L10n.t("settings_stationary_reminder_title")
        ])
    }

    func test_notificationToggleRows_showGuidanceWhenLiveActivitiesAreDisabledInSystemSettings() {
        let rows = SettingsNotificationsPresentation.toggleRows(isLiveActivityAvailable: false)

        XCTAssertEqual(rows.first?.subtitle, L10n.t("settings_live_activity_system_disabled_desc"))
    }

    func test_informationRows_keepCheckUpdatesAtStandardHeight() {
        let rows = SettingsInformationPresentation.rows(appVersionText: "V1.0.0")

        XCTAssertEqual(rows.first?.title, L10n.t("settings_check_updates_title"))
        XCTAssertEqual(rows.first?.rowHeight, 64)
    }

    private var debugExpectedDestinations: [SettingsGeneralRowPresentation.Destination] {
#if DEBUG
        return [.importGPX, .notifications, .debugTools]
#else
        return [.importGPX, .notifications]
#endif
    }
}
