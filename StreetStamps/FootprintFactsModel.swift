//
//  FootprintFactsModel.swift
//  StreetStamps
//
//  「你的小世界」事实卡片的纯逻辑层（最终版）。
//
//  Page shape:
//    · top    — world map lighting up visited countries (rendered elsewhere)
//    · middle — up to 4 concrete facts (this file selects them)
//    · bottom — 重逢: an old journey + that day's mood, tappable to its detail
//
//  Everything is journey-driven (JourneyStore + CityCache + current location +
//  mood). No passive-point loading. This layer is pure & store-independent so it
//  can be unit-tested without the app target; the caller pre-reduces heavy
//  coordinate scans into the compact inputs below (off the main thread). Names
//  for raw coordinates are resolved to district (区) level by the view.
//

import Foundation
import CoreLocation

// MARK: - Inputs (pre-reduced by the caller, off-main)

struct FootprintCityInput: Equatable {
    let cityKey: String
    let name: String
    let iso2: String?
    let anchor: CLLocationCoordinate2D?
    let firstVisit: Date?
    /// Start coordinate of this city's first journey — geocoded to 区 for "上次去新城市".
    let firstJourneyStart: CLLocationCoordinate2D?
    let journeyCount: Int

    static func == (l: FootprintCityInput, r: FootprintCityInput) -> Bool {
        l.cityKey == r.cityKey && l.name == r.name && l.iso2 == r.iso2 &&
        l.anchor?.latitude == r.anchor?.latitude && l.anchor?.longitude == r.anchor?.longitude &&
        l.firstVisit == r.firstVisit && l.journeyCount == r.journeyCount &&
        l.firstJourneyStart?.latitude == r.firstJourneyStart?.latitude &&
        l.firstJourneyStart?.longitude == r.firstJourneyStart?.longitude
    }
}

struct FootprintJourneyMeta: Equatable {
    let id: String
    let date: Date
    let cityKey: String
    let cityName: String?
    let countryISO2: String?
    let distanceMeters: Double
    let hasMemories: Bool
}

/// The single point, across all journeys, farthest from the user's home; the
/// journey that reached it. (Home = most-journeyed city; caller computes this.)
struct FarthestReachInput: Equatable {
    let journeyID: String
    let date: Date
    let point: CLLocationCoordinate2D

    static func == (l: FarthestReachInput, r: FarthestReachInput) -> Bool {
        l.journeyID == r.journeyID && l.date == r.date &&
        l.point.latitude == r.point.latitude && l.point.longitude == r.point.longitude
    }
}

/// A ~2km grid cell touched by journeys, with the day it was first reached.
struct VisitedAreaCell: Equatable {
    let center: CLLocationCoordinate2D
    let firstDate: Date
    let cityKey: String

    static func == (l: VisitedAreaCell, r: VisitedAreaCell) -> Bool {
        l.center.latitude == r.center.latitude && l.center.longitude == r.center.longitude &&
        l.firstDate == r.firstDate && l.cityKey == r.cityKey
    }
}

// MARK: - Outputs (facts). Coordinates here get 区-level names from the view.

struct LastNewCityFact: Equatable {
    let cityKey: String
    let cityName: String
    let daysAgo: Int
    /// Geocode this to a 区 for the "·徐汇区" suffix.
    let arrival: CLLocationCoordinate2D?

    static func == (l: LastNewCityFact, r: LastNewCityFact) -> Bool {
        l.cityKey == r.cityKey && l.cityName == r.cityName && l.daysAgo == r.daysAgo &&
        l.arrival?.latitude == r.arrival?.latitude && l.arrival?.longitude == r.arrival?.longitude
    }
}

struct FarthestReachFact: Equatable {
    let journeyID: String
    let daysAgo: Int
    let place: CLLocationCoordinate2D
    let metersFromNow: Double?

    static func == (l: FarthestReachFact, r: FarthestReachFact) -> Bool {
        l.journeyID == r.journeyID && l.daysAgo == r.daysAgo &&
        l.place.latitude == r.place.latitude && l.place.longitude == r.place.longitude &&
        l.metersFromNow == r.metersFromNow
    }
}

