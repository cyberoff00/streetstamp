import XCTest
@testable import StreetStamps

final class CurrentUserRepairDiagnosticTests: XCTestCase {
    func test_buildReport_marks_unindexed_and_disallowed_journeys() throws {
        let fixture = try CurrentUserRepairFixture.make()
        try fixture.writeJourney(id: "guest-ok", indexed: true)
        try fixture.writeJourney(id: "foreign", indexed: false)
        try fixture.writeSourceMap([
            "guest-ok": .deviceGuest(guestID: "guest123"),
            "foreign": .unknown
        ])

        let report = try CurrentUserRepairDiagnostic.buildReport(
            activeLocalProfileID: fixture.activeLocalProfileID,
            currentGuestScopedUserID: fixture.currentGuestScopedUserID,
            currentAccountUserID: fixture.currentAccountUserID
        )

        XCTAssertEqual(report.allowedJourneyIDs, ["guest-ok"])
        XCTAssertEqual(report.quarantinedJourneyIDs, ["foreign"])
        XCTAssertEqual(report.missingFromIndexJourneyIDs, ["foreign"])
        XCTAssertEqual(report.orphanedIndexedJourneyIDs, [])
    }

    func test_buildReport_quarantines_sourceLessLegacyJourney_forSignedInAccount() throws {
        let fixture = try CurrentUserRepairFixture.make()
        try fixture.writeJourney(id: "legacy-local", indexed: true)

        let report = try CurrentUserRepairDiagnostic.buildReport(
            activeLocalProfileID: fixture.activeLocalProfileID,
            currentGuestScopedUserID: fixture.currentGuestScopedUserID,
            currentAccountUserID: fixture.currentAccountUserID
        )

        XCTAssertEqual(report.allowedJourneyIDs, [])
        XCTAssertEqual(report.quarantinedJourneyIDs, ["legacy-local"])
        XCTAssertEqual(report.missingFromIndexJourneyIDs, [])
        XCTAssertEqual(report.orphanedIndexedJourneyIDs, [])
    }

    func test_buildReport_keeps_sourceLessLegacyJourney_inGuestMode() throws {
        let fixture = try CurrentUserRepairFixture.make(currentAccountUserID: nil)
        try fixture.writeJourney(id: "legacy-local", indexed: true)

        let report = try CurrentUserRepairDiagnostic.buildReport(
            activeLocalProfileID: fixture.activeLocalProfileID,
            currentGuestScopedUserID: fixture.currentGuestScopedUserID,
            currentAccountUserID: fixture.currentAccountUserID
        )

        XCTAssertEqual(report.allowedJourneyIDs, ["legacy-local"])
        XCTAssertEqual(report.quarantinedJourneyIDs, [])
        XCTAssertEqual(report.missingFromIndexJourneyIDs, [])
        XCTAssertEqual(report.orphanedIndexedJourneyIDs, [])
    }
}

private struct CurrentUserRepairFixture {
    let activeLocalProfileID: String
    let currentGuestScopedUserID: String
    let currentAccountUserID: String?
    let paths: StoragePath

    static func make(currentAccountUserID: String? = "abc") throws -> CurrentUserRepairFixture {
        let activeLocalProfileID = "local_guest123_\(UUID().uuidString)"
        let paths = StoragePath(userID: activeLocalProfileID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()
        return CurrentUserRepairFixture(
            activeLocalProfileID: activeLocalProfileID,
            currentGuestScopedUserID: "guest_guest123",
            currentAccountUserID: currentAccountUserID,
            paths: paths
        )
    }

    func writeJourney(id: String, indexed: Bool, endTime: Date = Date(timeIntervalSince1970: 100)) throws {
        let route = JourneyRoute(
            id: id,
            startTime: endTime.addingTimeInterval(-600),
            endTime: endTime,
            coordinates: [
                CoordinateCodable(lat: 51.5, lon: -0.12),
                CoordinateCodable(lat: 51.6, lon: -0.13)
            ]
        )
        let data = try JSONEncoder().encode(route)
        let url = paths.journeysDir.appendingPathComponent("\(id).json", isDirectory: false)
        try data.write(to: url, options: .atomic)
        if indexed {
            let indexURL = paths.journeysDir.appendingPathComponent("index.json", isDirectory: false)
            let existing = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: indexURL))) ?? []
            try JSONEncoder().encode(existing + [id]).write(to: indexURL, options: .atomic)
        }
    }

    func writeSourceMap(_ map: [String: JourneyRepairSource]) throws {
        let data = try JSONEncoder().encode(map)
        try data.write(to: paths.journeyRepairSourcesURL, options: .atomic)
    }
}
