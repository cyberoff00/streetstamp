import XCTest
@testable import StreetStamps

final class CurrentUserRepairPolicyTests: XCTestCase {
    func test_classifyJourneySources_allowsOnlyCurrentGuestAndCurrentAccount() {
        let policy = CurrentUserRepairPolicy(
            activeLocalProfileID: "local_guest123",
            currentGuestScopedUserID: "guest_guest123",
            currentAccountUserID: "abc"
        )

        XCTAssertTrue(policy.allows(.deviceGuest(guestID: "guest123")))
        XCTAssertTrue(policy.allows(.accountCache(accountUserID: "abc")))
        XCTAssertFalse(policy.allows(.deviceGuest(guestID: "other")))
        XCTAssertFalse(policy.allows(.accountCache(accountUserID: "other-account")))
        XCTAssertFalse(policy.allows(.unknown))
    }
}
