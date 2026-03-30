import Foundation

enum LifelogCountryRunBuilder {
    static func buildRuns(points: [LifelogPointCountryRecord]) -> [LifelogCountryRunRecord] {
        buildRuns(points: ArraySlice(points))
    }

    static func rebuildRuns(
        existingRuns: [LifelogCountryRunRecord],
        points: [LifelogPointCountryRecord],
        fromPointIndex pointIndex: Int
    ) -> [LifelogCountryRunRecord] {
        guard !points.isEmpty else { return [] }

        let clampedPointIndex = max(0, min(pointIndex, points.count - 1))
        let pointIndexesByID = Dictionary(points.enumerated().map { ($0.element.pointID, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let expansionPointIndex = max(0, clampedPointIndex - 1)
        let rebuildStartIndex = existingRuns.first { run in
            guard let runStartIndex = pointIndexesByID[run.startPointID],
                  let runEndIndex = pointIndexesByID[run.endPointID] else {
                return false
            }
            return runStartIndex ... runEndIndex ~= expansionPointIndex
        }.flatMap { pointIndexesByID[$0.startPointID] } ?? expansionPointIndex

        let prefixRuns = existingRuns.prefix { run in
            guard let endIndex = pointIndexesByID[run.endPointID] else { return false }
            return endIndex < rebuildStartIndex
        }

        let suffixRuns = buildRuns(points: points[rebuildStartIndex...])
        return Array(prefixRuns) + suffixRuns
    }

    private static func buildRuns(points: ArraySlice<LifelogPointCountryRecord>) -> [LifelogCountryRunRecord] {
        guard let first = points.first else { return [] }

        var runs: [LifelogCountryRunRecord] = []
        var startPointID = first.pointID
        var endPointID = first.pointID
        var currentISO2 = first.iso2

        for point in points.dropFirst() {
            if point.iso2 == currentISO2 {
                endPointID = point.pointID
                continue
            }

            runs.append(
                LifelogCountryRunRecord(
                    startPointID: startPointID,
                    endPointID: endPointID,
                    iso2: currentISO2
                )
            )
            startPointID = point.pointID
            endPointID = point.pointID
            currentISO2 = point.iso2
        }

        runs.append(
            LifelogCountryRunRecord(
                startPointID: startPointID,
                endPointID: endPointID,
                iso2: currentISO2
            )
        )
        return runs
    }
}
