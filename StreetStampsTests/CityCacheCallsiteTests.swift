import XCTest
import SwiftUI
@testable import StreetStamps

final class CityCacheCallsiteTests: XCTestCase {
    func test_cityStampLibraryViewDefaultsToCachedLoadsWithoutAutoRebuild() {
        let view = CityStampLibraryView(showSidebar: .constant(false))
        let mirror = Mirror(reflecting: view)
        let autoRebuild = mirror.descendant("autoRebuildFromJourneyStore") as? Bool

        XCTAssertEqual(autoRebuild, false)
    }

    func test_mainViewSourceNoLongerTriggersFullRebuildOnStoreLoad() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("StreetStamps/MainView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertFalse(source.contains("cityCache.rebuildFromJourneyStore()"))
    }
}
