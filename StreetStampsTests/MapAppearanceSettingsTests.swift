import XCTest
@testable import StreetStamps

final class MapAppearanceSettingsTests: XCTestCase {
    func test_usesMutedStandardMap_darkIsTrue_lightIsFalse() {
        XCTAssertTrue(MapAppearanceSettings.usesMutedStandardMap(for: .dark))
        XCTAssertFalse(MapAppearanceSettings.usesMutedStandardMap(for: .light))
    }
}

final class MapViewRouteRenderStyleTests: XCTestCase {
    func test_coreWidth_getsThinnerAsAltitudeIncreases() {
        let near = MapViewRouteRenderStyle.coreWidth(forAltitude: 600, mode: .walk)
        let far = MapViewRouteRenderStyle.coreWidth(forAltitude: 4_000, mode: .walk)

        XCTAssertLessThan(far, near)
        XCTAssertGreaterThan(far, 3.0)
    }

    func test_walk_isSlightlyWiderThanTransitAtSameAltitude() {
        let walk = MapViewRouteRenderStyle.coreWidth(forAltitude: 1_200, mode: .walk)
        let transit = MapViewRouteRenderStyle.coreWidth(forAltitude: 1_200, mode: .transit)

        XCTAssertGreaterThan(walk, transit)
    }

    func test_cleanProfile_usesSubtleHaloAndFrequencyLayers() {
        let widths = MapViewRouteRenderStyle.layerWidths(forAltitude: 1_200, mode: .walk, repeatWeight: 0.6, isGap: false)

        XCTAssertGreaterThan(widths.halo, widths.core)
        XCTAssertLessThan(widths.halo, widths.core * 1.45)
        XCTAssertLessThan(widths.frequency, widths.core)
        XCTAssertGreaterThan(widths.core, 2.5)
    }

    func test_altitudeBucket_ignoresTinyZoomChangesButDetectsRealZoomStep() {
        let baseline = MapViewRouteRenderStyle.altitudeBucket(for: 1_000)
        let tinyChange = MapViewRouteRenderStyle.altitudeBucket(for: 1_040)
        let largeChange = MapViewRouteRenderStyle.altitudeBucket(for: 2_200)

        XCTAssertEqual(baseline, tinyChange)
        XCTAssertNotEqual(baseline, largeChange)
    }
}

final class FriendFeedLogicTests: XCTestCase {
    func test_isJourneyEligible_requiresVisibilityAndDistanceOrMemory() {
        let base = makeJourney(visibility: .public, distance: 1_999, memories: [])
        XCTAssertFalse(FriendFeedLogic.isJourneyEligible(base))

        let withMemory = makeJourney(visibility: .friendsOnly, distance: 100, memories: [makeMemory()])
        XCTAssertTrue(FriendFeedLogic.isJourneyEligible(withMemory))

        let longDistance = makeJourney(visibility: .public, distance: 2_000, memories: [])
        XCTAssertTrue(FriendFeedLogic.isJourneyEligible(longDistance))

        let privateLongDistance = makeJourney(visibility: .private, distance: 10_000, memories: [makeMemory()])
        XCTAssertFalse(FriendFeedLogic.isJourneyEligible(privateLongDistance))
    }

    func test_eventTitle_forJourney_prefersCustomJourneyTitle() {
        let title = FriendFeedLogic.eventTitle(
            kind: .journey,
            cityName: "London",
            memoryCount: 0,
            journeyTitle: "Spring Escape",
            localize: { key in
                if key == "friends_event_published_journey" { return "发布了旅程「%@」" }
                if key == "friends_event_completed_journey" { return "完成了一段旅程" }
                return key
            }
        )

        XCTAssertEqual(title, "发布了旅程「Spring Escape」")
    }

    func test_eventTitle_forMemory_prefersCustomJourneyTitle() {
        let title = FriendFeedLogic.eventTitle(
            kind: .memory,
            cityName: "Kyoto",
            memoryCount: 3,
            journeyTitle: "Autumn Notes",
            localize: { key in
                if key == "friends_event_published_journey" { return "发布了旅程「%@」" }
                if key == "friends_event_added_memory" { return "添加了记忆" }
                return key
            }
        )

        XCTAssertEqual(title, "发布了旅程「Autumn Notes」")
    }

    func test_eventTitle_fallsBackToGenericCopyWhenJourneyTitleMatchesCity() {
        let title = FriendFeedLogic.eventTitle(
            kind: .journey,
            cityName: "London",
            memoryCount: 0,
            journeyTitle: "London",
            localize: { key in
                if key == "friends_event_published_journey" { return "发布了旅程「%@」" }
                if key == "friends_event_completed_journey" { return "完成了一段旅程" }
                return key
            }
        )

        XCTAssertEqual(title, "完成了一段旅程")
        XCTAssertFalse(title.contains("London"))
    }

    func test_locationTitle_hidesWhenCityCannotBeResolved() {
        XCTAssertEqual(
            FriendFeedLogic.locationTitle(cityName: "Unknown City", unknownCityLabel: "Unknown City"),
            ""
        )
        XCTAssertEqual(
            FriendFeedLogic.locationTitle(cityName: "", unknownCityLabel: "Unknown City"),
            ""
        )
        XCTAssertEqual(
            FriendFeedLogic.locationTitle(cityName: "Kyoto", unknownCityLabel: "Unknown City"),
            "Kyoto"
        )
    }

    func test_feedTimestamp_prefersSharedAtOverJourneyAndMemoryDates() {
        let journey = FriendSharedJourney(
            id: UUID().uuidString,
            title: "London",
            activityTag: nil,
            overallMemory: nil,
            distance: 3_000,
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            visibility: .friendsOnly,
            sharedAt: Date(timeIntervalSince1970: 500),
            routeCoordinates: [],
            memories: [
                FriendSharedMemory(
                    id: UUID().uuidString,
                    title: "m",
                    notes: "",
                    timestamp: Date(timeIntervalSince1970: 400),
                    imageURLs: []
                )
            ]
        )

        XCTAssertEqual(FriendFeedLogic.feedTimestamp(for: journey), Date(timeIntervalSince1970: 500))
    }

    private func makeJourney(
        visibility: JourneyVisibility,
        distance: Double,
        memories: [FriendSharedMemory]
    ) -> FriendSharedJourney {
        FriendSharedJourney(
            id: UUID().uuidString,
            title: "London",
            activityTag: nil,
            overallMemory: nil,
            distance: distance,
            startTime: Date(),
            endTime: Date(),
            visibility: visibility,
            routeCoordinates: [],
            memories: memories
        )
    }

    private func makeMemory() -> FriendSharedMemory {
        FriendSharedMemory(
            id: UUID().uuidString,
            title: "m",
            notes: "",
            timestamp: Date(),
            imageURLs: []
        )
    }
}
