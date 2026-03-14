import XCTest
@testable import StreetStamps

final class TabRenderPolicyTests: XCTestCase {
    func test_shouldRender_selectedTab_alwaysTrue() {
        let loaded: Set<NavigationTab> = [.start]
        XCTAssertTrue(TabRenderPolicy.shouldRender(tab: .lifelog, selectedTab: .lifelog, loadedTabs: loaded))
        XCTAssertTrue(TabRenderPolicy.shouldRender(tab: .friends, selectedTab: .friends, loadedTabs: loaded))
    }

    func test_shouldRender_lifelog_notSelected_notRenderedEvenIfLoaded() {
        let loaded: Set<NavigationTab> = [.start, .lifelog]
        XCTAssertFalse(TabRenderPolicy.shouldRender(tab: .lifelog, selectedTab: .start, loadedTabs: loaded))
    }

    func test_shouldRender_otherTabs_notSelected_stillRenderedWhenLoaded() {
        let loaded: Set<NavigationTab> = [.start, .friends, .cities, .profile]
        XCTAssertTrue(TabRenderPolicy.shouldRender(tab: .friends, selectedTab: .start, loadedTabs: loaded))
        XCTAssertTrue(TabRenderPolicy.shouldRender(tab: .cities, selectedTab: .start, loadedTabs: loaded))
        XCTAssertTrue(TabRenderPolicy.shouldRender(tab: .profile, selectedTab: .start, loadedTabs: loaded))
    }
}
