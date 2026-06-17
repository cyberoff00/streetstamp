//
//  SmallWorldModel.swift
//  StreetStamps
//
//  「你的小世界」— the warm, non-competitive retrospective.
//
//  Thesis: a life is not measured by how far you got out, but by where you keep
//  coming back. This file holds the PURE, testable logic that turns passive
//  lifelog points into that retrospective. It deliberately knows nothing about
//  SwiftUI, stores, CLGeocoder, or rendering — view code feeds it plain values
//  and renders the result. Keep it that way (see CLAUDE.md: extract logic into
//  pure helpers, cover with focused tests).
//

import Foundation
import CoreLocation

/// One passive sample, flattened out of `LifelogStore` into a store-independent
/// value so the builder stays pure and trivially testable.
struct SmallWorldPoint: Equatable, Sendable {
    let lat: Double
    let lon: Double
    /// ~1km grid cell id (`TrackPointCellID.make`). The unit of "a place".
    let cellID: String
    /// `"yyyy-MM-dd"` local day key (matches `LifelogStore` day keys).
    let dayKey: String
}

/// A place the user keeps returning to. Ranked by how many *distinct days* it
/// appears — time-of-life, not novelty.
struct ReturnPlace: Equatable, Identifiable {
    let cellID: String
    let center: CLLocationCoordinate2D
    /// Distinct days this cell was visited. The headline number.
    let visitDays: Int
    let totalPoints: Int
    /// Meters from the user's anchor ("home"). 0 for the anchor itself.
    let metersFromAnchor: Double

    var id: String { cellID }

    static func == (lhs: ReturnPlace, rhs: ReturnPlace) -> Bool {
        lhs.cellID == rhs.cellID &&
        lhs.center.latitude == rhs.center.latitude &&
        lhs.center.longitude == rhs.center.longitude &&
        lhs.visitDays == rhs.visitDays &&
        lhs.totalPoints == rhs.totalPoints &&
        lhs.metersFromAnchor == rhs.metersFromAnchor
    }
}

/// A resurfaced *ordinary* day — 重逢. Not a highlight; a regular day pulled back
/// up from the past, with the mood felt that day.
struct ReunionMoment: Equatable {
    let date: Date
    /// Raw mood value for that day (`happy` / `notbad2` / `sad`), or nil.
    let mood: String?
    let center: CLLocationCoordinate2D?
    let pointCount: Int

    static func == (lhs: ReunionMoment, rhs: ReunionMoment) -> Bool {
        lhs.date == rhs.date &&
        lhs.mood == rhs.mood &&
        lhs.pointCount == rhs.pointCount &&
        lhs.center?.latitude == rhs.center?.latitude &&
        lhs.center?.longitude == rhs.center?.longitude
    }
}

struct SmallWorldSummary: Equatable {
    /// False when there is too little passive history to say anything tender or
    /// honest. The view shows a gentle empty state instead of fake numbers.
    let hasEnoughData: Bool
    /// The most-returned cell center — the gravitational center of this life.
    let anchor: CLLocationCoordinate2D?
    /// Radius from `anchor` that contains `coveragePercent` of all passive
    /// samples. The "你 80% 的人生发生在这片 N 公里" number.
    let radiusMeters: Double
    let coveragePercent: Int
    let topPlaces: [ReturnPlace]
    /// Distinct days with any passive history. Breadth of *time* lived.
    let totalActiveDays: Int
    /// Distinct ~1km cells ever touched. Breadth of *space* lived.
    let distinctPlaces: Int
    let reunion: ReunionMoment?

    static let empty = SmallWorldSummary(
        hasEnoughData: false,
        anchor: nil,
        radiusMeters: 0,
        coveragePercent: 80,
        topPlaces: [],
        totalActiveDays: 0,
        distinctPlaces: 0,
        reunion: nil
    )

    static func == (lhs: SmallWorldSummary, rhs: SmallWorldSummary) -> Bool {
        lhs.hasEnoughData == rhs.hasEnoughData &&
        lhs.anchor?.latitude == rhs.anchor?.latitude &&
        lhs.anchor?.longitude == rhs.anchor?.longitude &&
        lhs.radiusMeters == rhs.radiusMeters &&
        lhs.coveragePercent == rhs.coveragePercent &&
        lhs.topPlaces == rhs.topPlaces &&
        lhs.totalActiveDays == rhs.totalActiveDays &&
        lhs.distinctPlaces == rhs.distinctPlaces &&
        lhs.reunion == rhs.reunion
    }
}

