//
//  JourneyMemoryNew.swift
//  StreetStamps
//
//  Redesigned Journey Memory UI:
//  - Screen 1: City list (collapsed), shows city name + country + memory count
//  - Screen 2: City expanded -> shows journeys with first memory preview
//  - Screen 3: Journey detail -> all memories in timeline format, editable
//

import Foundation
import SwiftUI
import UIKit
import CoreLocation
import MapKit
import MapboxMaps
import Turf
import Photos
import CommonCrypto

// MARK: - Route Thumbnail Cache

/// Two-tier cache for per-journey route snapshot images.
/// Memory layer (NSCache) gives instant hits while the app is alive.
/// Disk layer (JPEG in Application Support, LRU-evicted at 100 MB) survives relaunch
/// so cold opens skip the 100–300 ms MKMapSnapshotter / Mapbox Snapshotter round-trip.
/// Key is just `journey.id` — we intentionally accept that a map-style switch
/// keeps the old thumbnail until `set(...)` overwrites it (matches pre-existing behavior).
private final class RouteThumbnailCache {
    static let shared = RouteThumbnailCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let directory: URL
    private let maxBytes: Int = 100 * 1024 * 1024
    private let ioQueue = DispatchQueue(label: "RouteThumbnailDiskCache.io", qos: .utility)

    init() {
        memoryCache.countLimit = 200
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("RouteThumbnailCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func get(_ journeyID: String) async -> UIImage? {
        if let img = memoryCache.object(forKey: journeyID as NSString) {
            return img
        }
        let path = filePath(for: journeyID)
        let img: UIImage? = await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            ioQueue.async {
                guard let data = FileManager.default.contents(atPath: path.path) else {
                    cont.resume(returning: nil)
                    return
                }
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date()], ofItemAtPath: path.path
                )
                cont.resume(returning: UIImage(data: data))
            }
        }
        if let img {
            memoryCache.setObject(img, forKey: journeyID as NSString)
        }
        return img
    }

    func set(_ image: UIImage, for journeyID: String) {
        memoryCache.setObject(image, forKey: journeyID as NSString)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let path = filePath(for: journeyID)
        ioQueue.async { [directory, maxBytes] in
            try? data.write(to: path, options: .atomic)
            Self.evictIfNeeded(directory: directory, maxBytes: maxBytes)
        }
    }

    private func filePath(for journeyID: String) -> URL {
        directory.appendingPathComponent(Self.sha256(journeyID))
    }

    private static func evictIfNeeded(directory: URL, maxBytes: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var entries: [(url: URL, size: Int, date: Date)] = []
        var totalSize = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let date = values.contentModificationDate ?? .distantPast
            entries.append((file, size, date))
            totalSize += size
        }

        guard totalSize > maxBytes else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries {
            guard totalSize > maxBytes else { break }
            try? fm.removeItem(at: entry.url)
            totalSize -= entry.size
        }
    }

    private static func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// =======================================================
// MARK: - Memory Filter State
// =======================================================

final class MemoryFilterState: ObservableObject {
    @Published var monthCursor = Date()
    @Published var selectedStartDate: Date? = nil
    @Published var selectedEndDate: Date? = nil
    @Published var selectedActivityTag: String? = nil

    var hasActiveFilters: Bool {
        selectedStartDate != nil || selectedActivityTag != nil
    }

    func clearAll() {
        selectedStartDate = nil
        selectedEndDate = nil
        selectedActivityTag = nil
    }
}

// =======================================================
// MARK: - Memory Filter Controls (Reusable)
// =======================================================

struct MemoryFilterControls: View {
    @ObservedObject var filterState: MemoryFilterState
    let availableActivityTags: [String]
    let allJourneys: [JourneyRoute]
    @State private var showFilterPopover = false

