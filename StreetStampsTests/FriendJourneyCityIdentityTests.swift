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
}
