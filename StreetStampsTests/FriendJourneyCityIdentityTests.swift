import XCTest
@testable import StreetStamps

final class FriendJourneyCityIdentityTests: XCTestCase {
    func test_resolveCityID_prefersStableCityIDWhenTitleLanguageDiffers() {
        let journey = FriendSharedJourney(
            id: "journey-london",
            title: "伦敦",
            cityID: "London|GB",
            activityTag: nil,
            overallMemory: nil,
            distance: 3_000,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            visibility: .friendsOnly,
            routeCoordinates: [],
            memories: []
        )
        let cards = [
            FriendCityCard(id: "Paris|FR", name: "Paris", countryISO2: "FR"),
            FriendCityCard(id: "London|GB", name: "London", countryISO2: "GB")
        ]

        XCTAssertEqual(
            FriendJourneyCityIdentity.resolveCityID(for: journey, cards: cards),
            "London|GB"
        )
    }

    func test_resolveCityID_fallsBackToTitleMatchingForLegacyJourneyWithoutStableCityID() {
        let journey = FriendSharedJourney(
            id: "journey-legacy",
            title: "London",
            activityTag: nil,
            overallMemory: nil,
            distance: 3_000,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            visibility: .friendsOnly,
            routeCoordinates: [],
            memories: []
        )
        let cards = [
            FriendCityCard(id: "Paris|FR", name: "Paris", countryISO2: "FR"),
            FriendCityCard(id: "London|GB", name: "London", countryISO2: "GB")
        ]

        XCTAssertEqual(
            FriendJourneyCityIdentity.resolveCityID(for: journey, cards: cards),
            "London|GB"
        )
    }

    func test_resolveCityID_doesNotFallbackToFirstCardWhenStableIDAndTitleMatchAreMissing() {
        let journey = FriendSharedJourney(
            id: "journey-hangzhou-legacy",
            title: "杭州市",
            activityTag: nil,
            overallMemory: nil,
            distance: 3_000,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            visibility: .friendsOnly,
            routeCoordinates: [],
            memories: []
        )
        let cards = [
            FriendCityCard(id: "Cupertino|US", name: "Cupertino", countryISO2: "US"),
            FriendCityCard(id: "Hangzhou|CN", name: "Hangzhou", countryISO2: "CN")
        ]

        XCTAssertEqual(
            FriendJourneyCityIdentity.resolveCityID(for: journey, cards: cards),
            "Unknown|"
        )
    }

    func test_resolveCityID_fallsBackWhenStableCityIDIsMissingFromCards() {
        let journey = FriendSharedJourney(
            id: "journey-stale-city-id",
            title: "London",
            cityID: "Legacy London|GB",
            activityTag: nil,
            overallMemory: nil,
            distance: 3_000,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            visibility: .friendsOnly,
            routeCoordinates: [],
            memories: []
        )
        let cards = [
            FriendCityCard(id: "London|GB", name: "London", countryISO2: "GB"),
            FriendCityCard(id: "Paris|FR", name: "Paris", countryISO2: "FR")
        ]

        XCTAssertEqual(
            FriendJourneyCityIdentity.resolveCityID(for: journey, cards: cards),
            "London|GB"
        )
    }

    func test_resolveCityID_returnsUnknownForStaleStableCityIDWithoutRecoverableMatch() {
        let journey = FriendSharedJourney(
            id: "journey-stale-unrecoverable",
            title: "Weekend Trip",
            cityID: "Legacy London|GB",
            activityTag: nil,
            overallMemory: nil,
            distance: 3_000,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            visibility: .friendsOnly,
            routeCoordinates: [],
            memories: []
        )
        let cards = [
            FriendCityCard(id: "Paris|FR", name: "Paris", countryISO2: "FR"),
            FriendCityCard(id: "Berlin|DE", name: "Berlin", countryISO2: "DE")
        ]

        XCTAssertEqual(
            FriendJourneyCityIdentity.resolveCityID(for: journey, cards: cards),
            "Unknown|"
        )
    }

    func test_stableCityID_fallsBackToNonEmptyCityKeyWhenStartCityKeyIsEmptyString() {
        let route = JourneyRoute(
            id: "journey-empty-start-key",
            endTime: Date(),
            cityKey: "Shenzhen|CN",
            canonicalCity: "Shenzhen",
            startCityKey: "",
            visibility: .friendsOnly
        )

        XCTAssertEqual(
            FriendJourneyCityIdentity.stableCityID(from: route),
            "Shenzhen|CN"
        )
    }

    func test_journeyStableCityKey_prefersNonEmptyStartCityKey() {
        let route = JourneyRoute(
            id: "journey-stable-city-key",
            endTime: Date(),
            cityKey: "Shenzhen|CN",
            canonicalCity: "Shenzhen",
            startCityKey: "London|GB",
            visibility: .friendsOnly
        )

        XCTAssertEqual(route.stableCityKey, "London|GB")
    }

    func test_journeyMerge_preservesStableCityKeyWhenIncomingStartCityKeyIsEmpty() {
        let persisted = JourneyRoute(
            id: "journey-merge-city-key",
            endTime: Date(),
            cityKey: "Shenzhen|CN",
            canonicalCity: "Shenzhen",
            startCityKey: "Shenzhen|CN",
            visibility: .friendsOnly
        )
        let incoming = JourneyRoute(
            id: "journey-merge-city-key",
            endTime: Date(),
            cityKey: "Shenzhen|CN",
            canonicalCity: "Shenzhen",
            startCityKey: "",
            visibility: .friendsOnly
        )

        let merged = persisted.merged(with: incoming)

        XCTAssertEqual(merged.stableCityKey, "Shenzhen|CN")
        XCTAssertEqual(merged.cityKey, "Shenzhen|CN")
        XCTAssertEqual(merged.startCityKey, "Shenzhen|CN")
    }
}