    var body: some View {
        HStack(spacing: 6) {
            if !availableActivityTags.isEmpty {
                Menu {
                    ForEach(availableActivityTags, id: \.self) { tag in
                        Button {
                            filterState.selectedActivityTag = (filterState.selectedActivityTag == tag) ? nil : tag
                        } label: {
                            HStack {
                                Text(tag)
                                if filterState.selectedActivityTag == tag {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    if filterState.selectedActivityTag != nil {
                        Divider()
                        Button(L10n.t("clear")) {
                            filterState.selectedActivityTag = nil
                        }
                    }
                } label: {
                    Image(systemName: filterState.selectedActivityTag == nil ? "tag" : "tag.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(filterState.selectedActivityTag == nil ? .black : FigmaTheme.primary)
                }
            }

            Button {
                showFilterPopover.toggle()
            } label: {
                Image(systemName: filterState.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(filterState.hasActiveFilters ? FigmaTheme.primary : .black)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFilterPopover, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                JourneyMemoryCalendarRangePopover(
                    monthCursor: $filterState.monthCursor,
                    selectedStartDate: $filterState.selectedStartDate,
                    selectedEndDate: $filterState.selectedEndDate,
                    journeys: allJourneys,
                    onRangeCompleted: {
                        showFilterPopover = false
                    },
                    onApply: {
                        showFilterPopover = false
                    },
                    onClear: {
                        filterState.selectedStartDate = nil
                        filterState.selectedEndDate = nil
                        showFilterPopover = false
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}

// =======================================================
// MARK: - Main Journey Memory View (Screen 1 & 2)
// =======================================================

struct JourneyMemoryMainView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @ObservedObject private var languagePreference = LanguagePreference.shared
    @Environment(\.dismiss) private var dismiss
    @State private var expandedCities: Set<String> = []
    @State private var showFilterPopover = false
    @ObservedObject private var filterState: MemoryFilterState
    /// Localized city display cache for this screen (cityKey -> localized title in current locale)
    @State private var localizedCityNameByKey: [String: String] = [:]
    @State private var cachedCityGroups: [CityGroupData] = []
    @State private var cachedLocalizationFingerprint: String = ""
    @State private var rebuildWorkItem: DispatchWorkItem?
    @State private var cachedSortedJourneys: [JourneyRoute] = []
    @State private var cachedActivityTags: [String] = []
    private let hideLeadingControl: Bool
    private let showHeader: Bool
    private let readOnly: Bool
    private let headerTitle: String?
    private let emptyTitleKey: String
    private let emptySubtitleKey: String
    private let friendLoadout: RobotLoadout?
    var onSelectJourney: ((JourneyMemoryDetailDestination) -> Void)?

    init(
        hideLeadingControl: Bool = false,
        showHeader: Bool = true,
        readOnly: Bool = false,
        headerTitle: String? = nil,
        emptyTitleKey: String = "no_memories_yet",
        emptySubtitleKey: String = "memory_empty_desc",
        filterState: MemoryFilterState? = nil,
        friendLoadout: RobotLoadout? = nil,
        onSelectJourney: ((JourneyMemoryDetailDestination) -> Void)? = nil
    ) {
        self.hideLeadingControl = hideLeadingControl
        self.showHeader = showHeader
        self.readOnly = readOnly
        self.headerTitle = headerTitle
        self.emptyTitleKey = emptyTitleKey
        self.emptySubtitleKey = emptySubtitleKey
        self.filterState = filterState ?? MemoryFilterState()
        self.friendLoadout = friendLoadout
        self.onSelectJourney = onSelectJourney
    }

    /// Cached sorted journeys — rebuilt by refreshSortedJourneys() on data change,
    /// instead of O(n log n) re-sort on every body evaluate.
    private var allMemoryJourneys: [JourneyRoute] { cachedSortedJourneys }

    private var availableActivityTags: [String] { cachedActivityTags }

    private func refreshSortedJourneys() {
        cachedSortedJourneys = store.journeys
            .sorted { ($0.endTime ?? $0.startTime ?? .distantPast) > ($1.endTime ?? $1.startTime ?? .distantPast) }
        let tags = cachedSortedJourneys.compactMap { j -> String? in
            let tag = (j.activityTag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return tag.isEmpty ? nil : tag
        }
        cachedActivityTags = Array(Set(tags)).sorted()
    }

    private var filteredMemoryJourneys: [JourneyRoute] {
        var result = allMemoryJourneys

        if let startDate = filterState.selectedStartDate {
            let cal = Calendar.current
            let start = cal.startOfDay(for: startDate)
            let upperBase = filterState.selectedEndDate ?? startDate
            let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: upperBase)) ?? upperBase
            result = result.filter { j in
                guard let date = j.endTime ?? j.startTime else { return false }
                return date >= start && date < endExclusive
            }
        }

        if let tag = filterState.selectedActivityTag {
            result = result.filter { j in
                let jTag = (j.activityTag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return jTag == tag
            }
        }

        return result
    }

    var body: some View {
        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                if showHeader {
                    headerView
                }
                
                // Content
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(cityGroups, id: \.cityKey) { city in
                            CitySection(
                                city: city,
                                isExpanded: expandedCities.contains(city.cityKey),
                                readOnly: readOnly,
                                friendLoadout: friendLoadout,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        if expandedCities.contains(city.cityKey) {
                                            expandedCities.remove(city.cityKey)
                                        } else {
                                            expandedCities.insert(city.cityKey)
                                        }
                                    }
                                },
                                onSelectJourney: { destination in
                                    onSelectJourney?(destination)
                                }
                            )
                            .environmentObject(store)
                            .environmentObject(sessionStore)
                        }
                        
                        if cityGroups.isEmpty {
                            emptyState
                                .padding(.top, 60)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if JourneyMemoryMainLoadPolicy.shouldLoadOnAppear(hasLoaded: store.hasLoaded) {
                store.load()
            }
            onboardingGuide.advance(.openMemory)
            refreshSortedJourneys()
            cachedLocalizationFingerprint = rebuildLocalizationFingerprint()
            rebuildCityGroups()
        }
        .onChange(of: store.journeys.count) { _, _ in
            cachedLocalizationFingerprint = rebuildLocalizationFingerprint()
            scheduleRebuild()
        }
        .onChange(of: store.metadataRevision) { _, _ in
            scheduleRebuild()
        }
        .onChange(of: localizedCityNameByKey) { _, _ in
            scheduleRebuild()
        }
        .onChange(of: filterState.selectedStartDate) { _, _ in
            scheduleRebuild()
        }
        .onChange(of: filterState.selectedEndDate) { _, _ in
            scheduleRebuild()
        }
        .onChange(of: filterState.selectedActivityTag) { _, _ in
            scheduleRebuild()
        }
        // Keep city names localized to current language (do NOT rely on persisted English titles).
        .task(id: localizationFingerprint) {
            await refreshCityLocalizations()
        }
    }

    /// A stable-ish fingerprint to re-run localization when journey list changes.
    private var localizationFingerprint: String {
        cachedLocalizationFingerprint
    }

    private func rebuildLocalizationFingerprint() -> String {
        let lang = languagePreference.currentLanguage ?? "sys"
        let journeyPart = allMemoryJourneys
            .map { "\($0.id)|\($0.startCityKey ?? $0.cityKey)" }
            .joined(separator: ",")
        return "\(lang)|\(journeyPart)"
    }

    private func buildCachedCitiesByKey() -> [String: CachedCity] {
        cityCache.cachedCitiesByKey
    }

    /// Fetch localized city titles for the current locale, keyed by the *start city*.
    private func refreshCityLocalizations() async {
        await MainActor.run { localizedCityNameByKey = [:] }
        let journeys = allMemoryJourneys
        let citiesByKey = buildCachedCitiesByKey()

        // cityKey -> sample start coordinate
        var coordByKey: [String: CLLocationCoordinate2D] = [:]
        for j in journeys {
            let key = (j.startCityKey ?? j.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key != "Unknown|" else { continue }
            if coordByKey[key] == nil, let start = j.startCoordinate, start.isValid {
                coordByKey[key] = start
            }
        }

        // Phase 1: resolve all cached titles instantly (no geocode needed)
        var needsGeocode: [(key: String, coord: CLLocationCoordinate2D)] = []
        var resolvedBatch: [String: String] = [:]

        for (key, coord) in coordByKey {
            if let cachedCity = citiesByKey[key] {
                let title = cachedCity.displayTitle
                if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolvedBatch[key] = title
                    continue
                }
            }

            let locale = LanguagePreference.shared.displayLocale
            if let cached = CityNameTranslationCache.shared.cachedName(cityKey: key, localeID: locale.identifier),
               !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolvedBatch[key] = cached
                continue
            }

            needsGeocode.append((key: key, coord: coord))
        }

        if !resolvedBatch.isEmpty {
            await MainActor.run {
                for (k, v) in resolvedBatch { localizedCityNameByKey[k] = v }
            }
        }

        // Phase 2: geocode remaining keys (still serial due to CLGeocoder rate limits)
        let locale = LanguagePreference.shared.displayLocale
        for item in needsGeocode {
            let level = citiesByKey[item.key]?.identityLevel
                ?? CityPlacemarkResolver.inferIdentityLevel(cityKey: item.key, iso2: item.key.components(separatedBy: "|").last)
            if let title = await CityNameTranslationCache.shared.translate(cityKey: item.key, anchor: item.coord, level: level, locale: locale),
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { localizedCityNameByKey[item.key] = title }
            }
        }
    }

    // MARK: - Header
    
    private var headerView: some View {
        UnifiedTabPageHeader(title: resolvedHeaderTitle, titleLevel: .secondary, horizontalPadding: 20, topPadding: 14, bottomPadding: 12) {
            if hideLeadingControl {
                Color.clear
            } else {
                AppBackButton(foreground: .black)
            }
        } trailing: {
            MemoryFilterControls(
                filterState: filterState,
                availableActivityTags: availableActivityTags,
                allJourneys: allMemoryJourneys
            )
        }
    }

    private var resolvedHeaderTitle: String {
        let trimmed = headerTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.t("memories_title") : trimmed
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: FriendSharedEmptyStateStyle.verticalSpacing) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.4))
            
            Text(L10n.key(emptyTitleKey))
                .font(.system(size: FriendSharedEmptyStateStyle.titleFontSize, weight: .semibold))
                .foregroundColor(.black)
            
            Text(L10n.key(emptySubtitleKey))
                .font(.system(size: FriendSharedEmptyStateStyle.subtitleFontSize))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Data Grouping

    private var cityGroups: [CityGroupData] {
        cachedCityGroups
    }

    /// Coalesce rapid-fire onChange triggers into a single rebuild.
    private func scheduleRebuild() {
        rebuildWorkItem?.cancel()
        let item = DispatchWorkItem { [self] in
            refreshSortedJourneys()
            rebuildCityGroups()
        }
        rebuildWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func rebuildCityGroups() {
        let citiesByKey = buildCachedCitiesByKey()
        let journeys = filteredMemoryJourneys
        let journeyById = Dictionary(journeys.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

        // cityKey -> (journeyId -> [memories])
        var buckets: [String: [String: [JourneyMemory]]] = [:]
        var nameForKey: [String: String] = [:]
        var countryForKey: [String: String] = [:]

        for j in journeys {
            let key = (j.startCityKey ?? j.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)

            buckets[key, default: [:]][j.id] = j.memories

            if nameForKey[key] == nil {
                let fallbackTitle: String
                if let localized = localizedCityNameByKey[key], !localized.isEmpty {
                    fallbackTitle = localized
                } else {
                    fallbackTitle = JourneyCityNamePresentation.title(
                        for: j,
                        localizedCityNameByKey: localizedCityNameByKey,
                        cachedCitiesByKey: citiesByKey
                    )
                }
                nameForKey[key] = cityOnly(
                    CityDisplayResolver.title(for: key, fallbackTitle: fallbackTitle)
                )
            }

            if countryForKey[key] == nil {
                if let iso2 = CityDisplayResolver.iso2(from: key) {
                    countryForKey[key] = countryName(from: iso2)
                }
            }
        }

        var groups: [CityGroupData] = buckets.compactMap { key, memsByJourney in
            let js: [JourneyRoute] = memsByJourney.keys
                .compactMap { journeyById[$0] }
                .sorted(by: { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) })

            return CityGroupData(
                cityKey: key,
                cityName: nameForKey[key] ?? L10n.t("unknown"),
                countryName: countryForKey[key] ?? "",
                journeys: js,
                memoriesByJourney: memsByJourney
            )
        }

        groups.sort(by: { $0.cityName < $1.cityName })
        cachedCityGroups = groups
    }

    
    private func countryName(from iso2: String) -> String {
        let locale = LanguagePreference.shared.displayLocale
        return locale.localizedString(forRegionCode: iso2) ?? iso2
    }

    /// Journey Memory list shows city only (no country) even if the raw name contains ", Country".
    private func cityOnly(_ raw: String) -> String {
        let normalized = raw.replacingOccurrences(of: "，", with: ",")
        let first = normalized.split(separator: ",").first.map(String.init) ?? normalized
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct JourneyMemoryCalendarDay: Identifiable {
    let id = UUID()
    let date: Date?
    let number: Int

    /// Generates calendar day items for the month containing `monthDate`.
    /// Shared by JourneyMemoryCalendarRangePopover and MiniJourneyCalendar.
    static func daysForMonth(_ monthDate: Date) -> [JourneyMemoryCalendarDay] {
        let cal = Calendar.current
        guard
            let monthInterval = cal.dateInterval(of: .month, for: monthDate),
            let monthFirstWeek = cal.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let monthLastWeek = cal.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else { return [] }

        var cursor = monthFirstWeek.start
        var out: [JourneyMemoryCalendarDay] = []
        while cursor < monthLastWeek.end {
            let isInMonth = cal.isDate(cursor, equalTo: monthDate, toGranularity: .month)
            let n = cal.component(.day, from: cursor)
            out.append(JourneyMemoryCalendarDay(date: isInMonth ? cursor : nil, number: n))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }
}

struct JourneyMemoryCalendarRangePopover: View {
    @Binding var monthCursor: Date
    @Binding var selectedStartDate: Date?
    @Binding var selectedEndDate: Date?

    let journeys: [JourneyRoute]
    let onRangeCompleted: () -> Void
    let onApply: () -> Void
    let onClear: () -> Void

    private var panelMonthTitle: String {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMMM yyyy"
        return df.string(from: monthCursor).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("date_range"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.black)

            HStack(spacing: 18) {
                Button {
                    monthCursor = Calendar.current.date(byAdding: .month, value: -1, to: monthCursor) ?? monthCursor
                } label: {
                    circleChevron("chevron.left")
                }

                Text(panelMonthTitle)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.2)

                Button {
                    monthCursor = Calendar.current.date(byAdding: .month, value: 1, to: monthCursor) ?? monthCursor
                } label: {
                    circleChevron("chevron.right")
                }
            }

            monthGrid

            HStack(spacing: 8) {
                Button(L10n.t("clear")) {
                    onClear()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.78))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color.black.opacity(0.08))
                .clipShape(Capsule())

                Button(L10n.t("apply")) {
                    onApply()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color.black)
                .clipShape(Capsule())
                .disabled(selectedStartDate == nil)
                .opacity(selectedStartDate == nil ? 0.45 : 1.0)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(width: 292)
        .background(Color.white)
    }

    private var monthGrid: some View {
        let days = calendarDays()
        let weekday = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

        return VStack(spacing: 8) {
            HStack {
                ForEach(weekday, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.black.opacity(0.3))
                        .frame(maxWidth: .infinity)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.id) { day in
                    if let date = day.date {
                        let inRange = isInSelectedRange(date)
                        let isBoundary = isRangeBoundary(date)
                        let hasJourney = hasJourney(on: date)

                        Button {
                            selectDate(date)
                        } label: {
                            Text("\(day.number)")
                                .font(.system(size: 14, weight: isBoundary ? .bold : .medium))
                                .foregroundColor(dayTextColor(hasJourney: hasJourney, inRange: inRange, isBoundary: isBoundary))
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(dayBackground(inRange: inRange, isBoundary: isBoundary))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(height: 34)
                    }
                }
            }
        }
    }

    private func selectDate(_ date: Date) {
        let cal = Calendar.current
        let normalized = cal.startOfDay(for: date)

        if selectedStartDate == nil || selectedEndDate != nil {
            selectedStartDate = normalized
            selectedEndDate = nil
            return
        }

        guard let start = selectedStartDate else { return }
        if normalized < start {
            selectedEndDate = start
            selectedStartDate = normalized
        } else {
            selectedEndDate = normalized
        }
        onRangeCompleted()
    }

    private func isInSelectedRange(_ date: Date) -> Bool {
        let cal = Calendar.current
        guard let start = selectedStartDate else { return false }
        let end = selectedEndDate ?? start
        let day = cal.startOfDay(for: date)
        return day >= min(start, end) && day <= max(start, end)
    }

    private func isRangeBoundary(_ date: Date) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        if let start = selectedStartDate, cal.isDate(day, inSameDayAs: start) { return true }
        if let end = selectedEndDate, cal.isDate(day, inSameDayAs: end) { return true }
        return false
    }

    private func hasJourney(on date: Date) -> Bool {
        let cal = Calendar.current
        return journeys.contains {
            guard let d = $0.endTime ?? $0.startTime else { return false }
            return cal.isDate(d, inSameDayAs: date)
        }
    }

    private func dayTextColor(hasJourney: Bool, inRange: Bool, isBoundary: Bool) -> Color {
        if inRange || isBoundary { return .black }
        return hasJourney ? .black : Color.black.opacity(0.18)
    }

    @ViewBuilder
    private func dayBackground(inRange: Bool, isBoundary: Bool) -> some View {
        if isBoundary {
            Color.black.opacity(0.15)
        } else if inRange {
            Color.black.opacity(0.08)
        } else {
            Color.clear
        }
    }

    private func circleChevron(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.black)
            .frame(width: 30, height: 30)
            .background(Color.black.opacity(0.06))
            .clipShape(Circle())
    }

    private func calendarDays() -> [JourneyMemoryCalendarDay] {
        JourneyMemoryCalendarDay.daysForMonth(monthCursor)
    }
}

// =======================================================
// MARK: - Swipe back enabler (keep interactive pop when nav bar is hidden)
// =======================================================
// MARK: - City Group Data Model
// =======================================================

struct CityGroupData: Identifiable {
    var id: String { cityKey }
    let cityKey: String
    let cityName: String
    let countryName: String
    let journeys: [JourneyRoute]
    let memoriesByJourney: [String: [JourneyMemory]]
    
    var totalMemories: Int {
        memoriesByJourney.values.reduce(0) { $0 + $1.count }
    }
    
    var displayName: String {
        // Journey Memory list only shows city name (no country), per UI spec.
        return cityName.uppercased()
    }
}

// =======================================================
// MARK: - City Section (Expandable)
// =======================================================

private struct CitySection: View {
    let city: CityGroupData
    let isExpanded: Bool
    let readOnly: Bool
    let friendLoadout: RobotLoadout?
    let onToggle: () -> Void
    let onSelectJourney: (JourneyMemoryDetailDestination) -> Void

    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    
    var body: some View {
        VStack(spacing: 0) {
            // City Header (tap anywhere on the header row)
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(city.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.black)

                        let entryCount = city.journeys.count
                        Text(entryCount == 1 ? String(format: L10n.t("entry_count_singular"), locale: Locale.current, entryCount) : String(format: L10n.t("entry_count_plural"), locale: Locale.current, entryCount))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.black.opacity(0.45))
                            .tracking(0.8)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .background(Color.black.opacity(0.08))

                VStack(spacing: 0) {
                    ForEach(Array(city.journeys.enumerated()), id: \.element.id) { index, journey in
                        let memories = city.memoriesByJourney[journey.id] ?? []

                        Button {
                            onSelectJourney(JourneyMemoryDetailDestination(
                                journey: journey,
                                memories: memories,
                                cityName: city.cityName,
                                countryName: city.countryName,
                                readOnly: readOnly,
                                friendLoadout: friendLoadout
                            ))
                        } label: {
                            JourneyEntryRow(
                                journey: journey,
                                memories: memories
                            )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < city.journeys.count - 1 {
                            Divider()
                                .padding(.horizontal, 18)
                                .background(Color.black.opacity(0.08))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
        .figmaSurfaceCard(radius: 32)
        .padding(.horizontal, 24)
    }
}

// =======================================================
// MARK: - Journey Entry Row (in expanded city)
// =======================================================

private struct JourneyEntryRow: View {
    let journey: JourneyRoute
    let memories: [JourneyMemory]
    
    private var journeyDate: String {
        let d = journey.startTime ?? memories.map(\.timestamp).min() ?? Date()
        return JourneyMemoryDatePresentation.journeyDateString(for: d)
    }
    
    private var accessoryItems: [JourneyEntryAccessoryPresentation.Item] {
        JourneyEntryAccessoryPresentation.items(
            journey: journey,
            memories: memories
        )
    }

    private var previewText: String {
        JourneyEntryPreviewText.make(journey: journey, memories: memories)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(FigmaTheme.primary)
                        .frame(width: 8, height: 8)

                    Text(journeyDate)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                }

                Text(previewText)
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.8))
                    .lineSpacing(3)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !accessoryItems.isEmpty {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(accessoryItems) { item in
                        JourneyEntryAccessoryView(item: item)
                    }
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 16)
    }
}

enum JourneyEntryAccessoryPresentation {
    struct Item: Identifiable {
        let id: String
        let icon: String
        let text: String?
        let tint: Color
    }

    static func items(journey: JourneyRoute, memories: [JourneyMemory]) -> [Item] {
        var items: [Item] = []

        // Only show the "好友可见" badge once the backend publish has been confirmed (sharedAt set).
        if journey.visibility == .friendsOnly, journey.sharedAt != nil {
            items.append(
                Item(
                id: "visibility",
                icon: visibilityIcon(for: journey.visibility),
                text: journey.visibility.localizedTitle,
                tint: visibilityTint(for: journey.visibility)
            )
            )
        }

        if hasAnyPhoto(journey: journey, memories: memories) {
            items.append(
                Item(
                    id: "photos",
                    icon: "photo.fill",
                    text: nil,
                    tint: FigmaTheme.primary.opacity(0.9)
                )
            )
        }

        return items
    }

    static func hasAnyPhoto(journey: JourneyRoute, memories: [JourneyMemory]) -> Bool {
        if !journey.overallMemoryImagePaths.isEmpty {
            return true
        }

        return memories.contains { !$0.imagePaths.isEmpty || !$0.remoteImageURLs.isEmpty }
    }

    private static func visibilityIcon(for visibility: JourneyVisibility) -> String {
        switch visibility {
        case .private:
            return "lock.fill"
        case .friendsOnly:
            return "person.2.fill"
        case .public:
            return "globe"
        }
    }

    private static func visibilityTint(for visibility: JourneyVisibility) -> Color {
        switch visibility {
        case .private:
            return FigmaTheme.subtext
        case .friendsOnly:
            return UITheme.accent
        case .public:
            return FigmaTheme.primary
        }
    }
}

private struct JourneyEntryAccessoryView: View {
    let item: JourneyEntryAccessoryPresentation.Item

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: item.icon)
                .font(.system(size: 11, weight: .semibold))

            if let text = item.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundColor(item.tint)
    }
}

enum JourneyEntryPreviewText {
    static func make(journey: JourneyRoute, memories: [JourneyMemory]) -> String {
        let journeyTitle = (journey.customTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !journeyTitle.isEmpty {
            return journeyTitle
        }

        let overallMemory = (journey.overallMemory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let firstMemoryBody = memories
            .sorted(by: { $0.timestamp < $1.timestamp })
            .compactMap { memory -> String? in
                let notes = memory.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                return notes.isEmpty ? nil : notes
            }
            .first ?? ""

        let parts = [overallMemory, firstMemoryBody].filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: "\n")
        }

        return L10n.t("tap_to_view_memories")
    }
}

// =======================================================
// MARK: - Journey Memory Detail View (Screen 3)
// =======================================================

struct JourneyMemoryDetailView: View {
    let journey: JourneyRoute
    let memories: [JourneyMemory]
    let cityName: String
    let countryName: String
    let readOnly: Bool
    let friendLoadout: RobotLoadout?

    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var publishStore: JourneyPublishStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // 默认只读；点右上角 Edit 才进入编辑（避免 TextEditor 一直占用焦点导致键盘下不去）
    @State private var isEditing: Bool = false

    // 编辑草稿 + 用于取消的快照
    @State private var draftMemories: [JourneyMemory] = []
    @State private var snapshotBeforeEdit: [JourneyMemory] = []
    @State private var draftJourneyTitle: String = ""
    @State private var snapshotJourneyTitleBeforeEdit: String = ""
    @State private var draftOverallMemory: String = ""
    @State private var snapshotOverallMemoryBeforeEdit: String = ""
    @State private var draftOverallMemoryImagePaths: [String] = []
    @State private var snapshotOverallMemoryImagePathsBeforeEdit: [String] = []
    @State private var draftOverallMemoryRemoteImageURLs: [String] = []
    @State private var snapshotOverallMemoryRemoteImageURLsBeforeEdit: [String] = []
    @State private var showRepublishConfirmation = false

    // Which memory's text field is focused (used to keep caret visible in the outer ScrollView).
    @FocusState private var focusedMemoryID: String?
    
    
    // Share / Export
    @State private var shareImage: UIImage? = nil
    @State private var shareItem: ShareImageItem? = nil
    @State private var routeThumbnail: UIImage? = nil

    @State private var showDeleteAllConfirm = false
    @State private var showDeleteJourneyConfirm = false
    @State private var showPrivacySheet = false
    // Photo / Camera (edit mode)
    @State private var activePhotoFlow: PhotoInputMode? = nil
    @State private var activePhotoTarget: ActivePhotoTarget? = nil
    @State private var mirrorSelfie: Bool = false
    @State private var showJourneyPhotoLimitToast = false
    @State private var sidebarHideToken = UUID().uuidString

    // Visibility
    @State private var activeJourneySheet: JourneyDetailSheetRoutePresentation? = nil
    @State private var showRouteDetail = false
    @State private var pendingVisibility: JourneyVisibility = .private
    @State private var likesCount: Int = 0
    @State private var likedByMe: Bool = false
    @State private var journeyLikers: [JourneyLiker] = []
    @State private var likersLoading = false
    @State private var likersErrorMessage: String? = nil
    @State private var showMessage = false
    @State private var messageText = ""
    @State private var showMembershipGate: MembershipGatedFeature? = nil
    @ObservedObject private var membership = MembershipStore.shared
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @State private var showMemoryHint = false

    init(
        journey: JourneyRoute,
        memories: [JourneyMemory],
        cityName: String,
        countryName: String,
        readOnly: Bool = false,
        friendLoadout: RobotLoadout? = nil
    ) {
        self.journey = journey
        self.memories = memories
        self.cityName = cityName
        self.countryName = countryName
        self.readOnly = readOnly
        self.friendLoadout = friendLoadout
    }

    private enum ActivePhotoTarget: Equatable {
        case overallMemory
        case memory(index: Int)
    }
    
    
    
    private var sortedMemories: [JourneyMemory] {
        memories.sorted(by: { $0.timestamp < $1.timestamp })
    }

    private var currentJourney: JourneyRoute {
        store.journeys.first(where: { $0.id == journey.id }) ?? journey
    }

    private var likesSheetDetents: Set<PresentationDetent> {
        let compactHeight = min(520, max(276, 194 + CGFloat(max(journeyLikers.count, 1)) * 56))
        return [.height(compactHeight), .large]
    }
    
    private var journeyDate: String {
        let d = journey.startTime ?? memories.map(\.timestamp).min() ?? Date()
        return JourneyMemoryDatePresentation.journeyDateString(for: d)
    }
    
    private var distanceText: String {
        let km = journey.distance / 1000.0
        return String(format: "%.1fkm", km)
    }
    
    private var durationText: String {
        guard let start = journey.startTime, let end = journey.endTime else {
            return "--:--:--"
        }
        let seconds = Int(end.timeIntervalSince(start))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    private var journeyDisplayTitle: String {
        // Prefer draft title (always up-to-date after save) over stale init param.
        if let t = JourneyMemoryDetailTitlePresentation.normalizedCustomTitle(from: draftJourneyTitle) {
            return t
        }
        if let t = JourneyMemoryDetailTitlePresentation.normalizedCustomTitle(from: journey.customTitle) {
            return t
        }
        return cityName
    }

    private var journeyActivityTag: String {
        (journey.activityTag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var journeyMetaSubtitle: String {
        let titleNorm = journeyDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cityNorm = cityName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let countryTrimmed = countryName.trimmingCharacters(in: .whitespacesAndNewlines)

        if titleNorm == cityNorm || countryTrimmed.isEmpty || countryTrimmed.lowercased() == cityNorm {
            return journeyDate
        }
        return "\(countryTrimmed.uppercased()) • \(journeyDate)"
    }
    
    // 用于 Copy / Export
    private var fullText: String {
        let header =
        """
        \(cityName), \(countryName)
        \(journeyDate)
        Distance: \(distanceText)   Duration: \(durationText)
        
        """
        
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        
        let body = draftMemories
            .sorted(by: { $0.timestamp < $1.timestamp })
            .map { mem in
                let t = tf.string(from: mem.timestamp).uppercased()
                let notes = mem.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = mem.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let text = !notes.isEmpty ? notes : (!title.isEmpty ? title : "-")
                return "\(t)\n\(text)"
            }
            .joined(separator: "\n\n")
        
        return header + body
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                FigmaTheme.background.ignoresSafeArea()
                    .onTapGesture {
                        endEditing()
                    }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerCard
                        overallMemorySection
                        memoriesTimeline
                    }
                    .padding(.bottom, 40)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    navBar
                }
            }
            .onChange(of: focusedMemoryID) { id in
                guard let id else { return }
                // Wait for keyboard/layout, then scroll.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .overlay(alignment: .bottom) {
            if showMemoryHint {
                ContextualHintBar(
                    icon: "info.circle",
                    message: L10n.t("tour_memory_combined"),
                    onDismiss: { dismissMemoryHint() }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showMemoryHint)
        .overlay(alignment: .bottom) {
            if showJourneyPhotoLimitToast {
                Text(String(format: L10n.t("journey_photo_limit_toast"), journeyPhotoLimit))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { showJourneyPhotoLimitToast = false }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showJourneyPhotoLimitToast)
        .task {
            if let cached = await RouteThumbnailCache.shared.get(journey.id) {
                routeThumbnail = cached
            } else {
                await generateRouteThumbnail()
            }
        }
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
            let uid = sessionStore.currentUserID
            loadLikesCount()
            if readOnly {
                draftMemories = sortedMemories
                snapshotBeforeEdit = sortedMemories
                draftJourneyTitle = journey.customTitle ?? ""
                snapshotJourneyTitleBeforeEdit = draftJourneyTitle
                draftOverallMemory = journey.overallMemory ?? ""
                snapshotOverallMemoryBeforeEdit = draftOverallMemory
                draftOverallMemoryImagePaths = journey.overallMemoryImagePaths
                snapshotOverallMemoryImagePathsBeforeEdit = journey.overallMemoryImagePaths
                draftOverallMemoryRemoteImageURLs = journey.overallMemoryRemoteImageURLs
                snapshotOverallMemoryRemoteImageURLsBeforeEdit = journey.overallMemoryRemoteImageURLs
                isEditing = false
                focusedMemoryID = nil
                return
            }
            // 1) Restore a saved editing session (tab switch / swipe away / relaunch)
            if JourneyMemoryDetailResumeStore.shouldResume(userID: uid, journeyID: journey.id),
               let saved = JourneyMemoryDetailDraftStore.load(userID: uid, journeyID: journey.id) {
                draftMemories = saved.memories
                snapshotBeforeEdit = saved.memories
                draftJourneyTitle = saved.journeyTitle
                snapshotJourneyTitleBeforeEdit = draftJourneyTitle
                draftOverallMemory = saved.overallMemory
                snapshotOverallMemoryBeforeEdit = draftOverallMemory
                draftOverallMemoryImagePaths = saved.overallMemoryImagePaths
                snapshotOverallMemoryImagePathsBeforeEdit = saved.overallMemoryImagePaths
                draftOverallMemoryRemoteImageURLs = saved.overallMemoryRemoteImageURLs
                snapshotOverallMemoryRemoteImageURLsBeforeEdit = saved.overallMemoryRemoteImageURLs
                isEditing = true
                focusedMemoryID = saved.focusedMemoryID
                JourneyMemoryDetailResumeStore.set(false, userID: uid, journeyID: journey.id)
            } else if draftMemories.isEmpty {
                // 2) Default read-only initialization
                draftMemories = sortedMemories
                snapshotBeforeEdit = sortedMemories
                draftJourneyTitle = journey.customTitle ?? ""
                snapshotJourneyTitleBeforeEdit = draftJourneyTitle
                draftOverallMemory = journey.overallMemory ?? ""
                snapshotOverallMemoryBeforeEdit = draftOverallMemory
                draftOverallMemoryImagePaths = journey.overallMemoryImagePaths
                snapshotOverallMemoryImagePathsBeforeEdit = journey.overallMemoryImagePaths
                draftOverallMemoryRemoteImageURLs = journey.overallMemoryRemoteImageURLs
                snapshotOverallMemoryRemoteImageURLsBeforeEdit = journey.overallMemoryRemoteImageURLs
            }
        }
        .onAppear { showMemoryHintIfNeeded() }
        .onDisappear {
            flow.popSidebarButtonHidden(token: sidebarHideToken)
            // ✅ If user leaves while editing (e.g. switches to another tab), keep editing state.
            if !readOnly {
                persistDetailDraftIfNeeded()
            }
        }
        .onChange(of: scenePhase) { phase in
            if !readOnly, phase != .active {
                // ✅ App going to background / may be killed: persist current draft.
                persistDetailDraftIfNeeded(force: true)
            }
        }
        .alert(L10n.t("delete_all_notes_title"), isPresented: $showDeleteAllConfirm) {
            Button(L10n.t("cancel"), role: .cancel) { }

            Button(L10n.t("delete"), role: .destructive) {
                deleteAllMemoriesForThisJourney()
            }
        } message: {
            Text(L10n.key("delete_all_notes_message"))
        }
        .alert(L10n.t("delete_journey_confirm_title"), isPresented: $showDeleteJourneyConfirm) {
            Button(L10n.t("cancel"), role: .cancel) { }

            Button(L10n.t("delete"), role: .destructive) {
                deleteJourney()
            }
        } message: {
            Text(L10n.key("delete_memory_confirm_message"))
        }
        .alert(L10n.t("prompt"), isPresented: $showMessage) {
            Button(L10n.t("ok"), role: .cancel) { }
        } message: {
            Text(messageText)
        }
        .confirmationDialog(
            L10n.t("edit_save_republish_title"),
            isPresented: $showRepublishConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.t("edit_save_republish_action")) {
                saveEditingAndRepublish()
            }
            Button(L10n.t("edit_save_local_only_action")) {
                saveEditing()
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        }
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: item.images)
        }
        .sheet(item: $showMembershipGate) { feature in
            MembershipGateView(feature: feature)
        }
        .sheet(item: $activeJourneySheet) { route in
            switch route {
            case .visibility:
                JourneyVisibilitySheet(
                    journey: currentJourney,
                    pendingVisibility: $pendingVisibility,
                    isSubmitting: publishStore.status.isSending,
                    onApply: applyVisibilityChange
                )
                .presentationBackground(FigmaTheme.background)
                .presentationCornerRadius(28)
                .presentationDetents([.height(352)])
                .presentationDragIndicator(.visible)
            case .likes:
                JourneyLikesSheet(
                    journey: currentJourney,
                    displayCityName: cityName,
                    likers: journeyLikers,
                    isLoading: likersLoading,
                    errorMessage: likersErrorMessage,
                    onRetry: loadJourneyLikers,
                    onEditVisibility: {
                        activeJourneySheet = nil
                        DispatchQueue.main.async {
                            presentVisibilitySheet()
                        }
                    }
                )
                .presentationBackground(FigmaTheme.background)
                .presentationCornerRadius(28)
                .presentationDetents(likesSheetDetents)
                .presentationDragIndicator(.visible)
            }
        }

        .sheet(isPresented: $showPrivacySheet) {
            JourneyPrivacyOptionsSheet(journey: currentJourney) { updatedOptions in
                updatePrivacyOptions(updatedOptions)
            }
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $activePhotoFlow) { mode in
            PhotoInputFlowView(
                mode: mode,
                onComplete: { edited in
                    activePhotoFlow = nil
                    appendImagesToActiveMemory(edited, writesToPhotoLibrary: false)
                },
                onCancel: {
                    activePhotoFlow = nil
                }
            )
        }
    }
    
    // MARK: - Header Card
    
    private var navBar: some View {
        HStack(spacing: 0) {
            AppBackButton(foreground: Color(red: 0.04, green: 0.04, blue: 0.04)) {
                if isEditing { cancelEditing() }
                dismiss()
            }
            Spacer()
            if !readOnly {
                HStack(spacing: 6) {
                    if isEditing {
                        Button {
                            cancelEditing()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .appMinTapTarget()
                        }
                        .buttonStyle(.plain)

                        Button {
                            handleSaveTap()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .appMinTapTarget()
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            beginEditing()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .appMinTapTarget()
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                UIPasteboard.general.string = fullText
                            } label: {
                                Label(L10n.t("copy_all"), systemImage: "doc.on.doc")
                            }

                            Button {
                                exportLongImage()
                            } label: {
                                Label(L10n.t("export_long_image"), systemImage: "square.and.arrow.up")
                            }

                            Button {
                                showPrivacySheet = true
                            } label: {
                                Label(L10n.t("privacy_toggle_title"), systemImage: "hand.raised.fill")
                            }

                            Divider()

                            Button(role: .destructive) {
                                showDeleteAllConfirm = true
                            } label: {
                                Label(L10n.t("delete_all_notes"), systemImage: "trash")
                            }

                            Button(role: .destructive) {
                                showDeleteJourneyConfirm = true
                            } label: {
                                Label(L10n.t("delete_journey_confirm_title"), systemImage: "trash.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.black)
                                .appMinTapTarget()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 16)
            }
        }
        .background(FigmaTheme.background)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField(
                        cityName,
                        text: $draftJourneyTitle,
                        prompt: Text(cityName)
                            .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51).opacity(0.72))
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .bold))
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                    .submitLabel(.done)
                } else {
                    Text(journeyDisplayTitle.uppercased())
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Text(journeyMetaSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))

                    if !journeyActivityTag.isEmpty {
                        Text(journeyActivityTag.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(FigmaTheme.secondary)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(FigmaTheme.secondary.opacity(0.12))
                            .clipShape(Capsule(style: .continuous))
                    }
                }

                if !readOnly && FeatureFlagStore.shared.socialEnabled {
                    visibilityStatusButton
                }
            }
            
            // Stats
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.key("lockscreen_distance"))
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
                    Text(distanceText)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.key("lockscreen_duration"))
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
                    Text(durationText)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                }
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 32)
        .background(FigmaTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.90, green: 0.91, blue: 0.92))
                .frame(height: 0.5)
        }
    }
    
    // MARK: - Memories Timeline
    
    private var memoriesTimeline: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(draftMemories.enumerated()), id: \.offset) { index, _ in
                if isEditing {
                    EditableMemoryTimelineItem(
                        memory: $draftMemories[index],
                        userID: sessionStore.currentUserID,
                        maxPhotos: membership.maxPhotosPerMemory,
                        isJourneyLimitReached: journeyTotalPhotoCount >= journeyPhotoLimit,
                        focusedMemoryID: $focusedMemoryID,
                        onOpenCamera: { openCamera(for: index) },
                        onOpenPhotoLibrary: { openPhotoLibrary(for: index) },
                        onPhotoLimitReached: { showPhotoLimitFeedback() }
                    )
                    .id("editable_memory_\(index)_\(draftMemories[index].id)")
                } else {
                    ReadOnlyMemoryTimelineItem(
                        memory: draftMemories[index],
                        userID: sessionStore.currentUserID
                     
                    )
                    .id("readonly_memory_\(index)_\(draftMemories[index].id)")
                }
                
                if index < draftMemories.count - 1 {
                    TimelineDivider()
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
    }

    private var overallMemorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showRouteDetail = true
            } label: {
                VStack(spacing: 0) {
                    // Map thumbnail with route overlay
                    if let thumb = routeThumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(UIColor.systemGray6))
                            .frame(height: 160)
                            .overlay {
                                ProgressView()
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FigmaTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showRouteDetail) {
                JourneyRouteDetailView(
                    journeyID: journey.id,
                    isReadOnly: readOnly,
                    headerTitle: cityName,
                    friendLoadout: friendLoadout
                )
                .environmentObject(store)
            }

            Text(L10n.t("overall_memory"))
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color(red: 0.60, green: 0.63, blue: 0.69))

            if isEditing {
                TextField(L10n.t("overall_memory_placeholder"), text: $draftOverallMemory, axis: .vertical)
                    .lineLimit(4...8)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.21, green: 0.26, blue: 0.32))
                    .padding(12)
                    .background(FigmaTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 12) {
                    Button {
                        if overallMemoryTotalPhotoCount >= photoLimit || journeyTotalPhotoCount >= journeyPhotoLimit {
                            showPhotoLimitFeedback()
                        } else {
                            openCameraForOverallMemory()
                        }
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Circle())
                            .appMinTapTarget()
                    }
                    .opacity(overallMemoryTotalPhotoCount >= photoLimit || journeyTotalPhotoCount >= journeyPhotoLimit ? 0.35 : 1.0)

                    Button {
                        if overallMemoryTotalPhotoCount >= photoLimit || journeyTotalPhotoCount >= journeyPhotoLimit {
                            showPhotoLimitFeedback()
                        } else {
                            openPhotoLibraryForOverallMemory()
                        }
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Circle())
                            .appMinTapTarget()
                    }
                    .opacity(overallMemoryTotalPhotoCount >= photoLimit || journeyTotalPhotoCount >= journeyPhotoLimit ? 0.35 : 1.0)

                    Text(String(format: L10n.t("photo_count"), overallMemoryTotalPhotoCount, photoLimit))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)

                    Spacer()
                }

                if !draftOverallMemoryImagePaths.isEmpty || !draftOverallMemoryRemoteImageURLs.isEmpty {
                    EditableMemoryImagesView(
                        imagePaths: $draftOverallMemoryImagePaths,
                        remoteImageURLs: $draftOverallMemoryRemoteImageURLs,
                        userID: sessionStore.currentUserID
                    )
                }
            } else {
                if !draftOverallMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(draftOverallMemory)
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.21, green: 0.26, blue: 0.32))
                        .lineSpacing(8.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !isEditing && (!draftOverallMemoryImagePaths.isEmpty || !draftOverallMemoryRemoteImageURLs.isEmpty) {
                MemoryImagesView(
                    imagePaths: draftOverallMemoryImagePaths,
                    remoteImageURLs: draftOverallMemoryImagePaths.isEmpty ? draftOverallMemoryRemoteImageURLs : [],
                    userID: sessionStore.currentUserID
                )
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, -8)
    }

    // MARK: - Edit controls

    private var overallMemoryTotalPhotoCount: Int {
        draftOverallMemoryImagePaths.isEmpty
            ? draftOverallMemoryRemoteImageURLs.count
            : draftOverallMemoryImagePaths.count
    }

    private func beginEditing() {
        snapshotBeforeEdit = draftMemories
        snapshotJourneyTitleBeforeEdit = draftJourneyTitle
        snapshotOverallMemoryBeforeEdit = draftOverallMemory
        snapshotOverallMemoryImagePathsBeforeEdit = draftOverallMemoryImagePaths
        snapshotOverallMemoryRemoteImageURLsBeforeEdit = draftOverallMemoryRemoteImageURLs
        isEditing = true
        // Enter edit mode without auto-focusing any field; user controls scroll position.
        focusedMemoryID = nil
    }

    private func cancelEditing() {
        // Clean up any NEW photos added during this editing session (not yet saved).
        let uid = sessionStore.currentUserID
        cleanupNewlyAddedPhotos(userID: uid)

        draftMemories = snapshotBeforeEdit
        draftJourneyTitle = snapshotJourneyTitleBeforeEdit
        draftOverallMemory = snapshotOverallMemoryBeforeEdit
        draftOverallMemoryImagePaths = snapshotOverallMemoryImagePathsBeforeEdit
        draftOverallMemoryRemoteImageURLs = snapshotOverallMemoryRemoteImageURLsBeforeEdit
        isEditing = false
        endEditing()

        // Cancel is an explicit discard: clear persisted draft.
        JourneyMemoryDetailDraftStore.clear(userID: uid, journeyID: journey.id)
        JourneyMemoryDetailResumeStore.set(false, userID: uid, journeyID: journey.id)
    }

    @MainActor
    private func handleSaveTap() {
        let action = JourneyPublishDirtyPolicy.evaluateSaveAction(
            visibility: currentJourney.visibility,
            snapshotMemories: snapshotBeforeEdit,
            draftMemories: draftMemories,
            snapshotTitle: snapshotJourneyTitleBeforeEdit,
            draftTitle: draftJourneyTitle,
            snapshotOverallMemory: snapshotOverallMemoryBeforeEdit,
            draftOverallMemory: draftOverallMemory,
            snapshotOverallMemoryImagePaths: snapshotOverallMemoryImagePathsBeforeEdit,
            draftOverallMemoryImagePaths: draftOverallMemoryImagePaths,
            snapshotOverallMemoryRemoteImageURLs: snapshotOverallMemoryRemoteImageURLsBeforeEdit,
            draftOverallMemoryRemoteImageURLs: draftOverallMemoryRemoteImageURLs
        )
        switch action {
        case .saveLocal:
            saveEditing()
        case .promptRepublish:
            showRepublishConfirmation = true
        }
    }

    @MainActor
    private func saveEditingAndRepublish() {
        guard membership.canRepublishEditedJourney else {
            showMembershipGate = .republishJourney
            return
        }
        saveEditing()
        guard let updated = store.journeys.first(where: { $0.id == journey.id }),
              updated.endTime != nil else { return }
        publishStore.publish(
            journey: updated,
            sessionStore: sessionStore,
            cityCache: cityCache,
            journeyStore: store
        )
    }

    @MainActor
    private func saveEditing() {
        guard var j = store.journeys.first(where: { $0.id == journey.id }) else {
            isEditing = false
            endEditing()
            return
        }

        // Deferred deletion: delete local files that were removed during editing.
        let uid = sessionStore.currentUserID
        deferredDeleteRemovedPhotos(userID: uid)

        j.memories = draftMemories
        j.customTitle = JourneyMemoryDetailTitlePresentation.normalizedCustomTitle(from: draftJourneyTitle)
        let trimmedOverall = draftOverallMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        j.overallMemory = trimmedOverall.isEmpty ? nil : trimmedOverall
        j.overallMemoryImagePaths = draftOverallMemoryImagePaths
        j.overallMemoryRemoteImageURLs = draftOverallMemoryRemoteImageURLs
        store.upsertSnapshotThrottled(j, coordCount: j.coordinates.count)
        store.flushPersist(journey: j)

        snapshotBeforeEdit = draftMemories
        draftJourneyTitle = j.customTitle ?? ""
        snapshotJourneyTitleBeforeEdit = draftJourneyTitle
        snapshotOverallMemoryBeforeEdit = draftOverallMemory
        snapshotOverallMemoryImagePathsBeforeEdit = draftOverallMemoryImagePaths
        snapshotOverallMemoryRemoteImageURLsBeforeEdit = draftOverallMemoryRemoteImageURLs
        isEditing = false
        endEditing()

        // Save is explicit: clear any persisted draft.
        JourneyMemoryDetailDraftStore.clear(userID: uid, journeyID: journey.id)
        JourneyMemoryDetailResumeStore.set(false, userID: uid, journeyID: journey.id)
    }

    private func updatePrivacyOptions(_ options: Set<JourneyPrivacyOption>) {
        guard var j = store.journeys.first(where: { $0.id == journey.id }) else { return }
        j.privacyOptions = options
        store.upsertSnapshotThrottled(j, coordCount: j.coordinates.count)
        store.flushPersist(journey: j)
        // Regenerate route thumbnail with updated privacy
        Task { await generateRouteThumbnail() }
    }

    /// Delete NEW local photo files that were added during editing but not saved (cancel).
    private func cleanupNewlyAddedPhotos(userID: String) {
        // Overall memory
        let newOverall = Set(draftOverallMemoryImagePaths).subtracting(Set(snapshotOverallMemoryImagePathsBeforeEdit))
        for path in newOverall {
            PhotoStore.delete(named: path, userID: userID)
        }
        // Per-memory
        let snapshotByID = Dictionary(snapshotBeforeEdit.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for draft in draftMemories {
            guard let old = snapshotByID[draft.id] else {
                // Entirely new memory — delete all its photos
                for path in draft.imagePaths { PhotoStore.delete(named: path, userID: userID) }
                continue
            }
            let newPaths = Set(draft.imagePaths).subtracting(Set(old.imagePaths))
            for path in newPaths { PhotoStore.delete(named: path, userID: userID) }
        }
    }

    /// Delete local photo files that were present before editing but removed by the user.
    private func deferredDeleteRemovedPhotos(userID: String) {
        // Overall memory images
        let removedOverall = Set(snapshotOverallMemoryImagePathsBeforeEdit).subtracting(Set(draftOverallMemoryImagePaths))
        for path in removedOverall {
            PhotoStore.delete(named: path, userID: userID)
        }
        // Per-memory images
        let snapshotByID = Dictionary(snapshotBeforeEdit.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for draft in draftMemories {
            guard let old = snapshotByID[draft.id] else { continue }
            let removed = Set(old.imagePaths).subtracting(Set(draft.imagePaths))
            for path in removed {
                PhotoStore.delete(named: path, userID: userID)
            }
        }
        // Memories that were entirely deleted during editing
        let draftIDs = Set(draftMemories.map(\.id))
        for old in snapshotBeforeEdit where !draftIDs.contains(old.id) {
            for path in old.imagePaths {
                PhotoStore.delete(named: path, userID: userID)
            }
        }
    }

    // MARK: - Draft persistence (Journey Memory Detail)
    private func persistDetailDraftIfNeeded(force: Bool = false) {
        let uid = sessionStore.currentUserID
        // If not editing, clear any stale draft rather than persisting a read-only snapshot.
        guard isEditing else {
            if force {
                JourneyMemoryDetailDraftStore.clear(userID: uid, journeyID: journey.id)
                JourneyMemoryDetailResumeStore.set(false, userID: uid, journeyID: journey.id)
            }
            return
        }
        let draft = JourneyMemoryDetailDraft(
            memories: draftMemories,
            focusedMemoryID: focusedMemoryID,
            journeyTitle: draftJourneyTitle,
            overallMemory: draftOverallMemory,
            overallMemoryImagePaths: draftOverallMemoryImagePaths,
            overallMemoryRemoteImageURLs: draftOverallMemoryRemoteImageURLs
        )
        JourneyMemoryDetailDraftStore.save(draft, userID: uid, journeyID: journey.id)
        JourneyMemoryDetailResumeStore.set(true, userID: uid, journeyID: journey.id)
    }

    // MARK: - Photo add helpers (edit mode)
    private var photoLimit: Int { membership.maxPhotosPerMemory }
    private var journeyPhotoLimit: Int { membership.maxJourneyPhotos }
    private var journeyTotalPhotoCount: Int {
        // imagePaths and remoteImageURLs are parallel arrays for the same photos;
        // count max, not sum, to avoid double-counting published photos.
        let overallCount = max(draftOverallMemoryImagePaths.count, draftOverallMemoryRemoteImageURLs.count)
        let memoriesCount = draftMemories.reduce(0) { $0 + max($1.imagePaths.count, $1.remoteImageURLs.count) }
        return overallCount + memoriesCount
    }

    private func remainingPhotoSlotsForActiveTarget() -> Int {
        let journeyRemaining = max(0, journeyPhotoLimit - journeyTotalPhotoCount)
        let perMemoryRemaining: Int
        switch activePhotoTarget {
        case .overallMemory:
            perMemoryRemaining = photoLimit - max(draftOverallMemoryImagePaths.count, draftOverallMemoryRemoteImageURLs.count)
        case .memory(let idx):
            guard draftMemories.indices.contains(idx) else { return min(journeyRemaining, photoLimit) }
            perMemoryRemaining = photoLimit - max(draftMemories[idx].imagePaths.count, draftMemories[idx].remoteImageURLs.count)
        case nil:
            return min(journeyRemaining, photoLimit)
        }
        return min(journeyRemaining, perMemoryRemaining)
    }

    private func showPhotoLimitFeedback() {
        if membership.tier == .free {
            showMembershipGate = .journeyPhotos
        } else {
            withAnimation { showJourneyPhotoLimitToast = true }
        }
    }

    private func openCamera(for index: Int) {
        activePhotoTarget = .memory(index: index)
        PhotoInputPresentationPolicy.launchPicker(dismissTextInput: {
            endEditing()
        }) {
            activePhotoFlow = .camera(mirrorSelfie: mirrorSelfie)
        }
    }

    private func openPhotoLibrary(for index: Int) {
        activePhotoTarget = .memory(index: index)
        PhotoInputPresentationPolicy.launchPicker(dismissTextInput: {
            endEditing()
        }) {
            activePhotoFlow = .library(selectionLimit: max(1, remainingPhotoSlotsForActiveTarget()))
        }
    }

    private func openCameraForOverallMemory() {
        activePhotoTarget = .overallMemory
        PhotoInputPresentationPolicy.launchPicker(dismissTextInput: {
            endEditing()
        }) {
            activePhotoFlow = .camera(mirrorSelfie: mirrorSelfie)
        }
    }

    private func openPhotoLibraryForOverallMemory() {
        activePhotoTarget = .overallMemory
        PhotoInputPresentationPolicy.launchPicker(dismissTextInput: {
            endEditing()
        }) {
            activePhotoFlow = .library(selectionLimit: max(1, remainingPhotoSlotsForActiveTarget()))
        }
    }

    private func appendImagesToActiveMemory(_ images: [UIImage], writesToPhotoLibrary: Bool) {
        guard let target = activePhotoTarget else { return }

        // Journey-level photo cap
        let journeyRemaining = max(0, journeyPhotoLimit - journeyTotalPhotoCount)
        if journeyRemaining <= 0 {
            if membership.tier == .free {
                showMembershipGate = .journeyPhotos
            } else {
                showJourneyPhotoLimitToast = true
            }
            return
        }

        let remainingSlots: Int
        switch target {
        case .overallMemory:
            remainingSlots = min(journeyRemaining, max(0, photoLimit - max(draftOverallMemoryImagePaths.count, draftOverallMemoryRemoteImageURLs.count)))
        case .memory(let idx):
            guard draftMemories.indices.contains(idx) else { return }
            remainingSlots = min(journeyRemaining, max(0, photoLimit - max(draftMemories[idx].imagePaths.count, draftMemories[idx].remoteImageURLs.count)))
        }

        let trimmed = Array(images.prefix(remainingSlots))
        let didTruncate = images.count > trimmed.count && images.count > journeyRemaining
        guard !trimmed.isEmpty else { return }
        switch target {
        case .overallMemory:
            for image in trimmed {
                if overallMemoryTotalPhotoCount >= photoLimit { break }
                if journeyTotalPhotoCount >= journeyPhotoLimit { break }
                if let filename = try? PhotoStore.saveJPEG(image, userID: sessionStore.currentUserID) {
                    draftOverallMemoryImagePaths.append(filename)
                }
            }
        case .memory(let idx):
            guard draftMemories.indices.contains(idx) else { return }
            for image in trimmed {
                if max(draftMemories[idx].imagePaths.count, draftMemories[idx].remoteImageURLs.count) >= photoLimit { break }
                if journeyTotalPhotoCount >= journeyPhotoLimit { break }
                if let filename = try? PhotoStore.saveJPEG(image, userID: sessionStore.currentUserID) {
                    draftMemories[idx].imagePaths.append(filename)
                }
            }
        }

        if didTruncate || journeyTotalPhotoCount >= journeyPhotoLimit {
            if membership.tier == .free {
                showMembershipGate = .journeyPhotos
            } else {
                showJourneyPhotoLimitToast = true
            }
        }

        guard writesToPhotoLibrary else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            for image in trimmed {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: nil)
            }
        }
    }

    private func endEditing() {
        endEditingGlobal()
    }
    
    @MainActor
    private func deleteAllMemoriesForThisJourney() {
        // 结束任何编辑态 & 收起键盘
        isEditing = false
        endEditing()

        // 清空 UI
        draftMemories.removeAll()

        // 写回 store
        guard var j = store.journeys.first(where: { $0.id == journey.id }) else { return }
        j.memories.removeAll()

        store.upsertSnapshotThrottled(j, coordCount: j.coordinates.count)
        store.flushPersist(journey: j) // 删除这种操作建议立即落盘

        snapshotBeforeEdit = draftMemories
    }
    @MainActor
    func exportLongImage() {
        guard #available(iOS 16.0, *) else { return }

        let exportWidth: CGFloat = 360
        let scale: CGFloat = 3
        // Keep each page under ~10000px to avoid overly long images and
        // stay well within GPU texture limits.
        let maxPixelHeight: CGFloat = 10_000
        let maxPointHeight = maxPixelHeight / scale

        let sorted = draftMemories.sorted { $0.timestamp < $1.timestamp }
        let loadout = AvatarLoadoutStore.load()
        let uid = sessionStore.currentUserID

        // Helper: build a page view for a given slice of memories
        func makePageView(
            memories: [JourneyMemory],
            showHeader: Bool,
            showRouteThumbnail: Bool,
            showOverallMemory: Bool,
            pageIndicator: String?
        ) -> some View {
            JourneyMemoryDetailExportSnapshotView(
                journey: journey,
                memories: memories,
                overallMemory: draftOverallMemory,
                cityName: cityName,
                countryName: countryName,
                journeyDate: journeyDate,
                distanceText: distanceText,
                durationText: durationText,
                userID: uid,
                routeThumbnail: routeThumbnail,
                loadout: loadout,
                showHeader: showHeader,
                showRouteThumbnail: showRouteThumbnail,
                showOverallMemory: showOverallMemory,
                pageIndicator: pageIndicator
            )
            .frame(width: exportWidth)
            .fixedSize(horizontal: false, vertical: true)
        }

        // Helper: probe a view's intrinsic point height at scale=1 (always safe)
        func probeHeight<V: View>(_ view: V) -> CGFloat {
            let r = ImageRenderer(content: view)
            r.scale = 1
            r.proposedSize = .init(width: exportWidth, height: nil)
            return r.uiImage?.size.height ?? 0
        }

        // Helper: render a page at target scale
        func renderPage<V: View>(_ view: V) -> UIImage? {
            let r = ImageRenderer(content: view)
            r.scale = scale
            r.proposedSize = .init(width: exportWidth, height: nil)
            r.isOpaque = true
            return r.uiImage
        }

        // --- Try single page first ---
        let fullView = makePageView(
            memories: sorted,
            showHeader: true,
            showRouteThumbnail: true,
            showOverallMemory: true,
            pageIndicator: nil
        )
        let totalHeight = probeHeight(fullView)

        if totalHeight <= maxPointHeight {
            if let img = renderPage(fullView) {
                shareItem = ShareImageItem(images: [img])
            }
            return
        }

        // --- Multi-page: split at memory boundaries ---
        // Measure the "chrome" height (header + thumb + overall + footer) without any memories
        let chromeHeight = probeHeight(makePageView(
            memories: [],
            showHeader: true,
            showRouteThumbnail: true,
            showOverallMemory: true,
            pageIndicator: "1/2" // placeholder for height estimation
        ))
        let continuationChromeHeight = probeHeight(makePageView(
            memories: [],
            showHeader: false,
            showRouteThumbnail: false,
            showOverallMemory: false,
            pageIndicator: "2/2"
        ))

        // Greedily pack memories into pages by measuring cumulative height
        var pages: [[JourneyMemory]] = []
        var currentPage: [JourneyMemory] = []
        var isFirstPage = true

        for mem in sorted {
            let candidate = currentPage + [mem]
            let chrome = isFirstPage ? chromeHeight : continuationChromeHeight
            // Measure this page with the candidate memories
            let pageView = makePageView(
                memories: candidate,
                showHeader: isFirstPage,
                showRouteThumbnail: isFirstPage,
                showOverallMemory: isFirstPage,
                pageIndicator: "X" // placeholder
            )
            let h = probeHeight(pageView)

            if h > maxPointHeight && !currentPage.isEmpty {
                // This memory pushes over the limit — finalize current page
                pages.append(currentPage)
                currentPage = [mem]
                isFirstPage = false
            } else {
                currentPage = candidate
            }
        }
        if !currentPage.isEmpty {
            pages.append(currentPage)
        }

        // Edge case: if only one page after splitting, no page indicators
        let totalPages = pages.count
        var images: [UIImage] = []

        for (i, pageMemories) in pages.enumerated() {
            let isFirst = (i == 0)
            let indicator = totalPages > 1 ? "\(i + 1)/\(totalPages)" : nil
            let pageView = makePageView(
                memories: pageMemories,
                showHeader: isFirst,
                showRouteThumbnail: isFirst,
                showOverallMemory: isFirst,
                pageIndicator: indicator
            )
            if let img = renderPage(pageView) {
                images.append(img)
            }
        }

        if !images.isEmpty {
            shareItem = ShareImageItem(images: images)
        }
    }

    @MainActor
    // MARK: - Memory Detail Hint Sequence

    private func showMemoryHintIfNeeded() {
        guard !readOnly, onboardingGuide.shouldShowHint(.memoryDetailTour) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showMemoryHint = true }
        }
    }

    private func dismissMemoryHint() {
        withAnimation { showMemoryHint = false }
        onboardingGuide.dismissHint(.memoryDetailTour)
    }

    private func generateRouteThumbnail() async {
        let j = currentJourney
        let rawCoords = j.coordinates
        let privacyCoords = j.privacyFilteredCoordinates(rawCoords)
        let coords = privacyCoords.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        guard coords.count >= 2 else {
            // No route points — generate a plain map tile from the city key center.
            await generateFallbackRouteThumbnail()
            return
        }

        let currentStyle = MapLayerStyle.current

        // Mapbox path: build WGS84 segments, render via Mapbox Snapshotter.
        if currentStyle.engine == .mapbox {
            if let img = await Self.makeMapboxJourneyThumbnail(
                journey: j,
                coordsWGS84: coords,
                style: currentStyle,
                hideLandmarks: j.shouldHideLandmarks
            ) {
                self.routeThumbnail = img
                RouteThumbnailCache.shared.set(img, for: journey.id)
            }
            return
        }

        // MapKit path.
        let built = RouteRenderingPipeline.buildSegments(
            .init(coordsWGS84: coords, applyGCJForChina: false, gapDistanceMeters: 2_200,
                  countryISO2: j.countryISO2, cityKey: j.stableCityKey),
            surface: .mapKit
        )
        let drawCoords: [CLLocationCoordinate2D] = built.segments.flatMap { $0.coords }
        guard drawCoords.count >= 2 else { return }

        var minLat: Double = drawCoords.map(\.latitude).min()!
        var maxLat: Double = drawCoords.map(\.latitude).max()!
        var minLon: Double = drawCoords.map(\.longitude).min()!
        var maxLon: Double = drawCoords.map(\.longitude).max()!
        let latPad: Double = max((maxLat - minLat) * 0.25, 0.002)
        let lonPad: Double = max((maxLon - minLon) * 0.25, 0.002)
        minLat -= latPad; maxLat += latPad; minLon -= lonPad; maxLon += lonPad
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0, longitude: (minLon + maxLon) / 2.0)
        let span = MKCoordinateSpan(latitudeDelta: maxLat - minLat, longitudeDelta: maxLon - minLon)
        let region = MKCoordinateRegion(center: center, span: span)

        let snapshotSize = CGSize(width: 400, height: 200)
        let isDark = currentStyle.isDarkStyle
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = snapshotSize
        options.scale = UIScreen.main.scale
        options.mapType = currentStyle.mapKitType
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: currentStyle.mapKitInterfaceStyle),
            UITraitCollection(displayScale: UIScreen.main.scale),
            UITraitCollection(activeAppearance: .active),
            UITraitCollection(userInterfaceLevel: .base)
        ])
        if j.shouldHideLandmarks {
            options.showsPointsOfInterest = false
        }

        do {
            let snap = try await MKMapSnapshotter(options: options).start()
            let img = UIGraphicsImageRenderer(size: snapshotSize).image { renderer in
                let base = snap.image
                if j.shouldHideLandmarks {
                    mapPrivacyBlurred(base, radius: 14).draw(at: .zero)
                } else {
                    base.draw(at: .zero)
                }
                RouteSnapshotDrawer.draw(
                    segments: built.segments,
                    isFlightLike: built.isFlightLike,
                    snapshot: snap,
                    ctx: renderer.cgContext,
                    coreColor: currentStyle.routeBaseColor.withAlphaComponent(isDark ? 0.78 : 1.0),
                    stroke: .init(coreWidth: 3.0),
                    glowColor: currentStyle.routeGlowColor,
                    isDarkMap: isDark
                )
            }
            self.routeThumbnail = img
            RouteThumbnailCache.shared.set(img, for: journey.id)
        } catch {
            print("Route thumbnail snapshot error:", error)
        }
    }

    // MARK: - Mapbox Journey Thumbnail

    nonisolated private static func makeMapboxJourneyThumbnail(
        journey: JourneyRoute,
        coordsWGS84: [CLLocationCoordinate2D],
        style: MapLayerStyle,
        hideLandmarks: Bool
    ) async -> UIImage? {
        let built = RouteRenderingPipeline.buildSegments(
            .init(coordsWGS84: coordsWGS84, applyGCJForChina: false, gapDistanceMeters: 2_200,
                  countryISO2: journey.countryISO2, cityKey: journey.stableCityKey),
            surface: .mapbox
        )
        let segments = built.segments
        let drawCoords = segments.flatMap { $0.coords }
        guard drawCoords.count >= 2 else { return nil }

        // Bounding box with padding.
        let lats = drawCoords.map(\.latitude)
        let lons = drawCoords.map(\.longitude)
        var minLat = lats.min()!, maxLat = lats.max()!
        var minLon = lons.min()!, maxLon = lons.max()!
        let latPad = max((maxLat - minLat) * 0.25, 0.002)
        let lonPad = max((maxLon - minLon) * 0.25, 0.002)
        minLat -= latPad; maxLat += latPad; minLon -= lonPad; maxLon += lonPad
        let sw = CLLocationCoordinate2D(latitude: minLat, longitude: minLon)
        let ne = CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)

        let snapshotSize = CGSize(width: 400, height: 200)
        let styleURI = StyleURI(rawValue: style.mapboxStyleURI) ?? .dark
        let isDark = style.isDarkStyle
        let baseColor = style.routeBaseColor
        let glowColor = style.routeGlowColor
        let isFlightLike = built.isFlightLike
        let coreWidth: Double = isFlightLike ? 5 : 3

        print("[JourneyThumb] ▶ Mapbox snapshot START journey=\(journey.id)")
        return await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                let snapOptions = MapSnapshotOptions(
                    size: snapshotSize,
                    pixelRatio: UIScreen.main.scale,
                    showsLogo: false,
                    showsAttribution: false
                )
                let snapshotter = MapboxMaps.Snapshotter(options: snapOptions)

                snapshotter.onNext(event: .styleLoaded) { [snapshotter] _ in
                    print("[JourneyThumb] ▶ styleLoaded fired")

                    // When hideLandmarks, skip adding route layers to the style —
                    // routes will be drawn via CoreGraphics AFTER blurring the base map.
                    if !hideLandmarks {
                        let routeSourceId = "jthumb-routes"
                        var src = GeoJSONSource(id: routeSourceId)
                        let feats: [Turf.Feature] = segments.compactMap { seg in
                            guard seg.coords.count >= 2 else { return nil }
                            var f = Turf.Feature(geometry: .lineString(Turf.LineString(seg.coords)))
                            f.properties = ["isGap": .init(booleanLiteral: seg.style == .dashed)]
                            return f
                        }
                        src.data = .featureCollection(Turf.FeatureCollection(features: feats))
                        try? snapshotter.addSource(src)

                        var glow = LineLayer(id: "jthumb-glow", source: routeSourceId)
                        glow.filter = Exp(.eq) { Exp(.get) { "isGap" }; false }
                        glow.lineColor = .constant(StyleColor(glowColor))
                        glow.lineCap = .constant(.round)
                        glow.lineJoin = .constant(.round)
                        glow.lineOpacity = .constant(isDark ? 0.30 : 0.25)
                        glow.lineWidth = .constant(coreWidth + 4)
                        glow.lineBlur = .constant(3.0)
                        try? snapshotter.addLayer(glow)

                        var main = LineLayer(id: "jthumb-main", source: routeSourceId)
                        main.filter = Exp(.eq) { Exp(.get) { "isGap" }; false }
                        main.lineColor = .constant(StyleColor(baseColor.withAlphaComponent(isDark ? 0.78 : 1.0)))
                        main.lineCap = .constant(.round)
                        main.lineJoin = .constant(.round)
                        main.lineOpacity = .constant(1.0)
                        main.lineWidth = .constant(coreWidth)
                        try? snapshotter.addLayer(main)

                        var dash = LineLayer(id: "jthumb-dash", source: routeSourceId)
                        dash.filter = Exp(.eq) { Exp(.get) { "isGap" }; true }
                        dash.lineColor = .constant(StyleColor(baseColor))
                        dash.lineCap = .constant(.round)
                        dash.lineJoin = .constant(.round)
                        dash.lineOpacity = .constant(0.5)
                        dash.lineDasharray = .constant([10, 10])
                        dash.lineWidth = .constant(coreWidth * 0.6)
                        try? snapshotter.addLayer(dash)
                    }

                    let cam = snapshotter.camera(
                        for: [sw, ne],
                        padding: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16),
                        bearing: 0, pitch: 0
                    )
                    snapshotter.setCamera(to: cam)

                    // When hideLandmarks: use overlayHandler to blur the base map,
                    // then draw routes on top so they stay crisp.
                    let overlayHandler: SnapshotOverlayHandler? = hideLandmarks ? { overlay in
                        guard let ctx = UIGraphicsGetCurrentContext() else { return }
                        let size = snapshotSize
                        // Capture the rendered base map, blur it, and redraw
                        if let baseCG = ctx.makeImage() {
                            let baseUI = UIImage(cgImage: baseCG, scale: UIScreen.main.scale, orientation: .up)
                            let blurred = mapPrivacyBlurred(baseUI, radius: 14)
                            ctx.clear(CGRect(origin: .zero, size: CGSize(width: baseCG.width, height: baseCG.height)))
                            blurred.draw(in: CGRect(origin: .zero, size: size))
                        }
                        // Draw routes via CoreGraphics on top of the blurred base
                        RouteSnapshotDrawer.draw(
                            segments: segments,
                            isFlightLike: isFlightLike,
                            pointForCoordinate: { overlay.pointForCoordinate($0) },
                            ctx: ctx,
                            coreColor: baseColor.withAlphaComponent(isDark ? 0.78 : 1.0),
                            stroke: .init(coreWidth: coreWidth),
                            glowColor: glowColor,
                            isDarkMap: isDark
                        )
                    } : nil

                    snapshotter.start(overlayHandler: overlayHandler) { [snapshotter] result in
                        _ = snapshotter
                        switch result {
                        case .success(let image):
                            print("[JourneyThumb] ▶ Mapbox snapshot SUCCESS")
                            cont.resume(returning: image)
                        case .failure(let error):
                            print("[JourneyThumb] ▶ Mapbox snapshot FAILED error=\(error)")
                            cont.resume(returning: nil)
                        }
                    }
                }

                snapshotter.styleURI = styleURI
            }
        }
    }

    @MainActor
    private func generateFallbackRouteThumbnail() async {
        guard let cityKey = journey.stableCityKey else { return }
        let parts = cityKey.split(separator: "|")
        guard parts.count >= 2 else { return }
        let cityName = String(parts[0])
        let countryISO2 = String(parts[1])

        let center: CLLocationCoordinate2D? = await withCheckedContinuation { cont in
            CLGeocoder().geocodeAddressString("\(cityName), \(countryISO2)") { placemarks, _ in
                cont.resume(returning: placemarks?.first?.location?.coordinate)
            }
        }

        guard let center, CLLocationCoordinate2DIsValid(center) else { return }

        let fallbackStyle = MapLayerStyle.current
        let snapshotSize = CGSize(width: 400, height: 200)

        // Mapbox fallback: plain map tile at city center.
        if fallbackStyle.engine == .mapbox {
            let styleURI = StyleURI(rawValue: fallbackStyle.mapboxStyleURI) ?? .dark
            let zoom = MapboxEngineView.Coordinator.altitudeToZoom(80_000, latitude: center.latitude)
            let img: UIImage? = await withCheckedContinuation { cont in
                DispatchQueue.main.async {
                    let snapOptions = MapSnapshotOptions(size: snapshotSize, pixelRatio: UIScreen.main.scale, showsLogo: false, showsAttribution: false)
                    let snapshotter = MapboxMaps.Snapshotter(options: snapOptions)
                    snapshotter.onNext(event: .styleLoaded) { [snapshotter] _ in
                        snapshotter.setCamera(to: CameraOptions(center: center, zoom: zoom))
                        snapshotter.start(overlayHandler: nil) { [snapshotter] result in
                            _ = snapshotter
                            switch result {
                            case .success(let image): cont.resume(returning: image)
                            case .failure: cont.resume(returning: nil)
                            }
                        }
                    }
                    snapshotter.styleURI = styleURI
                }
            }
            if let img {
                self.routeThumbnail = img
                RouteThumbnailCache.shared.set(img, for: journey.id)
            }
            return
        }

        // MapKit fallback.
        let mappedCenter = MapCoordAdapter.forMapKit(center, countryISO2: countryISO2, cityKey: cityKey)
        let region = MKCoordinateRegion(
            center: mappedCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = snapshotSize
        options.scale = UIScreen.main.scale
        options.mapType = fallbackStyle.mapKitType
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: fallbackStyle.mapKitInterfaceStyle),
            UITraitCollection(displayScale: UIScreen.main.scale),
            UITraitCollection(activeAppearance: .active),
            UITraitCollection(userInterfaceLevel: .base)
        ])

        do {
            let snap = try await MKMapSnapshotter(options: options).start()
            self.routeThumbnail = snap.image
            RouteThumbnailCache.shared.set(snap.image, for: journey.id)
        } catch {
            print("Fallback route thumbnail error:", error)
        }
    }

    /// True only when the journey has been confirmed published to friends (sharedAt set after backend success).
    private var isConfirmedFriendVisible: Bool {
        guard currentJourney.visibility == .friendsOnly else { return false }
        return currentJourney.sharedAt != nil
    }

    private var visibilityStatusButton: some View {
        Button {
            presentPrimaryJourneySheet()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isConfirmedFriendVisible ? "person.2.fill" : "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(isConfirmedFriendVisible ? currentJourney.visibility.localizedTitle : JourneyVisibility.private.localizedTitle)
                    .font(.system(size: 12, weight: .medium))
                if likesCount > 0 {
                    Text("•")
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(likesCount)")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundColor(isConfirmedFriendVisible ? UITheme.accent : FigmaTheme.subtext)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isConfirmedFriendVisible ? UITheme.accent.opacity(0.12) : Color.black.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func applyVisibilityChange() {
        guard !publishStore.status.isSending else { return }
        guard currentJourney.endTime != nil else { return }
        let target = pendingVisibility
        let journey = currentJourney
        // Compare against the *effective* visibility: unconfirmed friends-only
        // (sharedAt == nil) counts as private so the user can retry by picking
        // friends-only again without being blocked by the no-op guard.
        let effective: JourneyVisibility = (journey.sharedAt != nil) ? journey.visibility : .private
        guard target != effective else {
            activeJourneySheet = nil
            return
        }
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: effective,
            target: target,
            isLoggedIn: sessionStore.isLoggedIn,
            journeyDistance: journey.distance,
            memoryCount: journey.memories.count
        )
        guard decision.isAllowed else {
            activeJourneySheet = nil
            showVisibilityDeniedMessage(reason: decision.reason)
            return
        }
        var updated = journey
        updated.visibility = target
        // Clear sharedAt when going private so the button doesn't show green
        // if the user later switches back to friends-only before a new publish confirms.
        if target == .private { updated.sharedAt = nil }
        store.applyBulkCompletedUpdates([updated])
        activeJourneySheet = nil

        publishStore.publish(
            journey: updated,
            sessionStore: sessionStore,
            cityCache: cityCache,
            journeyStore: store,
            isExplicitVisibilityChange: true
        )
    }

    private func loadLikesCount() {
        guard sessionStore.isLoggedIn, let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        Task {
            do {
                let stats = try await BackendAPIClient.shared.fetchJourneyLikeStats(
                    token: token,
                    journeyIDs: [journey.id],
                    ownerUserID: sessionStore.accountUserID
                )
                await MainActor.run {
                    if let stat = stats[journey.id] {
                        likesCount = stat.likes
                        likedByMe = stat.likedByMe
                    }
                }
            } catch {}
        }
    }

    private func presentPrimaryJourneySheet() {
        switch JourneyDetailSheetRoutePresentation.primaryRoute(forLikesCount: likesCount) {
        case .visibility:
            presentVisibilitySheet()
        case .likes:
            pendingVisibility = currentJourney.visibility
            activeJourneySheet = .likes
            loadJourneyLikers()
        }
    }

    private func presentVisibilitySheet() {
        let journey = currentJourney
        guard JourneyVisibilityPolicy.canEditVisibility(
            current: journey.visibility,
            target: journey.visibility,
            isLoggedIn: sessionStore.isLoggedIn
        ) else {
            showVisibilityDeniedMessage(reason: .loginRequired)
            return
        }

        // Show the picker reflecting the *confirmed* state (sharedAt != nil).
        // An unconfirmed friends-only intent (persisted locally but never
        // successfully published) should be treated as private in the UI —
        // otherwise the picker lies about a status friends will never see.
        pendingVisibility = (journey.sharedAt != nil) ? journey.visibility : .private
        activeJourneySheet = .visibility
    }

    private func loadJourneyLikers() {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            journeyLikers = []
            likersErrorMessage = nil
            return
        }

        likersLoading = true
        likersErrorMessage = nil
        let journeyID = currentJourney.id

        Task {
            do {
                let ownerUserID = sessionStore.accountUserID ?? sessionStore.currentUserID
                let out: [JourneyLiker]
                do {
                    out = try await BackendAPIClient.shared.fetchJourneyLikers(
                        token: token,
                        ownerUserID: ownerUserID,
                        journeyID: journeyID
                    )
                } catch {
                    let all = try await BackendAPIClient.shared.fetchNotifications(token: token, unreadOnly: false)
                    out = JourneyLikesPresentation.likers(from: all, journeyID: journeyID)
                }

                await MainActor.run {
                    journeyLikers = out
                    likersErrorMessage = nil
                    likersLoading = false
                }
            } catch {
                await MainActor.run {
                    journeyLikers = []
                    likersErrorMessage = error.localizedDescription
                    likersLoading = false
                }
            }
        }
    }

    private func showVisibilityDeniedMessage(reason: JourneyVisibilityPolicy.DenialReason?) {
        if let reason {
            messageText = L10n.t(reason.localizationKey)
        } else {
            messageText = L10n.t("cannot_modify_journey_permission")
        }
        showMessage = true
    }

    private func deleteJourney() {
        store.deleteJourney(id: journey.id)
        dismiss()
    }

}



