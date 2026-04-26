import XCTest
import CoreLocation
@testable import StreetStamps

final class PassiveLocationProfileTests: XCTestCase {
    func test_defaultDailyTrackingPrecisionIsLow() {
        XCTAssertEqual(DailyTrackingPrecision.defaultPrecision, .lowPrecision)
    }

    func test_dailyTrackingPrecisionRoundTripsViaRawValue() {
        for p in DailyTrackingPrecision.allCases {
            XCTAssertEqual(DailyTrackingPrecision(rawValue: p.rawValue), p)
        }
    }

    func test_movingProfileIsMorePreciseThanStationary() {
        let moving = PassiveLocationProfile.profile(for: .moving)
        let stationary = PassiveLocationProfile.profile(for: .stationary)

        XCTAssertLessThan(moving.desiredAccuracy, stationary.desiredAccuracy)
        XCTAssertLessThan(moving.distanceFilter, stationary.distanceFilter)
    }

    func test_stationaryProfileUsesHundredMetersAccuracy() {
        let stationary = PassiveLocationProfile.profile(for: .stationary)

        XCTAssertEqual(stationary.desiredAccuracy, kCLLocationAccuracyHundredMeters)
    }

    func test_passiveLifelogUsesPausesAutomatically() {
        let source = try! String(
            contentsOfFile: "/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/SystemLocationSource.swift"
        )

        XCTAssertTrue(source.contains("func startPassiveLifelog()"))
        XCTAssertTrue(source.contains("manager.pausesLocationUpdatesAutomatically = true"))
    }
}
