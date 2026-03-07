import XCTest
@testable import StreetStamps

final class GuestDataRecoveryServiceTests: XCTestCase {
    func test_recover_copiesLifelogMoodFileToTargetUser() throws {
        let sourceUserID = "guest-recovery-source-\(UUID().uuidString)"
        let targetUserID = "guest-recovery-target-\(UUID().uuidString)"
        let source = StoragePath(userID: sourceUserID)
        let target = StoragePath(userID: targetUserID)
        let fm = FileManager.default

        try? fm.removeItem(at: source.userRoot)
        try? fm.removeItem(at: target.userRoot)
        try source.ensureBaseDirectoriesExist()
        try target.ensureBaseDirectoriesExist()

        let today = Calendar.current.startOfDay(for: Date())
        let moodKey = dayKey(today)
        let moodURL = source.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        let payload = [moodKey: "happy"]
        let data = try JSONEncoder().encode(payload)
        try data.write(to: moodURL, options: .atomic)

        _ = try GuestDataRecoveryService.recover(from: sourceUserID, to: targetUserID)

        let targetMoodURL = target.cachesDir.appendingPathComponent("lifelog_mood.json", isDirectory: false)
        let targetData = try Data(contentsOf: targetMoodURL)
        let restored = try JSONDecoder().decode([String: String].self, from: targetData)
        XCTAssertEqual(restored[moodKey], "happy")
    }

    private func dayKey(_ day: Date) -> String {
        let start = Calendar.current.startOfDay(for: day)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: start)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}