struct NewAreaFact: Equatable {
    let cityKey: String
    let cityName: String
    let daysAgo: Int
    let cell: CLLocationCoordinate2D

    static func == (l: NewAreaFact, r: NewAreaFact) -> Bool {
        l.cityKey == r.cityKey && l.cityName == r.cityName && l.daysAgo == r.daysAgo &&
        l.cell.latitude == r.cell.latitude && l.cell.longitude == r.cell.longitude
    }
}

struct ReunionRef: Equatable {
    let journeyID: String
    let date: Date
    let mood: String?
    let cityName: String?
}

/// "上一次在X探索" / "上一次去X" — a city + how long ago, no coordinates needed.
struct CityRecencyFact: Equatable {
    let cityKey: String
    let cityName: String
    let daysAgo: Int
}

struct FootprintFacts: Equatable {
    let visitedISO2: [String]
    let countryCount: Int
    let cityCount: Int
    let totalJourneys: Int
    let totalMeters: Double
    let lastNewCity: LastNewCityFact?
    let lastExploreCurrentCity: CityRecencyFact?
    let lastOtherCity: CityRecencyFact?
    let reunion: ReunionRef?

    /// No completed journeys yet → show the invitation state, not empty cards.
    var isNewUser: Bool { totalJourneys == 0 }

    static let empty = FootprintFacts(
        visitedISO2: [], countryCount: 0, cityCount: 0,
        totalJourneys: 0, totalMeters: 0,
        lastNewCity: nil, lastExploreCurrentCity: nil, lastOtherCity: nil, reunion: nil
    )
}

enum FootprintFactsBuilder {

    static func build(
        cities: [FootprintCityInput],
        journeys: [FootprintJourneyMeta],
        currentLocation: CLLocationCoordinate2D?,
        moodByDay: [String: String],
        referenceDate: Date
    ) -> FootprintFacts {

        // Countries = unified set across city cards AND journeys (country code +
        // city-key ISO) — the same breadth the globe uses, so the two counts match.
        var rawISOs: [String?] = cities.map { $0.iso2 }
        for j in journeys {
            rawISOs.append(j.countryISO2)
            rawISOs.append(isoFromCityKey(j.cityKey))
        }
        let iso = canonicalVisitedISO2(rawISOs)

        // 旅程总计 — works from journey #1.
        let totalJourneys = journeys.count
        let totalMeters = journeys.reduce(0) { $0 + $1.distanceMeters }

        // 上次去新城市 (+区) — most recently first-visited city.
        let lastNewCity: LastNewCityFact? = cities
            .compactMap { c -> (FootprintCityInput, Date)? in c.firstVisit.map { (c, $0) } }
            .max(by: { $0.1 < $1.1 })
            .map { (city, date) in
                LastNewCityFact(
                    cityKey: city.cityKey,
                    cityName: city.name,
                    daysAgo: daysBetween(date, referenceDate),
                    arrival: city.firstJourneyStart ?? city.anchor
                )
            }

        // 当前城市 = the tracked city nearest to where you are now (within range).
        let currentCityKey: String? = {
            guard let here = currentLocation else { return nil }
            let nearest = cities
                .compactMap { c -> (String, Double)? in c.anchor.map { (c.cityKey, meters(here, $0)) } }
                .min(by: { $0.1 < $1.1 })
            guard let (key, dist) = nearest, dist <= currentCityMaxMeters else { return nil }
            return key
        }()
        let cityNameFor: (String) -> String = { key in
            cities.first(where: { $0.cityKey == key })?.name
                ?? journeys.first(where: { $0.cityKey == key })?.cityName ?? ""
        }

        // 上一次在当前城市探索 — most recent journey in the current city.
        let exploreCurrent: CityRecencyFact? = currentCityKey.flatMap { key in
            journeys.filter { $0.cityKey == key }.max(by: { $0.date < $1.date }).map { j in
                CityRecencyFact(cityKey: key, cityName: cityNameFor(key), daysAgo: daysBetween(j.date, referenceDate))
            }
        }

        // 上一次去另一个城市 — most recent journey to a city other than the current.
        let otherCity: CityRecencyFact? = currentCityKey.flatMap { key in
            journeys.filter { $0.cityKey != key }.max(by: { $0.date < $1.date }).map { j in
                CityRecencyFact(cityKey: j.cityKey, cityName: j.cityName ?? cityNameFor(j.cityKey),
                                daysAgo: daysBetween(j.date, referenceDate))
            }
        }

        return FootprintFacts(
            visitedISO2: iso,
            countryCount: iso.count,
            cityCount: cities.count,
            totalJourneys: totalJourneys,
            totalMeters: totalMeters,
            lastNewCity: lastNewCity,
            lastExploreCurrentCity: exploreCurrent,
            lastOtherCity: otherCity,
            reunion: pickReunion(journeys: journeys, moodByDay: moodByDay, referenceDate: referenceDate)
        )
    }

