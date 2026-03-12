import XCTest
@testable import StreetStamps

final class LocalizationCoverageTests: XCTestCase {
    func test_lifelogTitleUsesUpdatedEnglishAndSimplifiedChineseCopy() throws {
        let appRoot = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let english = try loadStringsFile(at: appRoot.appendingPathComponent("en.lproj/Localizable.strings"))
        let simplifiedChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))

        XCTAssertEqual(english["tab_lifelog"], "LIFELOG")
        XCTAssertEqual(english["lifelog_title"], "LIFELOG")
        XCTAssertEqual(simplifiedChinese["tab_lifelog"], "足迹")
        XCTAssertEqual(simplifiedChinese["lifelog_title"], "足迹")
    }

    func test_friendSofaSceneCopyUsesUpdatedEnglishAndSimplifiedChineseStrings() throws {
        let appRoot = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let english = try loadStringsFile(at: appRoot.appendingPathComponent("en.lproj/Localizable.strings"))
        let simplifiedChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))

        XCTAssertEqual(english["friends_welcome"], "Welcome!")
        XCTAssertEqual(english["friends_postcard_prompt"], "bring you a postcard")
        XCTAssertEqual(simplifiedChinese["friends_welcome"], "欢迎！")
        XCTAssertEqual(simplifiedChinese["friends_postcard_prompt"], "送你一张明信片")
    }

    func test_profileVisitCopyUsesUpdatedEnglishAndSimplifiedChineseStrings() throws {
        let appRoot = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let english = try loadStringsFile(at: appRoot.appendingPathComponent("en.lproj/Localizable.strings"))
        let simplifiedChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))

        XCTAssertEqual(english["social_notice_stomp"], "Visitor")
        XCTAssertEqual(english["notification_profile_stomp_format"], "%@ sat on your sofa")
        XCTAssertEqual(english["friend_profile_stomp_success_format"], "You sat on %@'s sofa")
        XCTAssertEqual(simplifiedChinese["social_notice_stomp"], "有人到访")
        XCTAssertEqual(simplifiedChinese["notification_profile_stomp_format"], "%@在你的沙发上坐了一坐")
        XCTAssertEqual(simplifiedChinese["friend_profile_stomp_success_format"], "你在 %@ 的沙发上坐了一坐")
    }

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
            "friends_welcome",
            "friends_postcard_prompt",
            "friends_joined_format",
            "settings_coming_soon_title",
            "settings_notifications_title",
            "settings_edit_name_title",
            "settings_private_transfer_title",
            "settings_private_transfer_intro",
            "settings_transfer_old_device",
            "settings_transfer_new_device",
            "settings_transfer_generate_qr",
            "settings_transfer_scan_import",
            "settings_transfer_scan_hint",
            "settings_transfer_same_wifi_hint",
            "settings_import_failed_title",
            "settings_live_activity_title",
            "settings_live_activity_desc",
            "settings_check_updates_title",
            "settings_check_updates_placeholder",
            "settings_about_us_title",
            "settings_about_us_placeholder",
            "settings_privacy_policy_title",
            "settings_privacy_policy_placeholder",
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
            "equipment_hat",
            "equipment_glass",
            "postcard_quota_friend_limit_reached",
            "postcard_quota_city_limit_reached",
            "postcard_sync_error_format",
            "details_unavailable_title",
            "details_unavailable_message",
            "verify_your_email",
            "auth_remembered_password",
            "resend_verification_email",
            "i_verified_my_email",
            "verification_email_sent",
            "email_still_unverified",
            "splash_tagline",
            "intro_skip",
            "postcard_greetings_from",
            "postcard_brand_street",
            "postcard_brand_stamps",
            "main_unlock_new_journey",
            "discard_changes_title",
            "long_stationary_reminder_title",
            "long_stationary_reminder_body",
            "postcard_received_title_format",
            "postcard_received_title_fallback",
            "postcard_received_body_format",
            "notification_journey_like_format",
            "notification_profile_stomp_format",
            "notification_friend_request_format",
            "notification_friend_request_accepted_format",
            "notification_friend_request_fallback",
            "social_notice_friend_request",
            "social_notice_friend_update",
            "friend_profile_cta_idle",
            "friend_profile_cta_loading",
            "friend_profile_cta_done",
            "friend_profile_stomp_success_format",
            "friend_profile_stomp_failed_format",
            "city_level_picker_title",
            "city_level_picker_cancel",
            "city_level_locality",
            "city_level_sub_admin",
            "city_level_admin",
            "city_level_island",
            "city_level_country",
            "city_level_region",
            "city_level_confirm_title",
            "city_level_confirm_apply",
            "city_level_confirm_upgrade_message",
            "city_level_confirm_future_default_message",
            "city_level_downgrade_blocked_title",
            "city_level_downgrade_blocked_message_format",
            "city_deep_memories_toggle_on",
            "city_deep_memories_toggle_off",
            "city_deep_memories_toggle_show_accessibility",
            "city_deep_memories_toggle_hide_accessibility",
            "lifelog_mood_option_sad",
            "lifelog_mood_option_notbad",
            "lifelog_mood_option_happy",
            "profile_summary_stats_format",
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

    func test_checkUpdatesTitleDoesNotForceLineBreakInChineseLocalizations() throws {
        let appRoot = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let simplifiedChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))
        let traditionalChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hant.lproj/Localizable.strings"))

        XCTAssertEqual(simplifiedChinese["settings_check_updates_title"], "检查更新")
        XCTAssertEqual(traditionalChinese["settings_check_updates_title"], "檢查更新")
        XCTAssertFalse(simplifiedChinese["settings_check_updates_title"]?.contains("\n") ?? true)
        XCTAssertFalse(traditionalChinese["settings_check_updates_title"]?.contains("\n") ?? true)
    }

    func test_appNameUsesWorldoAcrossEnglishAndSimplifiedChinese() throws {
        let appRoot = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let english = try loadStringsFile(at: appRoot.appendingPathComponent("en.lproj/Localizable.strings"))
        let simplifiedChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))

        XCTAssertEqual(english["app_name"], "Worldo")
        XCTAssertEqual(simplifiedChinese["app_name"], "Worldo")
    }

    func test_introSlidesExposeLocalizedScreenshotOnboardingCopy() throws {
        let appRoot = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let english = try loadStringsFile(at: appRoot.appendingPathComponent("en.lproj/Localizable.strings"))
        let simplifiedChinese = try loadStringsFile(at: appRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))

        let requiredKeys = [
            "intro_next",
            "intro_get_started",
            "intro_slide_1_title",
            "intro_slide_1_subtitle",
            "intro_slide_2_title",
            "intro_slide_2_subtitle",
            "intro_slide_3_title",
            "intro_slide_3_subtitle",
            "intro_slide_4_title",
            "intro_slide_4_subtitle"
        ]

        for key in requiredKeys {
            XCTAssertNotNil(english[key], "Missing English localization for key \(key)")
            XCTAssertNotNil(simplifiedChinese[key], "Missing Simplified Chinese localization for key \(key)")
        }

        XCTAssertEqual(simplifiedChinese["intro_slide_1_title"], "开启探索")
        XCTAssertEqual(simplifiedChinese["intro_slide_4_title"], "好友与更多探索")
    }

    func test_upperReturnsUppercasedLocalizedValue() {
        let english = Locale(identifier: "en")

        XCTAssertEqual(L10n.upper("profile_invite_friends", locale: english), "INVITE FRIENDS")
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
