import XCTest
@testable import StreetStamps

final class LifelogMigrationServiceTests: XCTestCase {
    func test_migrateLegacyLifelog_movesLegacyPayloadIntoPassiveFile() throws {
        let userID = "lifelog-migration-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        let fm = FileManager.default
        try? fm.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let legacyPayload = makePayload(pointCount: 2)
        try legacyPayload.write(to: paths.lifelogLegacyRouteURL, options: .atomic)

        try LifelogMigrationService.migrateLegacyLifelogIfNeeded(paths: paths)

        XCTAssertTrue(hasTrackData(at: paths.lifelogPassiveRouteURL))
        XCTAssertTrue(fm.fileExists(atPath: paths.lifelogLegacyRouteURL.path) == false)
        XCTAssertTrue(hasTrackData(at: paths.cachesDir.appendingPathComponent("lifelog_route.json.bak", isDirectory: false)))
    }

    func test_migrateLegacyLifelog_withMarker_recoversEmptyPassiveFromBackup() throws {
        let userID = "lifelog-migration-marker-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        let fm = FileManager.default
        try? fm.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let bakURL = paths.cachesDir.appendingPathComponent("lifelog_route.json.bak", isDirectory: false)
        let backupPayload = makePayload(pointCount: 3)
        try backupPayload.write(to: bakURL, options: .atomic)
        try Data("{}".utf8).write(to: paths.lifelogPassiveRouteURL, options: .atomic)
        fm.createFile(atPath: paths.migrationMarkerV5_lifelogPassiveSplit.path, contents: Data())

        try LifelogMigrationService.migrateLegacyLifelogIfNeeded(paths: paths)

        XCTAssertTrue(hasTrackData(at: paths.lifelogPassiveRouteURL))
    }

    private func makePayload(pointCount: Int) -> Data {
        var points: [[String: Double]] = []
        points.reserveCapacity(pointCount)
        var coordinates: [[String: Double]] = []
        coordinates.reserveCapacity(pointCount)

        for idx in 0..<pointCount {
            let lat = 37.0 + Double(idx) * 0.001
            let lon = -122.0 - Double(idx) * 0.001
            points.append([
                "lat": lat,
                "lon": lon,
                "timestamp": 793_972_000.0 + Double(idx) * 30.0
            ])
            coordinates.append([
                "lat": lat,
                "lon": lon
            ])
        }

        let payload: [String: Any] = [
            "points": points,
            "coordinates": coordinates,
            "isEnabled": true,
            "archivedJourneyIDs": [],
            "moodByDay": [:]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data("{}".utf8)
    }

    private func hasTrackData(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any] else {
            return false
        }
        let points = dict["points"] as? [Any] ?? []
        let coords = dict["coordinates"] as? [Any] ?? []
        return !points.isEmpty || !coords.isEmpty
    }
}
