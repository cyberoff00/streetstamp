import Foundation

enum LifelogCountryAttributionSource: String, Codable, Equatable, Sendable {
    case reverseGeocode
    case cityKey
}

struct LifelogCellCountryRecord: Codable, Equatable, Sendable {
    let cellID: String
    let iso2: String
    let source: LifelogCountryAttributionSource
    let confidence: Double
    let resolvedAt: Date
}

struct LifelogPointCountryRecord: Codable, Equatable, Sendable {
    let pointID: String
    let cellID: String
    let iso2: String?
}

struct LifelogCountryRunRecord: Codable, Equatable, Sendable {
    let startPointID: String
    let endPointID: String
    let iso2: String?
}

struct LifelogCountryAttributionSnapshot: Codable, Equatable, Sendable {
    var cells: [LifelogCellCountryRecord]
    var points: [LifelogPointCountryRecord]
    var runs: [LifelogCountryRunRecord]

    static let empty = LifelogCountryAttributionSnapshot(cells: [], points: [], runs: [])
}

final class LifelogCountryAttributionStore {
    private struct Payload: Codable, Equatable {
        var version: Int
        var cells: [LifelogCellCountryRecord]
        var points: [LifelogPointCountryRecord]
        var runs: [LifelogCountryRunRecord]
    }

    private let cellsURL: URL
    private let pointsURL: URL
    private let runsURL: URL
    private let fm: FileManager

    init(paths: StoragePath, fm: FileManager = .default) {
        self.cellsURL = paths.lifelogCountryCellsURL
        self.pointsURL = paths.lifelogPointCountriesURL
        self.runsURL = paths.lifelogCountryRunsURL
        self.fm = fm
    }

    func load() throws -> LifelogCountryAttributionSnapshot {
        LifelogCountryAttributionSnapshot(
            cells: try loadRecords(from: cellsURL, as: [LifelogCellCountryRecord].self),
            points: try loadRecords(from: pointsURL, as: [LifelogPointCountryRecord].self),
            runs: try loadRecords(from: runsURL, as: [LifelogCountryRunRecord].self)
        )
    }

    func save(_ snapshot: LifelogCountryAttributionSnapshot) throws {
        try saveRecords(snapshot.cells, to: cellsURL)
        try saveRecords(snapshot.points, to: pointsURL)
        try saveRecords(snapshot.runs, to: runsURL)
    }

    private func loadRecords<T: Codable>(from url: URL, as type: T.Type) throws -> T where T: ExpressibleByArrayLiteral {
        guard fm.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PayloadWrapper<T>.self, from: data).records
    }

    private func saveRecords<T: Codable>(_ records: T, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(PayloadWrapper(version: 1, records: records))
        try data.write(to: url, options: .atomic)
    }

    private struct PayloadWrapper<T: Codable>: Codable {
        let version: Int
        let records: T

        init(version: Int, records: T) {
            self.version = version
            self.records = records
        }

        private enum CodingKeys: String, CodingKey {
            case version
            case records
        }
    }
}
