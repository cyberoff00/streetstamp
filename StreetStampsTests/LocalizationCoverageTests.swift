import XCTest
@testable import StreetStamps

final class LocalizationCoverageTests: XCTestCase {
    func test_requiredFormalUserFacingKeysExistInEnglishAndSimplifiedChinese() throws {
        let appRoot = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let english = try loadStringsFile(at: appRoot.appendingPathComponent("en.lproj/Localizable.strings"))
        let simplifiedChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))

        let requiredKeys = [
            "tab_home",
            "tab_friends",
            "tab_collection",
            "tab_memory",
            "main_resume_onboarding",
            "open_sidebar",
            "collection_title",
            "collection_segment_cities",
            "collection_segment_journeys",
            "profile_invite_friends",
            "profile_notifications_title",
            "profile_edit_name_title",
            "profile_name_placeholder",
            "profile_name_rules",
            "profile_friend_invite_code",
            "profile_share_card",
            "profile_send_friend_request",
            "profile_friend_request_input",
            "profile_send_friend_request_button",
            "profile_scan_qr_code",
            "friends_logged_out_title",
            "friends_logged_out_message",
            "friends_go_login",
            "friends_accept",
            "friends_ignore",
            "friends_waiting_approval",
            "friends_mark_all_read",
            "friends_delete_friend",
            "friends_delete_failed",
            "friends_joined_format",
            "settings_coming_soon_title",
            "settings_notifications_title",
            "settings_edit_name_title",
            "settings_private_transfer_title",
            "settings_transfer_old_device",
            "settings_transfer_new_device",
            "settings_transfer_generate_qr",
            "settings_transfer_scan_import",
            "settings_import_failed_title",
            "settings_sign_in_title",
            "settings_sign_in_subtitle",
            "guest_mode",
            "not_linked",
            "account_center_title",
            "done",
            "please_sign_in_to_access_your_account",
            "backend_configuration",
            "journey_change_visibility",
            "journey_current_visibility_format",
            "journey_visibility_login_required",
            "journey_visibility_requires_distance_or_memory",
            "journey_confirm_change",
            "journey_likes_title",
            "journey_change_permission",
            "journey_likes_loading",
            "journey_loading_failed_format",
            "journey_no_likes_yet",
            "equipment_try_on_mode",
            "equipment_apply_try_on",
            "equipment_unowned_items",
            "equipment_total_price_format",
            "equipment_buy_all_and_apply",
            "postcard_sync_error_format",
            "details_unavailable_title",
            "details_unavailable_message",
            "verify_your_email",
            "resend_verification_email",
            "i_verified_my_email",
            "verification_email_sent",
            "email_still_unverified",
            "main_unlock_new_journey",
            "discard_changes_title",
            "long_stationary_reminder_title",
            "long_stationary_reminder_body",
            "postcard_received_title_format",
            "postcard_received_title_fallback",
            "postcard_received_body_format",
            "lockscreen_mode_sport_short",
            "lockscreen_mode_daily_short",
            "lockscreen_distance_unit_km_short",
            "watch_status_recording",
            "watch_status_paused",
            "watch_status_permission_needed",
            "watch_status_sync_waiting"
        ]

        for key in requiredKeys {
            XCTAssertNotNil(english[key], "Missing English localization for key \(key)")
            XCTAssertNotNil(simplifiedChinese[key], "Missing Simplified Chinese localization for key \(key)")
        }
    }

    func test_infoPlistLocalizedResourcesExistForAppWatchAndWidget() {
        let root = projectRoot()
        let appLanguages = ["en", "zh-Hans", "zh-Hant", "es", "fr", "ja", "ko"]

        for language in appLanguages {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent("StreetStamps/\(language).lproj/InfoPlist.strings").path
                ),
                "Missing app InfoPlist localization for \(language)"
            )
        }

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("StreetStampsWatch/en.lproj/InfoPlist.strings").path
            ),
            "Missing watch English InfoPlist localization"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("StreetStampsWatch/zh-Hans.lproj/InfoPlist.strings").path
            ),
            "Missing watch Simplified Chinese InfoPlist localization"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("TrackingWidge/StreetStampsWidgets/en.lproj/InfoPlist.strings").path
            ),
            "Missing widget English InfoPlist localization"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("TrackingWidge/StreetStampsWidgets/zh-Hans.lproj/InfoPlist.strings").path
            ),
            "Missing widget Simplified Chinese InfoPlist localization"
        )
    }

    func test_settingsGuestCardUsesLocalizedCopyKeys() {
        let card = SettingsAccountPresentation.card(
            isLoggedIn: false,
            displayName: "Explorer",
            exclusiveID: "",
            email: ""
        )

        XCTAssertEqual(card.title, L10n.t("settings_sign_in_title"))
        XCTAssertEqual(card.subtitle, L10n.t("settings_sign_in_subtitle"))
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadStringsFile(at url: URL) throws -> [String: String] {
        let dictionary = NSDictionary(contentsOf: url) as? [String: String]
        return try XCTUnwrap(dictionary, "Unable to parse strings file at \(url.path)")
    }
}
