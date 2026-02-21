import Foundation

final class JourneysFileStore {
    private let fm = FileManager.default
    private let baseURL: URL

    /// `baseURL` is the user-scoped journeys directory (e.g. .../<userID>/Journeys).
    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    private func ensureBaseDir() throws {
        try fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    private func urlFull(for id: String) -> URL {
        baseURL.appendingPathComponent("\(id).json")
    }

    private func urlMeta(for id: String) -> URL {
        baseURL.appendingPathComponent("\(id).meta.json")
    }

    private func urlDelta(for id: String) -> URL {
        baseURL.appendingPathComponent("\(id).delta.jsonl")
    }

    // MARK: - Writes

    /// Full snapshot (includes full coordinates). Used when a journey is completed (or edited after completion).
    private func saveFullJourney(_ journey: JourneyRoute) throws {
        try ensureBaseDir()
        let target = urlFull(for: journey.id)
        let tmp = target.appendingPathExtension("tmp")

        let data = try JSONEncoder().encode(journey)
        try data.write(to: tmp, options: .atomic)

        if fm.fileExists(atPath: target.path) {
            _ = try? fm.replaceItemAt(target, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: target)
        }
    }

    /// Lightweight snapshot that strips full coordinates (keeps thumbnails + memories + metadata).
    /// Intended to be updated during an ongoing journey without rewriting a huge JSON file.
    func saveMetaSnapshot(_ journey: JourneyRoute) throws {
        try ensureBaseDir()
        let target = urlMeta(for: journey.id)
        let tmp = target.appendingPathExtension("tmp")

        var meta = journey
        meta.coordinates = [] // ✅ strip heavy payload

        let data = try JSONEncoder().encode(meta)
        try data.write(to: tmp, options: .atomic)

        if fm.fileExists(atPath: target.path) {
            _ = try? fm.replaceItemAt(target, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: target)
        }
    }

    /// Append-only coordinate persistence for ongoing journeys.
    /// Writes one JSON array per line to keep decoding simple and IO minimal.
    func appendDelta(journeyId: String, newCoords: [CoordinateCodable]) throws {
        guard !newCoords.isEmpty else { return }
        try ensureBaseDir()

        let target = urlDelta(for: journeyId)
        var data = try JSONEncoder().encode(newCoords)
        data.append(0x0A) // newline

        if fm.fileExists(atPath: target.path) {
            let handle = try FileHandle(forWritingTo: target)
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try data.write(to: target, options: .atomic)
        }
    }

    /// Finalize a journey by writing the full snapshot and removing any meta/delta leftovers.
    func finalizeJourney(_ journey: JourneyRoute) throws {
        try saveFullJourney(journey)

        // Best-effort cleanup: if we crash during cleanup, full snapshot is still correct.
        let meta = urlMeta(for: journey.id)
        let delta = urlDelta(for: journey.id)
        _ = try? fm.removeItem(at: meta)
        _ = try? fm.removeItem(at: delta)
    }

    /// Remove all persisted files for a journey id.
    func deleteJourney(id: String) throws {
        let full = urlFull(for: id)
        let meta = urlMeta(for: id)
        let delta = urlDelta(for: id)
        if fm.fileExists(atPath: full.path) { try fm.removeItem(at: full) }
        if fm.fileExists(atPath: meta.path) { try fm.removeItem(at: meta) }
        if fm.fileExists(atPath: delta.path) { try fm.removeItem(at: delta) }
    }

    // MARK: - Reads

    func loadJourney(id: String) throws -> JourneyRoute {
        let fullURL = urlFull(for: id)
        let metaURL = urlMeta(for: id)
        let deltaURL = urlDelta(for: id)

        let fullExists = fm.fileExists(atPath: fullURL.path)
        let metaExists = fm.fileExists(atPath: metaURL.path)

        var base: JourneyRoute?
        var meta: JourneyRoute?

        if fullExists {
            let data = try Data(contentsOf: fullURL)
            base = try JSONDecoder().decode(JourneyRoute.self, from: data)
        }
        if metaExists {
            let data = try Data(contentsOf: metaURL)
            meta = try JSONDecoder().decode(JourneyRoute.self, from: data)
        }

        guard let seed = base ?? meta else {
            throw NSError(domain: "JourneysFileStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "Journey not found: \(id)"])
        }

        var out: JourneyRoute = seed
        if let b = base, let m = meta {
            out = b.merged(with: m) // keep full coords from `b`, take newer metadata from `m`
        } else if let m = meta {
            out = m
        } else if let b = base {
            out = b
        }

        // Apply deltas (if any)
        if fm.fileExists(atPath: deltaURL.path) {
            let raw = try String(contentsOf: deltaURL, encoding: .utf8)
            let lines = raw.split(separator: "\n")

            if !lines.isEmpty {
                let decoder = JSONDecoder()
                for line in lines {
                    guard !line.isEmpty else { continue }
                    if let data = line.data(using: .utf8),
                       let chunk = try? decoder.decode([CoordinateCodable].self, from: data) {
                        for c in chunk {
                            if let last = out.coordinates.last, last.lat == c.lat, last.lon == c.lon {
                                continue
                            }
                            out.coordinates.append(c)
                        }
                    }
                }
            }
        }

        // Ensure thumbnails exist even for older stored journeys.
        out.ensureThumbnail(maxPoints: 280)
        return out
    }

    func loadJourneys(ids: [String]) async -> [JourneyRoute] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var result: [JourneyRoute] = []
                result.reserveCapacity(ids.count)
                for id in ids {
                    if let j = try? self.loadJourney(id: id) { result.append(j) }
                }
                cont.resume(returning: result)
            }
        }
    }
}
