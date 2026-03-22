import XCTest
@testable import StreetStamps

final class JourneyCloudMigrationServiceSafetyTests: XCTestCase {
    func test_shouldMergeDownloadedProfile_requiresExactAccountMatch() {
        XCTAssertTrue(
            JourneyCloudMigrationService.shouldMergeDownloadedProfile(
                expectedAccountUserID: "u_owner_123",
                remoteProfileID: "u_owner_123"
            )
        )
    }

    func test_shouldMergeDownloadedProfile_rejectsMismatchedAccount() {
        XCTAssertFalse(
            JourneyCloudMigrationService.shouldMergeDownloadedProfile(
                expectedAccountUserID: "u_owner_123",
                remoteProfileID: "u_other_456"
            )
        )
    }

    func test_shouldMergeDownloadedProfile_rejectsGuestOrBlankAccount() {
        XCTAssertFalse(
            JourneyCloudMigrationService.shouldMergeDownloadedProfile(
                expectedAccountUserID: nil,
                remoteProfileID: "u_owner_123"
            )
        )
        XCTAssertFalse(
            JourneyCloudMigrationService.shouldMergeDownloadedProfile(
                expectedAccountUserID: "   ",
                remoteProfileID: "u_owner_123"
            )
        )
    }
}
