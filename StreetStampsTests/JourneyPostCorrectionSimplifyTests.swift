import XCTest
import CoreLocation
@testable import StreetStamps

/// Covers the iterative Douglas-Peucker simplification used by
/// `JourneyPostCorrection.simplifiedForDisplay`. The implementation was changed
/// from recursive to an explicit-stack iterative form so an all-day route of
/// tens of thousands of points can no longer overflow the thread stack during
/// finalize (which previously crashed the app mid-finalize and lost the journey).
final class JourneyPostCorrectionSimplifyTests: XCTestCase {

    /// step ≈ 33m at the equator — comfortably above daily mode's 1.5m dedup
    /// threshold, so points survive into the Douglas-Peucker stage.
    private let lonStep = 0.0003

    private func dailyRoute(coordinates: [CoordinateCodable]) -> JourneyRoute {
        var route = JourneyRoute()
        route.trackingMode = .daily
        route.coordinates = coordinates
        return route
    }

    func test_simplify_collinearLine_collapsesToEndpoints() {
        // A straight line: every interior point has ~0 perpendicular distance,
        // so DP must drop all of them and keep only the two endpoints.
        let coords = (0..<200).map { CoordinateCodable(lat: 0, lon: Double($0) * lonStep) }
        let route = dailyRoute(coordinates: coords)

        let simplified = JourneyPostCorrection.simplifiedForDisplay(for: route)

        XCTAssertEqual(simplified.count, 2, "Collinear points should collapse to endpoints")
        XCTAssertEqual(simplified.first?.lon ?? -1, coords.first?.lon ?? -2, accuracy: 1e-9)
        XCTAssertEqual(simplified.last?.lon ?? -1, coords.last?.lon ?? -2, accuracy: 1e-9)
    }

    func test_simplify_keepsPointDeviatingBeyondEpsilon() {
        // Straight line, but the middle point juts ~50m north — well beyond the
        // daily-mode ε (8m). DP must retain it alongside the two endpoints.
        var coords = (0..<11).map { CoordinateCodable(lat: 0, lon: Double($0) * lonStep) }
        // ~50m north ≈ 0.00045° latitude.
        coords[5] = CoordinateCodable(lat: 0.00045, lon: Double(5) * lonStep)
        let route = dailyRoute(coordinates: coords)

        let simplified = JourneyPostCorrection.simplifiedForDisplay(for: route)

        XCTAssertEqual(simplified.count, 3, "Endpoints + the deviating peak should survive")
        XCTAssertEqual(simplified[1].lat, 0.00045, accuracy: 1e-9)
    }

    func test_simplify_largeRoute_doesNotOverflowStack() {
        // ~120k points. The previous recursive DP could recurse O(n) deep on an
        // adversarial route and overflow the stack. The iterative version keeps
        // its work list on the heap, so this must complete without crashing.
        let count = 120_000
        var coords: [CoordinateCodable] = []
        coords.reserveCapacity(count)
        for i in 0..<count {
            // High-frequency zig-zag with amplitude well above ε so a large
            // fraction of points survive and the work stack is exercised hard.
            let wobble = (i % 2 == 0) ? 0.0009 : -0.0009 // ~100m peak-to-peak
            coords.append(CoordinateCodable(lat: wobble, lon: Double(i) * lonStep))
        }
        let route = dailyRoute(coordinates: coords)

        let simplified = JourneyPostCorrection.simplifiedForDisplay(for: route)

        XCTAssertGreaterThanOrEqual(simplified.count, 2)
        XCTAssertLessThanOrEqual(simplified.count, count)
    }
}
