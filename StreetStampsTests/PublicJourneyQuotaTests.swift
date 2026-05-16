import XCTest
@testable import StreetStamps

final class PublicJourneyQuotaTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PublicJourneyQuota._setCutoffForTesting(nil)
    }

    override func tearDown() {
        PublicJourneyQuota._setCutoffForTesting(nil)
        super.tearDown()
    }

    func test_ensureCutoff_seals_now_on_first_call_and_is_stable_after() {
        let first = PublicJourneyQuota.ensureCutoff()
        let second = PublicJourneyQuota.ensureCutoff()
        XCTAssertEqual(first.timeIntervalSince1970, second.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_pre_cutoff_journeys_do_not_count() {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        PublicJourneyQuota._setCutoffForTesting(cutoff)

        var pre = JourneyRoute()
        pre.sharedAt = Date(timeIntervalSince1970: 1_699_999_000) // before cutoff

        XCTAssertEqual(PublicJourneyQuota.usedCount(journeys: [pre]), 0)
    }

    func test_post_cutoff_published_journeys_count() {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        PublicJourneyQuota._setCutoffForTesting(cutoff)

        var a = JourneyRoute(); a.sharedAt = Date(timeIntervalSince1970: 1_700_000_100)
        var b = JourneyRoute(); b.sharedAt = Date(timeIntervalSince1970: 1_700_000_200)
        var c = JourneyRoute() // never published

        XCTAssertEqual(PublicJourneyQuota.usedCount(journeys: [a, b, c]), 2)
    }

    func test_free_tier_at_or_above_limit_is_over_free_limit() {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        PublicJourneyQuota._setCutoffForTesting(cutoff)

        var five: [JourneyRoute] = []
        for i in 0..<5 {
            var j = JourneyRoute()
            j.sharedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(100 + i))
            five.append(j)
        }
        XCTAssertTrue(PublicJourneyQuota.isOverFreeLimit(journeys: five, tier: .free))

        var four = Array(five.prefix(4))
        XCTAssertFalse(PublicJourneyQuota.isOverFreeLimit(journeys: four, tier: .free))
        _ = four
    }

    func test_premium_is_never_over_limit() {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        PublicJourneyQuota._setCutoffForTesting(cutoff)

        var lots: [JourneyRoute] = []
        for i in 0..<50 {
            var j = JourneyRoute()
            j.sharedAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(100 + i))
            lots.append(j)
        }
        XCTAssertFalse(PublicJourneyQuota.isOverFreeLimit(journeys: lots, tier: .premium))
    }
}
