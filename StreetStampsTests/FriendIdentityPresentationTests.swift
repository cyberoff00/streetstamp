import XCTest
@testable import StreetStamps

final class FriendIdentityPresentationTests: XCTestCase {
    func test_prefersHumanDisplayName() {
        XCTAssertEqual(
            FriendIdentityPresentation.displayName(
                displayName: "Ariel Sun",
                exclusiveID: "ariel.sun",
                userID: "u_internal_1",
                localize: { key in key == "unknown" ? "Unknown" : key }
            ),
            "Ariel Sun"
        )
    }

    func test_fallsBackToExclusiveIDWhenDisplayNameLooksInternal() {
        XCTAssertEqual(
            FriendIdentityPresentation.displayName(
                displayName: "u_e872904bd056bc8ff430e619",
                exclusiveID: "ariel.sun",
                userID: "u_internal_1",
                localize: { key in key == "unknown" ? "Unknown" : key }
            ),
            "ariel.sun"
        )
    }

    func test_hidesInternalIdentifiersWhenNoHumanNameExists() {
        XCTAssertEqual(
            FriendIdentityPresentation.displayName(
                displayName: "account_12345",
                exclusiveID: "u_legacy_handle",
                userID: "u_internal_1",
                localize: { key in key == "unknown" ? "Unknown" : key }
            ),
            "Unknown"
        )
    }
}