    /// If the nearest tracked city is farther than this from the current location,
    /// we don't claim the user is "in" a tracked city.
    static let currentCityMaxMeters: Double = 60_000

    /// Politically required for the China market: Taiwan / Hong Kong / Macao are
    /// part of China — never a separate country on the map or in counts. Map their
    /// ISO codes onto CN everywhere the map is colored or countries are counted.
    static func unifiedISO(_ iso: String) -> String {
        switch iso.uppercased() {
        case "TW", "HK", "MO": return "CN"
        default: return iso.uppercased()
        }
    }

    /// ISO-3166-1 alpha-2 from a `"name|ISO2"` city key, or nil.
    static func isoFromCityKey(_ cityKey: String?) -> String? {
        guard let cityKey else { return nil }
        let raw = cityKey.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let iso = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return iso.count == 2 ? iso : nil
    }

    /// THE single source of truth for "which countries": normalize → keep 2-letter
    /// → China-unify (TW/HK/MO → CN) → dedup → sort. Both the footprint page and
    /// the globe must call this so their counts always agree.
    static func canonicalVisitedISO2(_ rawISOs: [String?]) -> [String] {
        var set = Set<String>()
        for raw in rawISOs {
            guard let r = raw?.trimmingCharacters(in: .whitespaces).uppercased(), r.count == 2 else { continue }
            set.insert(unifiedISO(r))
        }
        return set.sorted()
    }

    static func canonicalVisitedISO2(_ rawISOs: [String]) -> [String] {
        canonicalVisitedISO2(rawISOs.map { Optional($0) })
    }

    /// Distinct visited country codes (China-unified), most-explored first.
    static func orderedVisitedISO2(_ cities: [FootprintCityInput]) -> [String] {
        var counts: [String: Int] = [:]
        for c in cities {
            guard let raw = c.iso2?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { continue }
            counts[unifiedISO(raw), default: 0] += 1
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// 重逢: prefer a journey from "this day, a past year"; else the richest old
    /// journey. Memory-bearing journeys win ties (more to relive). nil if nothing
    /// old enough — a new user has nothing to reunite with.
    static func pickReunion(
        journeys: [FootprintJourneyMeta],
        moodByDay: [String: String],
        referenceDate: Date
    ) -> ReunionRef? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceDate)

        // Eligible = any journey from a day before today. Stable order so the
        // day-seeded pick is deterministic.
        let eligible = journeys
            .filter { cal.startOfDay(for: $0.date) < today }
            .sorted { $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id }
        guard !eligible.isEmpty else { return nil }

        // Prefer "this day in a past year" when such a journey exists — otherwise
        // rotate through ALL past journeys. Either way the choice is seeded by the
        // calendar day, so it CHANGES EVERY DAY but stays stable within a day.
        let refYear = cal.component(.year, from: referenceDate)
        let anniversary = eligible.filter {
            cal.component(.year, from: $0.date) < refYear && calendarDayDistance($0.date, referenceDate) <= 3
        }
        let pool = anniversary.isEmpty ? eligible : anniversary

        let dayNumber = Int(today.timeIntervalSince1970 / 86_400)
        let idx = ((dayNumber % pool.count) + pool.count) % pool.count
        let j = pool[idx]

        let fmt = dayKeyFormatter()
        return ReunionRef(journeyID: j.id, date: j.date, mood: moodByDay[fmt.string(from: j.date)], cityName: j.cityName)
    }