enum SmallWorldBuilder {
    /// Minimum distinct active days before we'll claim to know someone's "small
    /// world". Below this, any radius/home claim is noise, not insight.
    static let minActiveDaysForInsight = 5

    /// Grid resolution for "a place". The shared `cellID` on passive points is
    /// ~1km — too coarse to tell home from the café two blocks away. We re-bucket
    /// on raw lat/lon at ~200m so returned-to places are street/block sized.
    static let placeGridDegrees: Double = 0.002

    static func build(
        points: [SmallWorldPoint],
        moodByDay: [String: String],
        referenceDate: Date,
        coveragePercent: Int = 80,
        topPlacesLimit: Int = 6,
        placeGridDegrees: Double = SmallWorldBuilder.placeGridDegrees
    ) -> SmallWorldSummary {
        guard !points.isEmpty else { return .empty }

        // --- Aggregate per cell -------------------------------------------------
        struct CellAgg {
            var sumLat = 0.0
            var sumLon = 0.0
            var count = 0
            var days = Set<String>()
        }
        var cells: [String: CellAgg] = [:]
        var activeDays = Set<String>()

        for p in points {
            activeDays.insert(p.dayKey)
            let key = placeKey(lat: p.lat, lon: p.lon, precision: placeGridDegrees)
            var agg = cells[key] ?? CellAgg()
            agg.sumLat += p.lat
            agg.sumLon += p.lon
            agg.count += 1
            agg.days.insert(p.dayKey)
            cells[key] = agg
        }

        let totalActiveDays = activeDays.count
        let distinctPlaces = cells.count

        guard totalActiveDays >= minActiveDaysForInsight else {
            return SmallWorldSummary(
                hasEnoughData: false,
                anchor: nil,
                radiusMeters: 0,
                coveragePercent: coveragePercent,
                topPlaces: [],
                totalActiveDays: totalActiveDays,
                distinctPlaces: distinctPlaces,
                reunion: nil
            )
        }

        // --- Rank places by distinct-days, then by time present -----------------
        // Returning often (many distinct days) is what makes a place *yours*.
        // Ties broken deterministically by point count then cellID so the result
        // is stable across runs (no Set/dictionary ordering leaking out).
        struct RankedCell {
            let cellID: String
            let center: CLLocationCoordinate2D
            let visitDays: Int
            let count: Int
        }
        let ranked: [RankedCell] = cells.map { id, agg in
            RankedCell(
                cellID: id,
                center: CLLocationCoordinate2D(
                    latitude: agg.sumLat / Double(agg.count),
                    longitude: agg.sumLon / Double(agg.count)
                ),
                visitDays: agg.days.count,
                count: agg.count
            )
        }
        .sorted { a, b in
            if a.visitDays != b.visitDays { return a.visitDays > b.visitDays }
            if a.count != b.count { return a.count > b.count }
            return a.cellID < b.cellID
        }

        let anchorCell = ranked[0]
        let anchor = anchorCell.center
        let anchorLoc = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)