// =======================================================
// MARK: - Memory Timeline Item
// =======================================================
private struct ExportMemoryTimelineItem: View {
    let memory: JourneyMemory
    let userID: String
    let contentWidth: CGFloat

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: memory.timestamp).uppercased()
    }

    private var contentText: String? {
        let notes = memory.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { return notes }
        let title = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(timeText)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color(red: 0.60, green: 0.63, blue: 0.69))

            if !memory.imagePaths.isEmpty {
                SyncMemoryImagesView(
                    imagePaths: memory.imagePaths,
                    userID: userID,
                    contentWidth: contentWidth
                )
            }

            if let text = contentText {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.21, green: 0.26, blue: 0.32))
                    .lineSpacing(8.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Synchronous image loading for ImageRenderer export (async .task won't fire in ImageRenderer).
/// contentWidth must be passed explicitly — ImageRenderer's layout engine does not reliably
/// propagate frame(maxWidth: .infinity) proposals, so we bypass it with concrete dimensions.
///
/// Images are downscaled to match the exact export pixel width (contentWidth × rendererScale)
/// so there is zero quality loss in the final image, while keeping total memory bounded.
/// Without this, 12 full-res photos (~48MB each) would require ~576MB simultaneously,
/// causing Core Graphics bitmap allocation failure (black image).
private struct SyncMemoryImagesView: View {
    let imagePaths: [String]
    let userID: String
    let contentWidth: CGFloat
    /// Must match ImageRenderer.scale so downscale target = pixel-perfect for export.
    var rendererScale: CGFloat = 3

    private func loadExportImage(named filename: String) -> UIImage? {
        guard let full = PhotoStore.loadImage(named: filename, userID: userID) else { return nil }
        let targetPixel = contentWidth * rendererScale // 296 × 3 = 888px — exact 1:1 mapping
        return full.downscaled(maxPixel: targetPixel)
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(imagePaths, id: \.self) { path in
                if let img = loadExportImage(named: path) {
                    let ratio = img.size.height > 0 ? img.size.width / img.size.height : 4.0/3.0
                    let imgHeight = contentWidth / ratio
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: contentWidth, height: imgHeight)
                        .clipped()
                        .overlay(
                            Rectangle()
                                .inset(by: 0.5)
                                .stroke(
                                    Color(red: 0.90, green: 0.91, blue: 0.92),
                                    lineWidth: 0.5
                                )
                        )
                } else {
                    Color(red: 0.95, green: 0.95, blue: 0.95)
                        .frame(width: contentWidth, height: 140)
                }
            }
        }
    }
}

