import CoreLocation
import XCTest
@testable import StreetStamps

final class CityBoundaryServiceTests: XCTestCase {
    func test_boundaryPolygon_timesOutAndClearsInflightSearch() async {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var value = 0

            func increment() {
                lock.lock()
                value += 1
                lock.unlock()
            }
        }

        let counter = Counter()
        let service = CityBoundaryService(
            searchTimeoutNanoseconds: 50_000_000,
            searchExecutor: { _, _ in
                counter.increment()
                SearchCancellationToken {}
            }
        )

        async let first: [CLLocationCoordinate2D]? = service.boundaryPolygon(
            cityKey: "Hangzhou|CN",
            cityName: "Hangzhou",
            countryISO2: "CN",
            anchor: nil
        )
        async let second: [CLLocationCoordinate2D]? = service.boundaryPolygon(
            cityKey: "Hangzhou|CN",
            cityName: "Hangzhou",
            countryISO2: "CN",
            anchor: nil
        )

        let firstResult = await first
        let secondResult = await second

        XCTAssertNil(firstResult)
        XCTAssertNil(secondResult)

        let thirdResult = await service.boundaryPolygon(
            cityKey: "Hangzhou|CN",
            cityName: "Hangzhou",
            countryISO2: "CN",
            anchor: nil
        )

        XCTAssertNil(thirdResult)
        XCTAssertEqual(counter.value, 2)
    }
}
