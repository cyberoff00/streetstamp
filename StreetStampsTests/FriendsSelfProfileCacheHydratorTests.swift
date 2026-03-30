import XCTest
@testable import StreetStamps

final class FriendsSelfProfileCacheHydratorTests: XCTestCase {
    func test_resolve_adoptsCachedProfileWhenCurrentIsMissing() {
        let cached = makeProfile(id: "me", journeyID: "cached-journey")

        let resolved = FriendsSelfProfileCacheHydrator.resolve(
            currentRemoteProfile: nil,
            cachedProfile: cached,
            didSeedFromCache: false
        )

        XCTAssertEqual(resolved.profile?.id, "me")
        XCTAssertEqual(resolved.profile?.journeys.map(\.id), ["cached-journey"])
        XCTAssertTrue(resolved.didSeedFromCache)
    }

    func test_resolve_doesNotOverwriteExistingRemoteProfile() {
        let current = makeProfile(id: "me", journeyID: "remote-journey")
        let cached = makeProfile(id: "me", journeyID: "cached-journey")

        let resolved = FriendsSelfProfileCacheHydrator.resolve(
            currentRemoteProfile: current,
            cachedProfile: cached,
            didSeedFromCache: false
        )

        XCTAssertEqual(resolved.profile?.journeys.map(\.id), ["remote-journey"])
        XCTAssertFalse(resolved.didSeedFromCache)
    }

    func test_resolve_doesNotReseedAfterCacheWasAlreadyConsumed() {
        let cached = makeProfile(id: "me", journeyID: "cached-journey")

        let resolved = FriendsSelfProfileCacheHydrator.resolve(
            currentRemoteProfile: nil,
            cachedProfile: cached,
            didSeedFromCache: true
        )

        XCTAssertNil(resolved.profile)
        XCTAssertTrue(resolved.didSeedFromCache)
    }

    private func makeProfile(id: String, journeyID: String) -> BackendProfileDTO {
        BackendProfileDTO(
            id: id,
            displayName: "Me",
            bio: "bio",
            journeys: [
                FriendSharedJourney(
                    id: journeyID,
                    title: "Trip",
                    cityID: "London|GB",
                    activityTag: nil,
                    overallMemory: nil,
                    distance: 3200,
                    startTime: Date(timeIntervalSince1970: 1_000),
                    endTime: Date(timeIntervalSince1970: 2_000),
                    visibility: .friendsOnly,
                    routeCoordinates: [],
                    memories: []
                )
            ],
            unlockedCityCards: [
                FriendCityCard(id: "London|GB", name: "London", countryISO2: "GB")
            ]
        )
    }
}
