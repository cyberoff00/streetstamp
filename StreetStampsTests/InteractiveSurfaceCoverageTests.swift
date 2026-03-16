import XCTest
@testable import StreetStamps

final class InteractiveSurfaceCoverageTests: XCTestCase {
    func test_sharedTapTargetModifierExists() {
        XCTAssertEqual(AppFullSurfaceTapTargetShape.rectangle.debugName, "rectangle")
        XCTAssertEqual(AppFullSurfaceTapTargetShape.capsule.debugName, "capsule")
        XCTAssertEqual(AppFullSurfaceTapTargetShape.circle.debugName, "circle")
        XCTAssertEqual(AppFullSurfaceTapTargetShape.roundedRect(24).debugName, "roundedRect")
    }

    func test_auditedHighTrafficFilesUseFullSurfaceTapTargetModifier() throws {
        let root = projectRoot().appendingPathComponent("StreetStamps", isDirectory: true)
        let auditedFiles = [
            "AuthEntryView.swift",
            "MainView.swift",
            "MapView.swift",
            "OnboardingCoachCard.swift",
            "ProfileView.swift",
            "SettingsView.swift",
            "SidebarNavigation.swift",
            "EquipmentView.swift",
            "FriendsHubView.swift",
            "AccountCenterView.swift",
            "FirstProfileSetupView.swift",
            "CollectionTabView.swift",
            "SharedJourneySheets.swift",
            "SofaProfileSceneView.swift",
            "AppTopHeader.swift",
            "CityStampLibraryView.swift",
            "CityDeepView.swift",
            "ActivityRecordView.swift",
            "JourneyMemoryNew.swift",
            "MyJourneysView.swift",
            "SharingCard.swift"
        ]

        for file in auditedFiles {
            let url = root.appendingPathComponent(file)
            let contents = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(
                contents.contains("appFullSurfaceTapTarget("),
                "Expected \(file) to adopt appFullSurfaceTapTarget for audited hit-target coverage"
            )
        }
    }

    func test_sharingCardHeaderExposesDiscardAsDirectAction() throws {
        let url = projectRoot()
            .appendingPathComponent("StreetStamps", isDirectory: true)
            .appendingPathComponent("SharingCard.swift")
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(
            contents.contains("Button(role: .destructive) {") && contents.contains("showDiscardConfirm = true"),
            "Expected SharingCard header to expose discard as a direct destructive action"
        )
        XCTAssertFalse(
            contents.contains("Menu {\n                    Button(role: .destructive) {\n                        showDiscardConfirm = true"),
            "Expected SharingCard discard action to no longer live inside an ellipsis menu"
        )
    }
}
