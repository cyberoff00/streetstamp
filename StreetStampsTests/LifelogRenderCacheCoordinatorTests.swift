import XCTest
@testable import StreetStamps

final class LifelogRenderCacheCoordinatorTests: XCTestCase {
    func test_recentWarmupDays_returnsTodayThenPreviousSixDays() {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let days = LifelogRenderWarmupPlanner.recentDays(anchorDay: anchor, count: 7)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, Calendar.current.startOfDay(for: anchor))
        XCTAssertEqual(
            days.last,
            Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: anchor))
        )
    }

    func test_viewportBucket_roundsNearbyRegionsToSameBucket() {
        let a = TrackTileViewport(minLat: 37.70, maxLat: 37.80, minLon: -122.50, maxLon: -122.30)
        let b = TrackTileViewport(minLat: 37.70002, maxLat: 37.80002, minLon: -122.50002, maxLon: -122.30002)

        XCTAssertEqual(
            LifelogViewportBucket.bucket(for: a),
            LifelogViewportBucket.bucket(for: b)
        )
    }
}
