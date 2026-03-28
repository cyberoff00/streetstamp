import XCTest
@testable import StreetStamps

final class FilmFilterEngineTests: XCTestCase {
    func test_sakuraCCDSoftPreset_usesWarmAiryBaselineValues() {
        let tuning = FilmFilterEngine.CaptureLookTuning.sakuraCCDSoft

        XCTAssertEqual(tuning.tonePoint0.y, 0.06, accuracy: 0.0001)
        XCTAssertEqual(tuning.tonePoint2.y, 0.53, accuracy: 0.0001)
        XCTAssertEqual(tuning.tonePoint4.y, 0.96, accuracy: 0.0001)
        XCTAssertEqual(tuning.targetNeutral.x, 6350, accuracy: 0.001)
        XCTAssertEqual(tuning.targetNeutral.y, -6, accuracy: 0.001)
        XCTAssertEqual(tuning.saturation, 0.94, accuracy: 0.0001)
        XCTAssertEqual(tuning.brightness, 0.006, accuracy: 0.0001)
        XCTAssertEqual(tuning.contrast, 0.97, accuracy: 0.0001)
        XCTAssertEqual(tuning.bloomRadius, 8.0, accuracy: 0.0001)
        XCTAssertEqual(tuning.bloomIntensity, 0.085, accuracy: 0.0001)
        XCTAssertEqual(tuning.grainStrength, 0.010, accuracy: 0.0001)
        XCTAssertEqual(tuning.vignetteIntensity, 0.12, accuracy: 0.0001)
    }

    func test_vignetteRadius_scalesWithImageExtent() {
        let extent = CGRect(x: 0, y: 0, width: 4032, height: 3024)

        let radius = FilmFilterEngine.vignetteRadius(for: extent)

        XCTAssertEqual(radius, 2479.68, accuracy: 0.001)
    }
}
