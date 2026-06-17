//
//  FootprintView.swift
//  StreetStamps
//
//  「足迹」— a warm, non-competitive look back at the life you actually live.
//  Top: a static been-style world map (visited countries filled), tap → live globe.
//  A two-stat summary, then a TIMELINE of recent footprint moments, and a
//  featured 重逢 card (an old journey + that day's mood, tap → its memory detail).
//
//  All numbers come from `FootprintFactsBuilder` (pure, unit-verified). City &
//  district names are resolved lazily, localized, at 区 level. Journey-driven.
//

import SwiftUI
import CoreLocation

struct FootprintView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var lifelogStore: LifelogStore
    @ObservedObject private var languagePreference = LanguagePreference.shared

    @State private var facts: FootprintFacts = .empty
    @State private var isLoading = true
    /// Localized (city, district) keyed by a rounded coordinate key.
    @State private var places: [String: ReverseGeocodeService.PlaceParts] = [:]

    var body: some View {
        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                UnifiedNavigationHeader(
                    chrome: NavigationChrome(title: L10n.t("footprint_title"), leadingAccessory: .back, titleLevel: .secondary),
                    horizontalPadding: 16, topPadding: 8, bottomPadding: 8,
                    onLeadingTap: { dismiss() }
                ) {
                    Color.clear.frame(width: 44, height: 44) // symmetric → centered title
                }
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await reload() }
        .onChange(of: scenePhase) { _, phase in
            // Recompute on foreground so "X 天前" rolls over across days even if
            // the page was left open / the app stayed in memory overnight.
            if phase == .active { Task { await reload() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack { ProgressView() }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if facts.isNewUser {
            invitation
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    mapHero
                    if !timelineItems.isEmpty { timelineCard }
                    if let r = facts.reunion { reunionCard(r) }
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Map hero

    private var mapHero: some View {
        NavigationLink {
            GlobeViewScreen()
        } label: {
            VStack(spacing: 0) {
                WorldChoroplethView(visitedISO2: Set(facts.visitedISO2))
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(FigmaTheme.primary.opacity(0.05))

                HStack(spacing: 8) {
                    Text(String(format: L10n.t("fp_map_summary_format"), facts.totalJourneys, distanceText(facts.totalMeters)))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                    Spacer()
                    Text(L10n.t("fp_tap_globe"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(FigmaTheme.primary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timeline of recent moments

    private struct TLItem { let daysAgo: Int; let icon: String; let text: String }

    private var timelineItems: [TLItem] {
        var items: [TLItem] = []
        if let f = facts.lastExploreCurrentCity {
            items.append(TLItem(daysAgo: f.daysAgo, icon: "location.fill",
                                text: String(format: L10n.t("fp_tl_explore"), localizedCity(f.cityKey, fallback: f.cityName))))
        }
        if let f = facts.lastOtherCity {
            items.append(TLItem(daysAgo: f.daysAgo, icon: "airplane",
                                text: String(format: L10n.t("fp_tl_other"), localizedCity(f.cityKey, fallback: f.cityName))))
        }
        if let f = facts.lastNewCity {
            items.append(TLItem(daysAgo: f.daysAgo, icon: "sparkles",
                                text: String(format: L10n.t("fp_tl_newcity"), lastNewCityPlace(f))))
        }
        return items.sorted { $0.daysAgo < $1.daysAgo }
    }

    private var timelineCard: some View {
        let items = timelineItems
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.icon) { idx, item in
                timelineRow(item, isLast: idx == items.count - 1)
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 6)
    }

    private func timelineRow(_ item: TLItem, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(FigmaTheme.primary.opacity(0.18))
                        .frame(width: 2)
                        .padding(.top, 16)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                ZStack {
                    Circle().fill(FigmaTheme.primary.opacity(0.12)).frame(width: 32, height: 32)
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)
                }
            }
            .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(daysText(item.daysAgo))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.3)
                    .foregroundColor(FigmaTheme.primary)
                Text(item.text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 26)

            Spacer(minLength: 0)
        }
    }

    // MARK: - 重逢 (→ memory detail)

    private func reunionCard(_ r: ReunionRef) -> some View {
        NavigationLink {
            reunionDestination(r)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.t("smallworld_reunion_title"))
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundColor(FigmaTheme.secondary)
                    Spacer()
                    Text(reunionDateText(r.date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext)
                }
                HStack(spacing: 16) {
                    moodChip(r.mood)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(reunionCity(r) ?? L10n.t("unknown"))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(FigmaTheme.text)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(L10n.t("fp_reunion_lead"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(FigmaTheme.subtext.opacity(0.5))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(
                        colors: [FigmaTheme.secondary.opacity(0.14), FigmaTheme.secondary.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
        }
        .buttonStyle(.plain)
    }

    /// Clean mood chip: a soft tinted disc + a single emoji for known moods, or a
    /// quiet "looking-back" glyph when no mood was recorded that day.
    private func moodChip(_ mood: String?) -> some View {
        let tint = moodTint(mood)
        return ZStack {
            Circle().fill(tint.opacity(0.18))
            moodGlyph(mood)
        }
        .frame(width: 54, height: 54)
        .overlay(Circle().strokeBorder(tint.opacity(0.4), lineWidth: 1.5))
    }

    @ViewBuilder
    private func moodGlyph(_ mood: String?) -> some View {
        switch normalizedMood(mood) {
        case "happy":  moodAsset("Happy", emoji: "😊")
        case "notbad": moodAsset("notbad2", emoji: "🙂")
        case "sad":    moodAsset("Sad", emoji: "😔")
        default:
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(FigmaTheme.primary)
        }
    }

    /// The user's own custom mood artwork; emoji only as a safety fallback.
    @ViewBuilder
    private func moodAsset(_ name: String, emoji: String) -> some View {
        if UIImage(named: name) != nil {
            Image(name).resizable().renderingMode(.original).scaledToFit().frame(width: 32, height: 32)
        } else {
            Text(emoji).font(.system(size: 26))
        }
    }

    private func moodTint(_ mood: String?) -> Color {
        switch normalizedMood(mood) {
        case "happy":  return Color(red: 0.96, green: 0.69, blue: 0.34)
        case "notbad": return FigmaTheme.secondary
        case "sad":    return Color(red: 0.46, green: 0.60, blue: 0.78)
        default:       return FigmaTheme.primary
        }
    }

    @ViewBuilder
    private func reunionDestination(_ r: ReunionRef) -> some View {
        if let j = store.journeys.first(where: { $0.id == r.journeyID }) {
            JourneyMemoryDetailView(
                journey: j,
                memories: j.memories,
                cityName: reunionCity(r) ?? L10n.t("unknown"),
                countryName: countryName(j.countryISO2)
            )
            .environmentObject(store)
        } else {
            EmptyView()
        }
    }

    /// Localized city name for the reunion journey (override → CN mapping → English).
    private func reunionCity(_ r: ReunionRef) -> String? {
        if let j = store.journeys.first(where: { $0.id == r.journeyID }) {
            let key = j.stableCityKey ?? j.cityKey
            if let cached = cityCache.cachedCitiesByKey[key], !cached.displayTitle.isEmpty {
                return cached.displayTitle
            }
        }
        return r.cityName
    }

    // MARK: - New-user invitation

    private var invitation: some View {
        VStack(spacing: 16) {
            WorldChoroplethView(visitedISO2: [])
                .opacity(0.5)
                .padding(.horizontal, 24)
            Text(L10n.t("fp_empty_title"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(FigmaTheme.text)
                .multilineTextAlignment(.center)
            Text(L10n.t("fp_empty_body"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(FigmaTheme.subtext)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(FigmaTheme.card)
    }

    // MARK: - Data

    private func reload() async {
        let completed = store.journeys.filter { $0.isCompleted }

        let metas: [FootprintJourneyMeta] = completed.map { j in
            .init(id: j.id, date: j.endTime ?? j.startTime ?? Date(),
                  cityKey: j.stableCityKey ?? j.cityKey, cityName: j.cityName,
                  countryISO2: j.countryISO2,
                  distanceMeters: j.distance, hasMemories: !j.memories.isEmpty)
        }

        var firstDate: [String: Date] = [:]
        var firstStart: [String: CLLocationCoordinate2D] = [:]
        var count: [String: Int] = [:]
        for j in completed {
            let key = j.stableCityKey ?? j.cityKey
            let d = j.endTime ?? j.startTime ?? Date()
            count[key, default: 0] += 1
            if firstDate[key] == nil || d < firstDate[key]! {
                firstDate[key] = d
                firstStart[key] = j.coordinates.first?.cl
            }
        }
        let cityInputs: [FootprintCityInput] = cityCache.cachedCities
            .filter { !($0.isTemporary ?? false) }
            .map { c in
                .init(cityKey: c.cityKey, name: c.name, iso2: c.countryISO2,
                      anchor: c.anchor?.cl, firstVisit: firstDate[c.cityKey],
                      firstJourneyStart: firstStart[c.cityKey],
                      journeyCount: count[c.cityKey] ?? c.journeyIds.count)
            }

        let mood = lifelogStore.snapshotMoodByDay()
        let current = LocationHub.shared.currentLocation?.coordinate
        let ref = Date()

        facts = FootprintFactsBuilder.build(
            cities: cityInputs, journeys: metas,
            currentLocation: current, moodByDay: mood, referenceDate: ref
        )
        isLoading = false
        await resolvePlaces()
    }

    /// Resolve localized city/district for the fact coordinates, spaced to clear
    /// the geocoder throttle. Best-effort; numbers carry meaning without names.
    private func resolvePlaces() async {
        let coords = [facts.lastNewCity?.arrival].compactMap { $0 }
        for c in coords where places[coordKey(c)] == nil {
            if let p = await ReverseGeocodeService.shared.localizedPlace(
                for: CLLocation(latitude: c.latitude, longitude: c.longitude)) {
                places[coordKey(c)] = p
            }
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
        }
    }

    // MARK: - Place composition (localized, deduped)

    private func parts(_ c: CLLocationCoordinate2D) -> ReverseGeocodeService.PlaceParts? { places[coordKey(c)] }

    /// Localized city name (override → CN mapping → English), instant — no geocode.
    private func localizedCity(_ cityKey: String, fallback: String) -> String {
        if let c = cityCache.cachedCitiesByKey[cityKey], !c.displayTitle.isEmpty { return c.displayTitle }
        return fallback
    }

    private func lastNewCityPlace(_ f: LastNewCityFact) -> String {
        let p = f.arrival.flatMap(parts)
        let city = localizedCity(f.cityKey, fallback: p?.city ?? f.cityName)
        if let d = p?.district, !d.isEmpty, d != city { return "\(city)·\(d)" }
        return city
    }

    // MARK: - Formatting

    private func coordKey(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.3f,%.3f", c.latitude, c.longitude)
    }

    private func daysText(_ days: Int) -> String {
        if days <= 0 { return L10n.t("fp_today") }
        if days == 1 { return L10n.t("fp_yesterday") }
        return String(format: L10n.t("fp_days_ago"), days)
    }

    private func distanceText(_ meters: Double) -> String {
        if meters < 1000 {
            let m = max(0, Int((meters / 50).rounded()) * 50)
            return String(format: L10n.t("unit_meters_format"), m)
        }
        let km = meters / 1000
        let v = km < 10 ? String(format: "%.1f", km) : String(format: "%.0f", km)
        return String(format: L10n.t("unit_km_format"), v)
    }

    private func reunionDateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = languagePreference.displayLocale
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func countryName(_ iso2: String?) -> String {
        guard let iso2, !iso2.isEmpty else { return "" }
        return languagePreference.displayLocale.localizedString(forRegionCode: iso2) ?? iso2
    }

    private func normalizedMood(_ mood: String?) -> String? {
        switch mood {
        case "Happy", "mood/Happy", "happy", "mood/happy", "😄", "🤩": return "happy"
        case "notbad2", "mood/notbad2", "notbad", "normal", "😐", "🙂": return "notbad"
        case "Sad", "mood/Sad", "sad", "mood/sad", "😢", "😭": return "sad"
        default: return nil
        }
    }
}