struct ReadOnlyMemoryTimelineItem: View {
    let memory: JourneyMemory
    let userID: String

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: memory.timestamp).uppercased()
    }

    private var contentText: String? {
        let notes = memory.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { return notes }
        let title = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Time
            Text(timeText)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color(red: 0.60, green: 0.63, blue: 0.69))

            // Images
            if !memory.imagePaths.isEmpty || !memory.remoteImageURLs.isEmpty {
                MemoryImagesView(
                    imagePaths: memory.imagePaths,
                    remoteImageURLs: memory.imagePaths.isEmpty ? memory.remoteImageURLs : [],
                    userID: userID
                )
            }

            // Text
            if let text = contentText {
                SelectableTextView(
                    text: text,
                    font: .systemFont(ofSize: 14),
                    textColor: UIColor(red: 0.21, green: 0.26, blue: 0.32, alpha: 1.0),
                    lineSpacing: 8.75
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PlainGrowingEditor: View {
    @Binding var text: String
    let focusKey: String
    let focusedMemoryID: FocusState<String?>.Binding

    var body: some View {
        TextField("", text: $text, axis: .vertical)
            .font(.system(size: 14))
            .foregroundColor(Color(red: 0.21, green: 0.26, blue: 0.32))
            .lineSpacing(8.75)
            .textFieldStyle(.plain)
            .autocorrectionDisabled(true)
            .focused(focusedMemoryID, equals: focusKey)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2) // 让点击区域舒服点
    }
}


private struct AsyncLocalImage: View {
    let path: String
    let userID: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay(
                        Rectangle()
                            .inset(by: 0.5)
                            .stroke(
                                Color(red: 0.90, green: 0.91, blue: 0.92),
                                lineWidth: 0.5
                            )
                    )
            } else {
                Color(red: 0.95, green: 0.95, blue: 0.95)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
            }
        }
        .task(id: path) {
            let uid = userID
            let p = path
            image = await Task.detached(priority: .userInitiated) {
                PhotoStore.loadImage(named: p, userID: uid)
            }.value
        }
    }
}

