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

    func test_equipmentCategoryRowIncludesHorizontalScrollAffordance() throws {
        let url = projectRoot()
            .appendingPathComponent("StreetStamps", isDirectory: true)
            .appendingPathComponent("EquipmentView.swift")
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(
            contents.contains("equipmentCategoryTrailingPeekWidth"),
            "Expected EquipmentView category row to expose a named trailing peek affordance"
        )
        XCTAssertTrue(
            contents.contains("categoryScrollHintOverlay"),
            "Expected EquipmentView category row to expose a right-edge scroll hint overlay"
        )
    }

    func test_equipmentViewKeepsSwipeBackEnablerWhenNavigationBarIsHidden() throws {
        let url = projectRoot()
            .appendingPathComponent("StreetStamps", isDirectory: true)
            .appendingPathComponent("EquipmentView.swift")
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(
            contents.contains(".toolbar(.hidden, for: .navigationBar)"),
            "Expected EquipmentView to continue hiding the stock navigation bar for its custom header"
        )
        XCTAssertTrue(
            contents.contains(".background(SwipeBackEnabler())"),
            "Expected EquipmentView to re-enable the interactive swipe-back gesture after hiding the navigation bar"
        )
    }

    func test_equipmentCategoryIconsUseUnifiedDisplaySize() throws {
        let url = projectRoot()
            .appendingPathComponent("StreetStamps", isDirectory: true)
            .appendingPathComponent("EquipmentView.swift")
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(
            contents.contains(".frame(width: 24, height: 24)"),
            "Expected EquipmentView asset-backed category icons to keep a unified 24pt display size"
        )
        XCTAssertFalse(
            contents.contains("case \"suit\":\n            return 28"),
            "Expected EquipmentView to avoid a suit-only icon size override once the asset matches Figma"
        )
    }

    func test_equipmentPreviewUsesCornerTryOnControlsAndMintBackdrop() throws {
        let url = projectRoot()
            .appendingPathComponent("StreetStamps", isDirectory: true)
            .appendingPathComponent("EquipmentView.swift")
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(
            contents.contains("Color(red: 224.0 / 255.0, green: 241.0 / 255.0, blue: 237.0 / 255.0)"),
            "Expected EquipmentView preview card to use the shared mint backdrop"
        )
        XCTAssertFalse(
            contents.contains("tryOnRow\n"),
            "Expected EquipmentView to stop placing a standalone try-on row in the top stack"
        )
        XCTAssertTrue(
            contents.contains("tryOnCornerControl"),
            "Expected EquipmentView preview card to expose a compact corner try-on control"
        )
        XCTAssertTrue(
            contents.contains("#4CAF50"),
            "Expected EquipmentView hair color options to include a green swatch"
        )
    }
}
