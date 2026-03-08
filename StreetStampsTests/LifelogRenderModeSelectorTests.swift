import XCTest
import MapKit
@testable import StreetStamps

final class LifelogRenderModeSelectorTests: XCTestCase {
    func test_isNearMode_whenViewportWithin2km_returnsTrue() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        )

        let spanMeters = LifelogRenderModeSelector.viewportMaxSpanMeters(for: region)

        XCTAssertLessThanOrEqual(spanMeters, 2_000)
        XCTAssertTrue(LifelogRenderModeSelector.isNearMode(viewportMaxSpanMeters: spanMeters))
    }

    func test_isNearMode_whenViewportOver2km_returnsFalse() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )

        let spanMeters = LifelogRenderModeSelector.viewportMaxSpanMeters(for: region)

        XCTAssertGreaterThan(spanMeters, 2_000)
        XCTAssertFalse(LifelogRenderModeSelector.isNearMode(viewportMaxSpanMeters: spanMeters))
    }

    func test_footprintStepMeters_is50Meters() {
        XCTAssertEqual(LifelogRenderModeSelector.footprintStepMeters, 50)
    }

    func test_mapModePillPresentation_usesLighterSportSymbolAndSoftChrome() {
        let presentation = TrackingMode.sport.mapPillPresentation

        XCTAssertEqual(presentation.symbolName, "figure.run")
        XCTAssertEqual(presentation.iconFontSize, 12)
        XCTAssertEqual(presentation.horizontalSpacing, 7)
        XCTAssertEqual(presentation.foregroundOpacity, 0.82)
        XCTAssertEqual(presentation.backgroundOpacity, 0.78)
        XCTAssertEqual(presentation.borderOpacity, 0.18)
    }

    func test_mapModePillPresentation_usesLighterDailySymbolAndSoftChrome() {
        let presentation = TrackingMode.daily.mapPillPresentation

        XCTAssertEqual(presentation.symbolName, "figure.walk.motion")
        XCTAssertEqual(presentation.iconFontSize, 12)
        XCTAssertEqual(presentation.horizontalSpacing, 7)
        XCTAssertEqual(presentation.foregroundOpacity, 0.82)
        XCTAssertEqual(presentation.backgroundOpacity, 0.78)
        XCTAssertEqual(presentation.borderOpacity, 0.18)
    }
}