private struct MemoryImagesView: View {
    let imagePaths: [String]
    let remoteImageURLs: [String]
    let userID: String

    var body: some View {
        VStack(spacing: 12) {
            ForEach(imagePaths, id: \.self) { path in
                AsyncLocalImage(path: path, userID: userID)
            }
            ForEach(remoteImageURLs, id: \.self) { rawURL in
                if let url = URL(string: rawURL) {
                    CachedRemoteImage(url: url) { $0.resizable() } placeholder: {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                    } failure: {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.95, green: 0.95, blue: 0.95))
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                            .overlay {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.secondary)
                            }
                    }
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay(
                        Rectangle()
                            .inset(by: 0.5)
                            .stroke(
                                Color(red: 0.90, green: 0.91, blue: 0.92),
                                lineWidth: 0.5
                            )
                    )
                }
            }
        }
    }
}

private struct EditableMemoryImagesView: View {
    @Binding var imagePaths: [String]
    @Binding var remoteImageURLs: [String]
    let userID: String

    // Locked on appear: only show remote photos if there were no local photos when editing started.
    // Prevents remote photos from "popping in" when the last local photo is deleted.
    @State private var showRemote = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(imagePaths, id: \.self) { path in
                ZStack(alignment: .topTrailing) {
                    AsyncLocalImage(path: path, userID: userID)

                    Button {
                        // Deferred: only remove from array. Actual file deletion happens on save.
                        // Also remove the positionally-corresponding remoteImageURL so it doesn't
                        // resurface after save (imagePaths and remoteImageURLs are parallel arrays).
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            if let idx = imagePaths.firstIndex(of: path) {
                                imagePaths.remove(at: idx)
                                if idx < remoteImageURLs.count {
                                    remoteImageURLs.remove(at: idx)
                                }
                            } else {
                                imagePaths.removeAll(where: { $0 == path })
                            }
                        }
                    } label: {
                        editableImageDeleteButton
                    }
                    .buttonStyle(.plain)
                }
            }
            if showRemote {
            ForEach(remoteImageURLs, id: \.self) { rawURL in
                if let url = URL(string: rawURL) {
                    ZStack(alignment: .topTrailing) {
                        CachedRemoteImage(url: url) { $0.resizable() } placeholder: {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 140)
                        } failure: {
                            Color(red: 0.95, green: 0.95, blue: 0.95)
                                .frame(maxWidth: .infinity)
                                .frame(height: 140)
                        }
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .overlay(
                            Rectangle()
                                .inset(by: 0.5)
                                .stroke(Color(red: 0.90, green: 0.91, blue: 0.92), lineWidth: 0.5)
                        )

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                remoteImageURLs.removeAll(where: { $0 == rawURL })
                            }
                        } label: {
                            editableImageDeleteButton
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            } // end if showRemote
        }
        .onAppear {
            showRemote = imagePaths.isEmpty && !remoteImageURLs.isEmpty
        }
    }

    private var editableImageDeleteButton: some View {
        Image(systemName: "xmark.circle.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(Color.black.opacity(0.65))
            .background(
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 26, height: 26)
            )
            .appMinTapTarget()
    }
}


