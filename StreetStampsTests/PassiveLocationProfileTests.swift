import XCTest
@testable import StreetStamps

final class PassiveLocationProfileTests: XCTestCase {
    func test_highPrecisionPassiveUses35MeterDistanceFilter() {
        let profile = PassiveLocationProfile.profile(for: .highPrecision)

        XCTAssertEqual(profile.distanceFilter, 35, accuracy: 0.001)
    }

    func test_lowPrecisionPassiveUses70MeterDistanceFilter() {
        let profile = PassiveLocationProfile.profile(for: .lowPrecision)

        XCTAssertEqual(profile.distanceFilter, 70, accuracy: 0.001)
    }

    func test_dailyJourneyBaseProfileUsesNearestTenMetersAnd15MeterFilter() {
        let source = try! String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/SystemLocationSource.swift"
        )

        XCTAssertTrue(source.contains("manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters"))
        XCTAssertTrue(source.contains("manager.distanceFilter = 15"))
    }
}
