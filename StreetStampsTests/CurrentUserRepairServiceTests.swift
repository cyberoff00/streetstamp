import XCTest
@testable import StreetStamps

final class CurrentUserRepairServiceTests: XCTestCase {
    func test_repair_moves_disallowed_journeys_to_quarantine_and_rebuilds_ordered_index() throws {
        let fixture = try CurrentUserRepairServiceFixture.make()
        try fixture.writeJourney(id: "allowed-newer", endTime: Date(timeIntervalSince1970: 200))
        try fixture.writeJourney(id: "foreign", endTime: Date(timeIntervalSince1970: 300))
        try fixture.writeJourney(id: "allowed-older", endTime: Date(timeIntervalSince1970: 100))

        let report = CurrentUserRepairReport(
            allowedJourneyIDs: ["allowed-newer", "allowed-older"],
            quarantinedJourneyIDs: ["foreign"],
            missingFromIndexJourneyIDs: ["allowed-newer"],
            orphanedIndexedJourneyIDs: []
        )

        let result = try CurrentUserRepairService.repairCurrentUser(
            activeLocalProfileID: fixture.paths.userID,
            report: report
        )

        XCTAssertEqual(result.quarantinedJourneyIDs, ["foreign"])
        XCTAssertEqual(try fixture.loadIndex(), ["allowed-newer", "allowed-older"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.paths.quarantineDir.appendingPathComponent("foreign.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.journeysDir.appendingPathComponent("foreign.json").path))
    }
}

private struct CurrentUserRepairServiceFixture {
    let paths: StoragePath

    static func make() throws -> CurrentUserRepairServiceFixture {
        let paths = StoragePath(userID: "local_repair_\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()
        return CurrentUserRepairServiceFixture(paths: paths)
    }

    func writeJourney(id: String, endTime: Date) throws {
        let route = JourneyRoute(
            id: id,
            startTime: endTime.addingTimeInterval(-600),
            endTime: endTime,
            coordinates: [
                CoordinateCodable(lat: 51.5, lon: -0.12),
                CoordinateCodable(lat: 51.6, lon: -0.13)
            ]
        )
        let url = paths.journeysDir.appendingPathComponent("\(id).json", isDirectory: false)
        try JSONEncoder().encode(route).write(to: url, options: .atomic)
    }

    func loadIndex() throws -> [String] {
        let data = try Data(contentsOf: paths.journeysDir.appendingPathComponent("index.json", isDirectory: false))
        return try JSONDecoder().decode([String].self, from: data)
    }
}
