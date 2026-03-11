import Foundation
import CoreLocation

struct LifelogCountryAttributionPointInput: Sendable, Equatable {
    let pointID: String
    let cellID: String
    let coordinate: CoordinateCodable
}

actor LifelogCountryAttributionCoordinator {
    typealias CanonicalResolver = @Sendable (CLLocation) async -> ReverseGeocodeService.CanonicalResult?

    private let store: LifelogCountryAttributionStore
    private let resolveCanonical: CanonicalResolver

    private var snapshot: LifelogCountryAttributionSnapshot
    private var pendingCells: [String: CoordinateCodable] = [:]
    private var unresolvedCellIDs = Set<String>()
    private var processingTask: Task<Void, Never>?

    init(
        paths: StoragePath,
        store: LifelogCountryAttributionStore? = nil,
        resolveCanonical: @escaping CanonicalResolver = { location in
            await ReverseGeocodeService.shared.canonical(for: location)
        }
    ) {
        let resolvedStore = store ?? LifelogCountryAttributionStore(paths: paths)
        self.store = resolvedStore
        self.resolveCanonical = resolveCanonical
        self.snapshot = (try? resolvedStore.load()) ?? .empty
    }

    func enqueue(points: [LifelogCountryAttributionPointInput]) async {
        guard !points.isEmpty else { return }

        let cellsByID = Dictionary(uniqueKeysWithValues: snapshot.cells.map { ($0.cellID, $0) })
        var didChange = false
        var earliestChangedPointIndex: Int?

        for point in points {
            let resolvedISO2 = cellsByID[point.cellID]?.iso2
            let next = LifelogPointCountryRecord(
                pointID: point.pointID,
                cellID: point.cellID,
                iso2: resolvedISO2
            )

            if let existingIndex = snapshot.points.firstIndex(where: { $0.pointID == point.pointID }) {
                if snapshot.points[existingIndex] != next {
                    snapshot.points[existingIndex] = next
                    didChange = true
                    earliestChangedPointIndex = min(earliestChangedPointIndex ?? existingIndex, existingIndex)
                }
            } else {
                snapshot.points.append(next)
                didChange = true
                let insertedIndex = snapshot.points.count - 1
                earliestChangedPointIndex = min(earliestChangedPointIndex ?? insertedIndex, insertedIndex)
            }

            if cellsByID[point.cellID] == nil && !unresolvedCellIDs.contains(point.cellID) {
                pendingCells[point.cellID] = point.coordinate
            }
        }

        if didChange, let earliestChangedPointIndex {
            rebuildRuns(fromPointIndex: earliestChangedPointIndex)
            persistSnapshot()
        }

        startProcessingIfNeeded()
    }

    func loadSnapshot() -> LifelogCountryAttributionSnapshot {
        snapshot
    }

    private func startProcessingIfNeeded() {
        guard processingTask == nil, !pendingCells.isEmpty else { return }
        processingTask = Task { [weak self] in
            await self?.drainPendingCells()
        }
    }

    private func drainPendingCells() async {
        while let cellID = pendingCells.keys.sorted().first,
              let coordinate = pendingCells.removeValue(forKey: cellID) {
            let location = CLLocation(latitude: coordinate.lat, longitude: coordinate.lon)
            let result = await resolveCanonical(location)
            await applyResolution(result, forCellID: cellID)
        }

        processingTask = nil
        if !pendingCells.isEmpty {
            startProcessingIfNeeded()
        }
    }

    private func applyResolution(
        _ result: ReverseGeocodeService.CanonicalResult?,
        forCellID cellID: String
    ) {
        guard let result else {
            unresolvedCellIDs.insert(cellID)
            return
        }

        let iso2 = result.iso2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let iso2, !iso2.isEmpty else {
            unresolvedCellIDs.insert(cellID)
            return
        }

        unresolvedCellIDs.remove(cellID)

        var cellsByID = Dictionary(uniqueKeysWithValues: snapshot.cells.map { ($0.cellID, $0) })
        cellsByID[cellID] = LifelogCellCountryRecord(
            cellID: cellID,
            iso2: iso2,
            source: .reverseGeocode,
            confidence: 1.0,
            resolvedAt: Date()
        )
        snapshot.cells = cellsByID.values.sorted { $0.cellID < $1.cellID }

        snapshot.points = snapshot.points.map { point in
            guard point.cellID == cellID else { return point }
            return LifelogPointCountryRecord(pointID: point.pointID, cellID: point.cellID, iso2: iso2)
        }
        rebuildRuns(fromPointIndex: firstPointIndex(forCellID: cellID) ?? 0)
        persistSnapshot()
        NotificationCenter.default.post(
            name: .lifelogCountryAttributionDidChange,
            object: nil,
            userInfo: ["countryISO2": iso2]
        )
    }

    private func firstPointIndex(forCellID cellID: String) -> Int? {
        snapshot.points.firstIndex { $0.cellID == cellID }
    }

    private func rebuildRuns(fromPointIndex pointIndex: Int) {
        snapshot.runs = LifelogCountryRunBuilder.rebuildRuns(
            existingRuns: snapshot.runs,
            points: snapshot.points,
            fromPointIndex: pointIndex
        )
    }

    private func persistSnapshot() {
        do {
            try store.save(snapshot)
        } catch {
            print("❌ lifelog country attribution save failed:", error)
        }
    }
}