private struct EditableMemoryTimelineItem: View {
    @Binding var memory: JourneyMemory
    let userID: String
    let maxPhotos: Int
    let isJourneyLimitReached: Bool
    let focusedMemoryID: FocusState<String?>.Binding
    let onOpenCamera: () -> Void
    let onOpenPhotoLibrary: () -> Void
    var onPhotoLimitReached: (() -> Void)? = nil

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: memory.timestamp).uppercased()
    }

    private var totalPhotoCount: Int {
        memory.imagePaths.isEmpty
            ? memory.remoteImageURLs.count
            : memory.imagePaths.count
    }

    private var isPhotoLimitReached: Bool {
        totalPhotoCount >= maxPhotos || isJourneyLimitReached
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(timeText)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color(red: 0.60, green: 0.63, blue: 0.69))

            HStack(spacing: 12) {
                Button {
                    if isPhotoLimitReached {
                        onPhotoLimitReached?()
                    } else {
                        onOpenCamera()
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .opacity(isPhotoLimitReached ? 0.35 : 1.0)

                Button {
                    if isPhotoLimitReached {
                        onPhotoLimitReached?()
                    } else {
                        onOpenPhotoLibrary()
                    }
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .opacity(isPhotoLimitReached ? 0.35 : 1.0)

                Text(String(format: L10n.t("photo_count"), totalPhotoCount, maxPhotos))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)

                Spacer()
            }
            .padding(.top, 2)

            if !memory.imagePaths.isEmpty || !memory.remoteImageURLs.isEmpty {
                EditableMemoryImagesView(
                    imagePaths: $memory.imagePaths,
                    remoteImageURLs: $memory.remoteImageURLs,
                    userID: userID
                )
            }

            PlainGrowingEditor(text: $memory.notes, focusKey: memory.id, focusedMemoryID: focusedMemoryID)
        }
        .padding(.vertical, 16)
    }
}


