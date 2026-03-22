import XCTest
@testable import StreetStamps

final class SurfaceRefreshReminderPolicyTests: XCTestCase {
    func test_foregroundReturn_requiresThirtySecondBackgroundGap() {
        let lastBackgroundAt = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertFalse(
            SurfaceRefreshReminderPolicy.shouldRunForegroundFreshnessCheck(
                lastBackgroundAt: lastBackgroundAt,
                now: lastBackgroundAt.addingTimeInterval(29.9)
            )
        )
        XCTAssertTrue(
            SurfaceRefreshReminderPolicy.shouldRunForegroundFreshnessCheck(
                lastBackgroundAt: lastBackgroundAt,
                now: lastBackgroundAt.addingTimeInterval(30.0)
            )
        )
    }

    func test_lightweightCheckCooldown_requiresFiveMinutesBetweenChecks() {
        let lastCheckAt = Date(timeIntervalSinceReferenceDate: 2_000)

        XCTAssertFalse(
            SurfaceRefreshReminderPolicy.shouldRunLightweightCheck(
                lastCheckedAt: lastCheckAt,
                now: lastCheckAt.addingTimeInterval(299.9)
            )
        )
        XCTAssertTrue(
            SurfaceRefreshReminderPolicy.shouldRunLightweightCheck(
                lastCheckedAt: lastCheckAt,
                now: lastCheckAt.addingTimeInterval(300.0)
            )
        )
    }

    func test_promptCooldown_requiresNinetySecondsBetweenPrompts() {
        let lastPromptAt = Date(timeIntervalSinceReferenceDate: 3_000)

        XCTAssertFalse(
            SurfaceRefreshReminderPolicy.shouldShowPrompt(
                lastPromptAt: lastPromptAt,
                now: lastPromptAt.addingTimeInterval(89.9)
            )
        )
        XCTAssertTrue(
            SurfaceRefreshReminderPolicy.shouldShowPrompt(
                lastPromptAt: lastPromptAt,
                now: lastPromptAt.addingTimeInterval(90.0)
            )
        )
    }

    func test_firstCheckAndFirstPromptAreAlwaysAllowed() {
        let now = Date(timeIntervalSinceReferenceDate: 4_000)

        XCTAssertTrue(
            SurfaceRefreshReminderPolicy.shouldRunLightweightCheck(
                lastCheckedAt: nil,
                now: now
            )
        )
        XCTAssertTrue(
            SurfaceRefreshReminderPolicy.shouldShowPrompt(
                lastPromptAt: nil,
                now: now
            )
        )
    }
}
