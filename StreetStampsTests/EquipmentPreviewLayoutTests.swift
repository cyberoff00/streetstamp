import XCTest
import CoreGraphics
@testable import StreetStamps

final class EquipmentPreviewLayoutTests: XCTestCase {
    func test_tallCanvasUsesAspectFillAndCenterAlignment() {
        let rect = EquipmentPreviewLayout.imageRect(
            imageSize: CGSize(width: 128, height: 160),
            in: CGSize(width: 82, height: 82)
        )

        XCTAssertEqual(rect.width, 82, accuracy: 0.001)
        XCTAssertEqual(rect.height, 102.5, accuracy: 0.001)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 41, accuracy: 0.001)
    }

    func test_squareCanvasStillFitsExactlyInsidePreview() {
        let rect = EquipmentPreviewLayout.imageRect(
            imageSize: CGSize(width: 128, height: 128),
            in: CGSize(width: 82, height: 82)
        )

        XCTAssertEqual(rect.width, 82, accuracy: 0.001)
        XCTAssertEqual(rect.height, 82, accuracy: 0.001)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
    }

    func test_equipmentPreviewSupportsLargerGridPreviewSize() {
        let rect = EquipmentPreviewLayout.imageRect(
            imageSize: CGSize(width: 128, height: 160),
            in: CGSize(width: 90, height: 90)
        )

        XCTAssertEqual(rect.width, 90, accuracy: 0.001)
        XCTAssertEqual(rect.height, 112.5, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 45, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 45, accuracy: 0.001)
    }

    func test_avatarAssetLayoutUsesBottomAlignmentForTallerCanvas() {
        let rect = AvatarAssetLayout.imageRect(
            imageSize: CGSize(width: 128, height: 160),
            in: CGSize(width: 176, height: 176)
        )

        XCTAssertEqual(rect.width, 176, accuracy: 0.001)
        XCTAssertEqual(rect.height, 220, accuracy: 0.001)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 176, accuracy: 0.001)
    }

    func test_equipmentPreviewSupportsLargerTryOnPreviewSize() {
        let rect = EquipmentPreviewLayout.imageRect(
            imageSize: CGSize(width: 128, height: 160),
            in: CGSize(width: 64, height: 64)
        )

        XCTAssertEqual(rect.width, 64, accuracy: 0.001)
        XCTAssertEqual(rect.height, 80, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 32, accuracy: 0.001)
        XCTAssertEqual(rect.midY, 32, accuracy: 0.001)
    }
}