private struct ShareImageItem: Identifiable {
    let id = UUID()
    let images: [UIImage]
}

struct JourneyMemoryDetailExportPresentation {
    let overallMemoryText: String
    let overallMemoryImagePaths: [String]

    init(overallMemory: String?, overallMemoryImagePaths: [String]) {
        self.overallMemoryText = overallMemory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.overallMemoryImagePaths = overallMemoryImagePaths
    }

    var shouldShowOverallMemory: Bool {
        !overallMemoryText.isEmpty || !overallMemoryImagePaths.isEmpty
    }
}

enum JourneyMemoryDatePresentation {
    static func journeyDateString(
        for date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM dd, yyyy"
        return formatter.string(from: date).uppercased()
    }
}

enum JourneyMemoryDetailTitlePresentation {
    static func normalizedCustomTitle(from rawTitle: String?) -> String? {
        guard let trimmed = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func exportTitle(customTitle: String?, fallbackCityName: String) -> String {
        normalizedCustomTitle(from: customTitle) ?? fallbackCityName
    }
}

// =======================================================
// MARK: - Timeline Divider
// =======================================================

private struct TimelineDivider: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(red: 0.82, green: 0.84, blue: 0.86))
                .frame(height: 0.5)

            Text("◆")
                .font(.system(size: 12))
                .tracking(1.2)
                .foregroundColor(Color(red: 0.60, green: 0.63, blue: 0.69))
                .padding(.horizontal, 10)
                .background(FigmaTheme.background)
        }
        .frame(height: 1)
        .padding(.vertical, 24)
    }
}