    // MARK: - Heavy coordinate scan (run off-main; pure & Sendable in/out)

    /// One journey reduced to plain double arrays — Sendable, safe to hand to a
    /// detached task (CLLocationCoordinate2D is not reliably Sendable).
    struct ScanJourneyInput: Sendable {
        let id: String
        let date: Date
        let cityKey: String
        let lats: [Double]
        let lons: [Double]
    }
    struct RawFarthest: Sendable { let journeyID: String; let date: Date; let lat: Double; let lon: Double }
    struct RawCell: Sendable { let lat: Double; let lon: Double; let firstDate: Date; let cityKey: String }

    /// ~2km grid for "new corner" detection.
    static let areaGridDegrees: Double = 0.02

    /// Scans every journey coordinate ONCE to find (a) the point farthest from
    /// home and (b) per-cell first-visit dates. The only O(total points) work in
    /// the feature; everything else is over cities/journeys/cells.
    static func scanJourneys(
        _ journeys: [ScanJourneyInput],
        home: (lat: Double, lon: Double)?,
        gridDegrees: Double = areaGridDegrees
    ) -> (farthest: RawFarthest?, cells: [RawCell]) {
        var bestFar: RawFarthest?
        var bestFarMeters = -1.0
        var cells: [String: RawCell] = [:]

        for j in journeys {
            let n = min(j.lats.count, j.lons.count)
            var i = 0
            while i < n {
                let lat = j.lats[i], lon = j.lons[i]

                if let home {
                    let d = haversine(home.lat, home.lon, lat, lon)
                    if d > bestFarMeters {
                        bestFarMeters = d
                        bestFar = RawFarthest(journeyID: j.id, date: j.date, lat: lat, lon: lon)
                    }
                }

                let la = (lat / gridDegrees).rounded(.down)
                let lo = (lon / gridDegrees).rounded(.down)
                let key = "\(Int(la)):\(Int(lo))"
                if let existing = cells[key] {
                    if j.date < existing.firstDate {
                        cells[key] = RawCell(lat: existing.lat, lon: existing.lon, firstDate: j.date, cityKey: j.cityKey)
                    }
                } else {
                    cells[key] = RawCell(
                        lat: (la + 0.5) * gridDegrees,
                        lon: (lo + 0.5) * gridDegrees,
                        firstDate: j.date,
                        cityKey: j.cityKey
                    )
                }
                i += 1
            }
        }
        return (bestFar, Array(cells.values))
    }

    static func haversine(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (bLat - aLat) * .pi / 180
        let dLon = (bLon - aLon) * .pi / 180
        let la1 = aLat * .pi / 180, la2 = bLat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * R * asin(min(1, sqrt(h)))
    }

    // MARK: - Pure helpers

    /// Great-circle distance in meters (plain doubles, no CLLocation allocation).
    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let la1 = a.latitude * .pi / 180
        let la2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * R * asin(min(1, sqrt(h)))
    }

    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to)).day ?? 0
    }

    /// Cyclic distance in days between two dates' (month, day), ignoring year.
    /// 0 = same calendar day; max ~182.
    static func calendarDayDistance(_ a: Date, _ b: Date) -> Int {
        let cal = Calendar.current
        let da = cal.ordinality(of: .day, in: .year, for: a) ?? 0
        let db = cal.ordinality(of: .day, in: .year, for: b) ?? 0
        let diff = abs(da - db)
        return min(diff, 365 - diff)
    }

    static func dayKeyFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