        // --- Radius covering `coveragePercent` of all samples -------------------
        // Weighted by points (a proxy for time spent), measured from the anchor.
        // The closing N% — the far-flung trips — are intentionally left outside
        // the circle; that's the whole point of "your small world".
        let distances: [Double] = points
            .map { CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: anchorLoc) }
            .sorted()
        let radiusMeters = percentile(sorted: distances, percent: coveragePercent)

        // --- Top return places --------------------------------------------------
        let topPlaces: [ReturnPlace] = ranked.prefix(topPlacesLimit).map { c in
            ReturnPlace(
                cellID: c.cellID,
                center: c.center,
                visitDays: c.visitDays,
                totalPoints: c.count,
                metersFromAnchor: CLLocation(latitude: c.center.latitude, longitude: c.center.longitude)
                    .distance(from: anchorLoc)
            )
        }

        // --- 重逢: resurface one ordinary past day ------------------------------
        let reunion = pickReunion(points: points, moodByDay: moodByDay, referenceDate: referenceDate)

        return SmallWorldSummary(
            hasEnoughData: true,
            anchor: anchor,
            radiusMeters: radiusMeters,
            coveragePercent: coveragePercent,
            topPlaces: topPlaces,
            totalActiveDays: totalActiveDays,
            distinctPlaces: distinctPlaces,
            reunion: reunion
        )
    }

    /// Buckets a coordinate into a ~`precision`-degree grid cell. Floor-based so a
    /// point deterministically lands in one cell. (Trade-off: a place straddling a
    /// grid line can split across two cells; acceptable at 200m for a v1 — revisit
    /// with adjacency merging if return-day counts look diluted.)
    static func placeKey(lat: Double, lon: Double, precision: Double) -> String {
        let la = Int(floor(lat / precision))
        let lo = Int(floor(lon / precision))
        return "\(la):\(lo)"
    }

    /// Nearest-rank percentile on an already-sorted ascending array.
    static func percentile(sorted: [Double], percent: Int) -> Double {
        guard let last = sorted.last else { return 0 }
        guard sorted.count > 1 else { return last }
        let p = min(100, max(0, percent))
        // index of the value at/just above the p-th percentile
        let rank = Int(ceil(Double(p) / 100.0 * Double(sorted.count)))
        let idx = min(sorted.count - 1, max(0, rank - 1))
        return sorted[idx]
    }

    /// Prefer "this day, a year ago". Failing that, the oldest day far enough in
    /// the past to feel like a genuine look-back. Returns nil when nothing
    /// qualifies (too-new accounts get no fake nostalgia).
    static func pickReunion(
        points: [SmallWorldPoint],
        moodByDay: [String: String],
        referenceDate: Date
    ) -> ReunionMoment? {
        // Group points by day once.
        var byDay: [String: [SmallWorldPoint]] = [:]
        for p in points { byDay[p.dayKey, default: []].append(p) }
        guard !byDay.isEmpty else { return nil }

        let cal = Calendar.current
        let formatter = dayKeyFormatter()

        func parse(_ key: String) -> Date? { formatter.date(from: key) }

        // Candidate 1: within ±7 days of one year ago, the day with most points.
        if let yearAgo = cal.date(byAdding: .year, value: -1, to: cal.startOfDay(for: referenceDate)) {
            let window: TimeInterval = 7 * 24 * 3600
            let near = byDay.compactMap { key, pts -> (String, [SmallWorldPoint], TimeInterval)? in
                guard let d = parse(key) else { return nil }
                let delta = abs(d.timeIntervalSince(yearAgo))
                return delta <= window ? (key, pts, delta) : nil
            }
            if let best = near.sorted(by: { lhs, rhs in
                if lhs.1.count != rhs.1.count { return lhs.1.count > rhs.1.count }
                return lhs.2 < rhs.2
            }).first {
                return moment(forDayKey: best.0, points: best.1, moodByDay: moodByDay, formatter: formatter)
            }
        }

        // Candidate 2: oldest day at least 30 days old.
        let cutoff = referenceDate.addingTimeInterval(-30 * 24 * 3600)
        let oldEnough = byDay.compactMap { key, pts -> (String, [SmallWorldPoint], Date)? in
            guard let d = parse(key), d <= cutoff else { return nil }
            return (key, pts, d)
        }
        if let oldest = oldEnough.min(by: { $0.2 < $1.2 }) {
            return moment(forDayKey: oldest.0, points: oldest.1, moodByDay: moodByDay, formatter: formatter)
        }

        return nil
    }

    private static func moment(
        forDayKey key: String,
        points: [SmallWorldPoint],
        moodByDay: [String: String],
        formatter: DateFormatter
    ) -> ReunionMoment? {
        guard let date = formatter.date(from: key), !points.isEmpty else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: points.reduce(0) { $0 + $1.lat } / Double(points.count),
            longitude: points.reduce(0) { $0 + $1.lon } / Double(points.count)
        )
        return ReunionMoment(
            date: date,
            mood: moodByDay[key],
            center: center,
            pointCount: points.count
        )
    }

    /// Matches `LifelogStore` day keys (`yyyy-MM-dd`, local calendar).
    static func dayKeyFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