// =======================================================
// MARK: - Time Label (for timeline)
// =======================================================

private struct TimeLabel: View {
    let time: String
    
    var body: some View {
        Text(time)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }
}
import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.permittedArrowDirections = []
            pop.sourceView = UIView()
            pop.sourceRect = .zero
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct JourneyMemoryDetailExportSnapshotView: View {
    let journey: JourneyRoute
    let memories: [JourneyMemory]
    let overallMemory: String
    let cityName: String
    let countryName: String
    let journeyDate: String
    let distanceText: String
    let durationText: String
    let userID: String
    let routeThumbnail: UIImage?
    let loadout: RobotLoadout

    // Pagination support
    var showHeader: Bool = true
    var showRouteThumbnail: Bool = true
    var showOverallMemory: Bool = true
    var pageIndicator: String? = nil

    private var sortedMemories: [JourneyMemory] {
        memories.sorted(by: { $0.timestamp < $1.timestamp })
    }

    private var presentation: JourneyMemoryDetailExportPresentation {
        JourneyMemoryDetailExportPresentation(
            overallMemory: overallMemory,
            overallMemoryImagePaths: journey.overallMemoryImagePaths
        )
    }

    private var exportTitle: String {
        JourneyMemoryDetailTitlePresentation.exportTitle(
            customTitle: journey.customTitle,
            fallbackCityName: cityName
        )
    }

    // exportWidth = 360 (set in exportLongImage), horizontal padding = 32 each side
    private let imageContentWidth: CGFloat = 360 - 32 * 2

    var body: some View {
        ZStack {
            FigmaTheme.background

            VStack(alignment: .center, spacing: 24) {
                if showHeader {
                    headerCard
                }
                if showRouteThumbnail, let thumb = routeThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(red: 0.90, green: 0.91, blue: 0.92), lineWidth: 1)
                        )
                        .padding(.horizontal, 32)
                }
                if let indicator = pageIndicator {
                    Text(indicator)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.0)
                        .foregroundColor(Color(red: 0.62, green: 0.65, blue: 0.70))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if showOverallMemory, presentation.shouldShowOverallMemory {
                    overallMemorySection
                }
                memoriesTimeline
                brandingFooter
            }
            .padding(.bottom, 40)
        }
        // 关键：让内容按真实高度撑开，renderer 才能渲出长图
        .fixedSize(horizontal: false, vertical: true)
    }


    // MARK: - Header (match style, hide interactive controls)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {

            // Keep the same top spacing as the real page
            Color.clear.frame(height: 20)
                .padding(.top, 18)

            // Title + avatar
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exportTitle.uppercased())
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text("\(countryName.uppercased()) • \(journeyDate)")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                RobotRendererView(size: 52, face: .front, loadout: loadout)
                    .frame(width: 52, height: 52)
            }

            // Stats
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.key("lockscreen_distance"))
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
                    Text(distanceText)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.key("lockscreen_duration"))
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
                    Text(durationText)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                }
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 32)
        .background(FigmaTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.90, green: 0.91, blue: 0.92))
                .frame(height: 0.5)
        }
    }

    private var overallMemorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("overall_memory"))
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color(red: 0.60, green: 0.63, blue: 0.69))

            if !presentation.overallMemoryText.isEmpty {
                Text(presentation.overallMemoryText)
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.21, green: 0.26, blue: 0.32))
                    .lineSpacing(8.75)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !presentation.overallMemoryImagePaths.isEmpty {
                SyncMemoryImagesView(
                    imagePaths: presentation.overallMemoryImagePaths,
                    userID: userID,
                    contentWidth: imageContentWidth
                )
            }
        }
        .frame(width: imageContentWidth, alignment: .leading)
        .padding(.top, -8)
    }

    // MARK: - Memories Timeline (read-only, match spacing)

    private var memoriesTimeline: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(sortedMemories.enumerated()), id: \.element.id) { index, mem in
                ExportMemoryTimelineItem(
                    memory: mem,
                    userID: userID,
                    contentWidth: imageContentWidth
                )

                if index < sortedMemories.count - 1 {
                    TimelineDivider()
                }
            }
        }
        .frame(width: imageContentWidth, alignment: .leading)
        .padding(.top, 4)
    }

    private var brandingFooter: some View {
        HStack(spacing: 5) {
            if let icon = UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }

            Text("WORLDO")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.0)
                .foregroundColor(Color(red: 0.62, green: 0.65, blue: 0.70))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 12)
    }
}
