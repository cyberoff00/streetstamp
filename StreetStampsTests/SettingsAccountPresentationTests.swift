import XCTest
@testable import StreetStamps

final class SettingsAccountPresentationTests: XCTestCase {
    func test_guestCard_usesFigmaLoginCopyAndChevron() {
        let card = SettingsAccountPresentation.card(
            isLoggedIn: false,
            displayName: "Explorer",
            exclusiveID: "",
            email: ""
        )

        XCTAssertEqual(card.style, .guest)
        XCTAssertEqual(card.title, "登录 Worldo")
        XCTAssertEqual(card.subtitle, "同步旅行数据，解锁好友功能")
        XCTAssertTrue(card.showsChevron)
        XCTAssertEqual(card.detailLines, [])
    }

    func test_loggedInCard_showsNameExclusiveIDEmailAndChevronForAccountCenterEntry() {
        let card = SettingsAccountPresentation.card(
            isLoggedIn: true,
            displayName: "Explorer",
            exclusiveID: "WO_2024_001",
            email: "traveler@worldo.app"
        )

        XCTAssertEqual(card.style, .member)
        XCTAssertEqual(card.title, "Explorer")
        XCTAssertEqual(card.subtitle, "ID: WO_2024_001")
        XCTAssertEqual(card.detailLines, ["traveler@worldo.app"])
        XCTAssertTrue(card.showsChevron)
    }

    func test_loggedOutAccountActions_haveNoExtraRowsBecauseCardHandlesLogin() {
        XCTAssertEqual(
            SettingsAccountPresentation.accountActionTitles(isLoggedIn: false),
            []
        )
    }

    func test_loggedInAccountActions_areEmptyBecauseMemberActionsMovedToAccountCenter() {
        XCTAssertEqual(
            SettingsAccountPresentation.accountActionTitles(isLoggedIn: true),
            []
        )
    }

    func test_serviceSectionTitles_areSeparatedFromAccountSection() {
        XCTAssertEqual(
            SettingsAccountPresentation.serviceActionTitles,
            ["PRIVATE DATA TRANSFER", "SUBSCRIPTION"]
        )
    }
}
