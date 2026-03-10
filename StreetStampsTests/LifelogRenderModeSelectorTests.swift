import XCTest
import MapKit
@testable import StreetStamps

final class LifelogRenderModeSelectorTests: XCTestCase {
    func test_isNearMode_whenViewportAtDefaultSpan_returnsTrue() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )

        XCTAssertTrue(LifelogRenderModeSelector.isNearMode(region))
    }

    func test_isNearMode_whenViewportWiderThanDefaultSpan_returnsFalse() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.031, longitudeDelta: 0.03)
        )

        XCTAssertFalse(LifelogRenderModeSelector.isNearMode(region))
    }

    func test_footprintStepMeters_is50Meters() {
        XCTAssertEqual(LifelogRenderModeSelector.footprintStepMeters, 50)
    }

    func test_mapModePillPresentation_usesSportIconOnly() {
        let presentation = TrackingMode.sport.mapPillPresentation

        XCTAssertEqual(presentation.symbolName, "figure.run")
        XCTAssertEqual(presentation.iconFontSize, 12)
        XCTAssertEqual(presentation.foregroundOpacity, 0.82)
    }

    func test_mapModePillPresentation_usesDailyIconOnly() {
        let presentation = TrackingMode.daily.mapPillPresentation

        XCTAssertEqual(presentation.symbolName, "figure.walk.motion")
        XCTAssertEqual(presentation.iconFontSize, 12)
        XCTAssertEqual(presentation.foregroundOpacity, 0.82)
    }
}
