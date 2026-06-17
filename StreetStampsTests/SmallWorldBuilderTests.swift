//
//  SmallWorldBuilderTests.swift
//  StreetStampsTests
//
//  Covers the pure retrospective logic behind 「你的小世界」.
//

import XCTest
import CoreLocation
@testable import StreetStamps

final class SmallWorldBuilderTests: XCTestCase {

    private let fmt = SmallWorldBuilder.dayKeyFormatter()

    /// Day key `n` days before `ref`.
    private func dayKey(daysBefore n: Int, from ref: Date) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -n, to: ref)!
        return fmt.string(from: d)
    }

    private func point(lat: Double, lon: Double, day: String) -> SmallWorldPoint {
        SmallWorldPoint(lat: lat, lon: lon, cellID: TrackPointCellID.make(lat: lat, lon: lon), dayKey: day)
    }

    // MARK: - Empty / insufficient data

    func testEmptyPointsReturnsEmptySummary() {
        let s = SmallWorldBuilder.build(points: [], moodByDay: [:], referenceDate: Date())
        XCTAssertFalse(s.hasEnoughData)
        XCTAssertNil(s.anchor)
        XCTAssertTrue(s.topPlaces.isEmpty)
        XCTAssertNil(s.reunion)
    }

    func testTooFewActiveDaysIsNotEnoughData() {
        let ref = Date()
        // 3 distinct days only — below minActiveDaysForInsight (5).
        var pts: [SmallWorldPoint] = []
        for d in 0..<3 {
            pts.append(point(lat: 31.23, lon: 121.47, day: dayKey(daysBefore: d, from: ref)))
        }
        let s = SmallWorldBuilder.build(points: pts, moodByDay: [:], referenceDate: ref)
        XCTAssertFalse(s.hasEnoughData)
        XCTAssertEqual(s.totalActiveDays, 3)
        XCTAssertEqual(s.distinctPlaces, 1)
        XCTAssertTrue(s.topPlaces.isEmpty, "No claims about places without enough days")
    }

    // MARK: - Anchor & ranking

    func testAnchorIsMostReturnedCellAndPlacesRankedByDistinctDays() {
        let ref = Date()
        var pts: [SmallWorldPoint] = []
        // "Home": visited on 6 distinct days.
        for d in 0..<6 {
            pts.append(point(lat: 31.2300, lon: 121.4700, day: dayKey(daysBefore: d, from: ref)))
        }
        // "Office": visited on 4 distinct days (~2km away).
        for d in 0..<4 {
            pts.append(point(lat: 31.2500, lon: 121.4700, day: dayKey(daysBefore: d, from: ref)))
        }
        // "Cafe": 1 day.
        pts.append(point(lat: 31.2310, lon: 121.4900, day: dayKey(daysBefore: 10, from: ref)))

        let s = SmallWorldBuilder.build(points: pts, moodByDay: [:], referenceDate: ref)
        XCTAssertTrue(s.hasEnoughData)
        XCTAssertEqual(s.distinctPlaces, 3)
        XCTAssertEqual(s.anchor?.latitude ?? 0, 31.2300, accuracy: 0.001)

        XCTAssertEqual(s.topPlaces.count, 3)
        XCTAssertEqual(s.topPlaces[0].visitDays, 6)
        XCTAssertEqual(s.topPlaces[0].metersFromAnchor, 0, accuracy: 1)
        XCTAssertEqual(s.topPlaces[1].visitDays, 4)
        XCTAssertGreaterThan(s.topPlaces[1].metersFromAnchor, 1500)
        XCTAssertEqual(s.topPlaces[2].visitDays, 1)
    }

    // MARK: - Radius

    func testRadiusExcludesFarFlungTrips() {
        let ref = Date()
        var pts: [SmallWorldPoint] = []
        // 8 days of life clustered around home.
        for d in 0..<8 {
            pts.append(point(lat: 31.2300, lon: 121.4700, day: dayKey(daysBefore: d, from: ref)))
        }
        // Two faraway trip points (~hundreds of km) on two extra days.
        pts.append(point(lat: 39.9042, lon: 116.4074, day: dayKey(daysBefore: 100, from: ref))) // Beijing
        pts.append(point(lat: 22.3193, lon: 114.1694, day: dayKey(daysBefore: 200, from: ref))) // Hong Kong

        let s = SmallWorldBuilder.build(points: pts, moodByDay: [:], referenceDate: ref, coveragePercent: 80)
        XCTAssertTrue(s.hasEnoughData)
        // 80% of the 10 samples are at home → radius should be tiny, not span to Beijing.
        XCTAssertLessThan(s.radiusMeters, 50_000)
    }

    func testPercentileNearestRank() {
        let sorted = [0.0, 10, 20, 30, 40, 50, 60, 70, 80, 90] // 10 values
        XCTAssertEqual(SmallWorldBuilder.percentile(sorted: sorted, percent: 80), 70, accuracy: 0.0001)
        XCTAssertEqual(SmallWorldBuilder.percentile(sorted: sorted, percent: 100), 90, accuracy: 0.0001)
        XCTAssertEqual(SmallWorldBuilder.percentile(sorted: [], percent: 80), 0, accuracy: 0.0001)
        XCTAssertEqual(SmallWorldBuilder.percentile(sorted: [42], percent: 80), 42, accuracy: 0.0001)
    }

    // MARK: - 重逢

    func testReunionPrefersOneYearAgoWithMood() {
        let ref = Date()
        var pts: [SmallWorldPoint] = []
        for d in 0..<6 {
            pts.append(point(lat: 31.23, lon: 121.47, day: dayKey(daysBefore: d, from: ref)))
        }
        // A day ~1 year ago.
        let yearAgoKey = dayKey(daysBefore: 365, from: ref)
        pts.append(point(lat: 31.24, lon: 121.48, day: yearAgoKey))
        pts.append(point(lat: 31.24, lon: 121.48, day: yearAgoKey))

        let s = SmallWorldBuilder.build(points: pts, moodByDay: [yearAgoKey: "happy"], referenceDate: ref)
        XCTAssertNotNil(s.reunion)
        XCTAssertEqual(s.reunion?.mood, "happy")
        XCTAssertEqual(s.reunion?.pointCount, 2)
        let resolved = fmt.string(from: s.reunion!.date)
        XCTAssertEqual(resolved, yearAgoKey)
    }

    func testNoReunionWhenEverythingIsRecent() {
        let ref = Date()
        var pts: [SmallWorldPoint] = []
        // All within the last week — nothing old enough to look back on.
        for d in 0..<6 {
            pts.append(point(lat: 31.23, lon: 121.47, day: dayKey(daysBefore: d, from: ref)))
        }
        let s = SmallWorldBuilder.build(points: pts, moodByDay: [:], referenceDate: ref)
        XCTAssertNil(s.reunion)
    }
}
