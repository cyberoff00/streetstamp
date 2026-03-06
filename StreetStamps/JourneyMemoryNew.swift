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

// =======================================================
// MARK: - Main Journey Memory View (Screen 1 & 2)
// =======================================================

struct JourneyMemoryMainView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @Environment(\.dismiss) private var dismiss
    @State private var expandedCities: Set<String> = []
    @State private var showFilterPopover = false
    @State private var monthCursor = Date()
    @State private var selectedStartDate: Date? = nil
    @State private var selectedEndDate: Date? = nil
    /// Localized city display cache for this screen (cityKey -> localized title in current locale)
    @State private var localizedCityNameByKey: [String: String] = [:]
    
    @Binding var showSidebar: Bool
    private let usesSidebarHeader: Bool
    private let hideLeadingControl: Bool
    private let readOnly: Bool
    private let headerTitle: String?
    
    init(
        showSidebar: Binding<Bool>,
        usesSidebarHeader: Bool = true,
        hideLeadingControl: Bool = false,
        readOnly: Bool = false,
        headerTitle: String? = nil
    ) {
        self._showSidebar = showSidebar
        self.usesSidebarHeader = usesSidebarHeader
        self.hideLeadingControl = hideLeadingControl
        self.readOnly = readOnly
        self.headerTitle = headerTitle
    }

    private var allMemoryJourneys: [JourneyRoute] {
        store.journeys
            .filter { !$0.memories.isEmpty }
            .sorted { ($0.endTime ?? $0.startTime ?? .distantPast) > ($1.endTime ?? $1.startTime ?? .distantPast) }
    }

    private var filteredMemoryJourneys: [JourneyRoute] {
        guard selectedStartDate != nil else { return allMemoryJourneys }
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedStartDate!)
        let upperBase = selectedEndDate ?? selectedStartDate!
        let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: upperBase)) ?? upperBase

        return allMemoryJourneys.filter { j in
            guard let date = j.endTime ?? j.startTime else { return false }
            return date >= start && date < endExclusive
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Content
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(cityGroups, id: \.cityKey) { city in
                            CitySection(
                                city: city,
                                isExpanded: expandedCities.contains(city.cityKey),
                                readOnly: readOnly,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        if expandedCities.contains(city.cityKey) {
                                            expandedCities.remove(city.cityKey)
                                        } else {
                                            expandedCities.insert(city.cityKey)
                                        }
                                    }
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
            store.load()
            onboardingGuide.advance(.openMemory)
        }
        // Keep city names localized to current language (do NOT rely on persisted English titles).
        .task(id: localizationFingerprint) {
            await refreshCityLocalizations()
        }
    }

    /// A stable-ish fingerprint to re-run localization when journey list changes.
    private var localizationFingerprint: String {
        allMemoryJourneys
            .map { "\($0.id)|\($0.startCityKey ?? $0.cityKey)" }
            .joined(separator: ",")
    }

    /// Fetch localized city titles for the current locale, keyed by the *start city*.
    private func refreshCityLocalizations() async {
        let journeys = allMemoryJourneys

        // cityKey -> sample start coordinate
        var coordByKey: [String: CLLocationCoordinate2D] = [:]
        for j in journeys {
            let key = (j.startCityKey ?? j.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key != "Unknown|" else { continue }
            if coordByKey[key] == nil, let start = j.startCoordinate, start.isValid {
                coordByKey[key] = start
            }
        }

        for (key, coord) in coordByKey {
            // Skip if we already have a localized value for this key.
            if localizedCityNameByKey[key] != nil { continue }

            // Prefer service cache (now locale-aware) to avoid extra geocode calls.
            if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key),
               !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { localizedCityNameByKey[key] = cached }
                continue
            }

            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let title = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key),
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { localizedCityNameByKey[key] = title }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        UnifiedTabPageHeader(title: resolvedHeaderTitle, horizontalPadding: 20, topPadding: 14, bottomPadding: 12) {
            if hideLeadingControl {
                Color.clear
            } else if usesSidebarHeader {
                SidebarHamburgerButton(showSidebar: $showSidebar, size: 42, iconSize: 20)
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)
            }
        } trailing: {
            Button {
                showFilterPopover.toggle()
            } label: {
                Image(systemName: selectedStartDate == nil ? "calendar" : "calendar.badge.clock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFilterPopover, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                JourneyMemoryCalendarRangePopover(
                    monthCursor: $monthCursor,
                    selectedStartDate: $selectedStartDate,
                    selectedEndDate: $selectedEndDate,
                    journeys: allMemoryJourneys,
                    onRangeCompleted: {
                        showFilterPopover = false
                    },
                    onApply: {
                        showFilterPopover = false
                    },
                    onClear: {
                        selectedStartDate = nil
                        selectedEndDate = nil
                        showFilterPopover = false
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var resolvedHeaderTitle: String {
        let trimmed = headerTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.t("memories_title") : trimmed
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.4))
            
            Text(L10n.key("no_memories_yet"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
            
            Text(L10n.key("memory_empty_desc"))
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Data Grouping

    private var cityGroups: [CityGroupData] {
        let journeys = filteredMemoryJourneys
        let journeyById = Dictionary(uniqueKeysWithValues: journeys.map { ($0.id, $0) })

        // cityKey -> (journeyId -> [memories])
        var buckets: [String: [String: [JourneyMemory]]] = [:]
        var nameForKey: [String: String] = [:]
        var countryForKey: [String: String] = [:]

        for j in journeys {
            // ✅ 关键：永远用 Journey 的起点 cityKey
            let key = (j.startCityKey ?? j.cityKey)

            // 把整个 journey 的 memories 都归到起点城市下面
            buckets[key, default: [:]][j.id] = j.memories

            // 城市名：优先使用当前语言的本地化标题（基于 cityKey），再 fallback 到 journey 自带的 displayCityName。
            if nameForKey[key] == nil {
                if let localized = localizedCityNameByKey[key], !localized.isEmpty {
                    nameForKey[key] = cityOnly(localized)
                } else {
                    nameForKey[key] = cityOnly(j.displayCityName)
                }
            }

            // 国家从 cityKey (City|ISO2) 取
            if countryForKey[key] == nil {
                if let iso2 = key.split(separator: "|").last.map(String.init) {
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
        return groups
    }

    
    private func countryName(from iso2: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forRegionCode: iso2) ?? iso2
    }

    /// Journey Memory list shows city only (no country) even if the raw name contains ", Country".
    private func cityOnly(_ raw: String) -> String {
        let normalized = raw.replacingOccurrences(of: "，", with: ",")
        let first = normalized.split(separator: ",").first.map(String.init) ?? normalized
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct JourneyMemoryCalendarDay: Identifiable {
    let id = UUID()
    let date: Date?
    let number: Int
}

private struct JourneyMemoryCalendarRangePopover: View {
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
        let cal = Calendar.current
        guard
            let monthInterval = cal.dateInterval(of: .month, for: monthCursor),
            let monthFirstWeek = cal.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let monthLastWeek = cal.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else { return [] }

        var cursor = monthFirstWeek.start
        var out: [JourneyMemoryCalendarDay] = []
        while cursor < monthLastWeek.end {
            let isInMonth = cal.isDate(cursor, equalTo: monthCursor, toGranularity: .month)
            let n = cal.component(.day, from: cursor)
            out.append(JourneyMemoryCalendarDay(date: isInMonth ? cursor : nil, number: n))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }
}

// =======================================================
// MARK: - Swipe back enabler (keep interactive pop when nav bar is hidden)
// =======================================================

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SwipeBackVC { SwipeBackVC() }
    func updateUIViewController(_ uiViewController: SwipeBackVC, context: Context) {}

    final class SwipeBackVC: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Re-enable edge swipe.
            navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Only when there's actually something to pop.
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

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
    let onToggle: () -> Void
    
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

                        NavigationLink {
                            JourneyMemoryDetailView(
                                journey: journey,
                                memories: memories,
                                cityName: city.cityName,
                                countryName: city.countryName,
                                readOnly: readOnly
                            )
                            .environmentObject(store)
                            .environmentObject(sessionStore)
                        } label: {
                            JourneyEntryRow(journey: journey, memories: memories)
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
    
    private var sortedMemories: [JourneyMemory] {
        memories.sorted(by: { $0.timestamp < $1.timestamp })
    }
    
    private var firstMemory: JourneyMemory? {
        sortedMemories.first
    }
    
    private var journeyDate: String {
        let d = journey.startTime ?? memories.map(\.timestamp).min() ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: d).uppercased()
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

    private var previewText: String {
        guard let mem = firstMemory else { return "" }
        let notes = mem.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { return notes }
        let title = mem.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L10n.t("tap_to_view_memories") : title
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date with green dot
            HStack(spacing: 8) {
                Circle()
                    .fill(FigmaTheme.primary)
                    .frame(width: 8, height: 8)
                
                Text(journeyDate)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
            }
            
//            // Distance & Duration
//            HStack(spacing: 24) {
//                VStack(alignment: .leading, spacing: 2) {
//                    Text(L10n.key("lockscreen_distance"))
//                        .font(.system(size: 10, weight: .medium))
//                        .foregroundColor(.gray)
//                        .tracking(0.5)
//                    Text(distanceText)
//                        .font(.system(size: 15, weight: .bold))
//                        .foregroundColor(.black)
//                }
//
//                VStack(alignment: .leading, spacing: 2) {
//                    Text(L10n.key("lockscreen_duration"))
//                        .font(.system(size: 10, weight: .medium))
//                        .foregroundColor(.gray)
//                        .tracking(0.5)
//                    Text(durationText)
//                        .font(.system(size: 15, weight: .bold))
//                        .foregroundColor(.black)
//                }
//            }
            
            // Preview text
            Text(previewText)
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.8))
                .lineSpacing(3)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    // 默认只读；点右上角 Edit 才进入编辑（避免 TextEditor 一直占用焦点导致键盘下不去）
    @State private var isEditing: Bool = false

    // 编辑草稿 + 用于取消的快照
    @State private var draftMemories: [JourneyMemory] = []
    @State private var snapshotBeforeEdit: [JourneyMemory] = []
    @State private var draftOverallMemory: String = ""
    @State private var snapshotOverallMemoryBeforeEdit: String = ""

    // Which memory's text field is focused (used to keep caret visible in the outer ScrollView).
    @FocusState private var focusedMemoryID: String?
    
    
    // Share / Export
    @State private var shareImage: UIImage? = nil
    @State private var shareItem: ShareImageItem? = nil

    @State private var showDeleteAllConfirm = false
    // Photo / Camera (edit mode)
    @State private var showCamera: Bool = false
    @State private var showPhotoLibrary: Bool = false
    @State private var activeMemoryIndex: Int? = nil
    @State private var mirrorSelfie: Bool = false
    @State private var sidebarHideToken = UUID().uuidString

    init(
        journey: JourneyRoute,
        memories: [JourneyMemory],
        cityName: String,
        countryName: String,
        readOnly: Bool = false
    ) {
        self.journey = journey
        self.memories = memories
        self.cityName = cityName
        self.countryName = countryName
        self.readOnly = readOnly
    }
    
    
    
    private var sortedMemories: [JourneyMemory] {
        memories.sorted(by: { $0.timestamp < $1.timestamp })
    }
    
    private var journeyDate: String {
        let d = journey.startTime ?? memories.map(\.timestamp).min() ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: d).uppercased()
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
        let t = (journey.customTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
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
        // ✅ Keep the NavigationController's edge-swipe "back" gesture.
        // `navigationBarBackButtonHidden(true)` often disables interactive pop.
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
            let uid = sessionStore.currentUserID
            if readOnly {
                draftMemories = sortedMemories
                snapshotBeforeEdit = sortedMemories
                draftOverallMemory = journey.overallMemory ?? ""
                snapshotOverallMemoryBeforeEdit = draftOverallMemory
                isEditing = false
                focusedMemoryID = nil
                return
            }
            // 1) Restore a saved editing session (tab switch / swipe away / relaunch)
            if JourneyMemoryDetailResumeStore.shouldResume(userID: uid, journeyID: journey.id),
               let saved = JourneyMemoryDetailDraftStore.load(userID: uid, journeyID: journey.id) {
                draftMemories = saved.memories
                snapshotBeforeEdit = saved.memories
                draftOverallMemory = journey.overallMemory ?? ""
                snapshotOverallMemoryBeforeEdit = draftOverallMemory
                isEditing = true
                focusedMemoryID = saved.focusedMemoryID
                JourneyMemoryDetailResumeStore.set(false, userID: uid, journeyID: journey.id)
            } else if draftMemories.isEmpty {
                // 2) Default read-only initialization
                draftMemories = sortedMemories
                snapshotBeforeEdit = sortedMemories
                draftOverallMemory = journey.overallMemory ?? ""
                snapshotOverallMemoryBeforeEdit = draftOverallMemory
            }
        }
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
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.image])
        }

        .fullScreenCover(isPresented: $showCamera) {
            SystemCameraPicker(
                preferredDevice: .rear,
                mirrorOnCapture: mirrorSelfie,
                onImage: { image in
                    showCamera = false
                    appendCapturedToActiveMemory(image)
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPhotoLibrary) {
            PhotoLibraryPicker(
                selectionLimit: max(1, 3 - (activeMemoryIndex.flatMap { draftMemories.indices.contains($0) ? draftMemories[$0].imagePaths.count : 0 } ?? 0)),
                onImages: { images in
                    showPhotoLibrary = false
                    appendLibraryImagesToActiveMemory(images)
                },
                onCancel: { showPhotoLibrary = false }
            )
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Back
            Button {
                if isEditing {
                    cancelEditing()
                }
                dismiss()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                .frame(height: 20)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            
            // Title + actions
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(journeyDisplayTitle.uppercased())
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

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
                    
                    Text(journeyMetaSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
                }
                
                Spacer()

                // Right-side actions
                if !readOnly {
                    HStack(spacing: 6) {
                        if isEditing {
                            Button {
                                cancelEditing()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)

                            Button {
                                saveEditing()
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                beginEditing()
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(width: 36, height: 36)
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
                                Divider()

                                Button(role: .destructive) {
                                    showDeleteAllConfirm = true
                                } label: {
                                    Label(L10n.t("delete_all_notes"), systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.black)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Color.clear.frame(width: 72, height: 36)
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
        .overlay(
            Rectangle()
                .inset(by: 0.5)
                .stroke(Color(red: 0.90, green: 0.91, blue: 0.92), lineWidth: 0.5)
        )
    }
    
    // MARK: - Memories Timeline
    
    private var memoriesTimeline: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(draftMemories.enumerated()), id: \.offset) { index, _ in
                if isEditing {
                    EditableMemoryTimelineItem(
                        memory: $draftMemories[index],
                        userID: sessionStore.currentUserID,
                        maxPhotos: 3,
                        focusedMemoryID: $focusedMemoryID,
                        onOpenCamera: { openCamera(for: index) },
                        onOpenPhotoLibrary: { openPhotoLibrary(for: index) }
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
            } else {
                Text(draftOverallMemory)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.48, green: 0.54, blue: 0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 52, alignment: .topLeading)
                    .padding(12)
                    .background(FigmaTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, -8)
    }

    // MARK: - Edit controls

    private func beginEditing() {
        snapshotBeforeEdit = draftMemories
        snapshotOverallMemoryBeforeEdit = draftOverallMemory
        isEditing = true
        // Enter edit mode without auto-focusing any field; user controls scroll position.
        focusedMemoryID = nil
    }

    private func cancelEditing() {
        draftMemories = snapshotBeforeEdit
        draftOverallMemory = snapshotOverallMemoryBeforeEdit
        isEditing = false
        endEditing()

        // Cancel is an explicit discard: clear persisted draft.
        JourneyMemoryDetailDraftStore.clear(userID: sessionStore.currentUserID, journeyID: journey.id)
        JourneyMemoryDetailResumeStore.set(false, userID: sessionStore.currentUserID, journeyID: journey.id)
    }

    @MainActor
    private func saveEditing() {
        guard var j = store.journeys.first(where: { $0.id == journey.id }) else {
            isEditing = false
            endEditing()
            return
        }

        j.memories = draftMemories
        let trimmedOverall = draftOverallMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        j.overallMemory = trimmedOverall.isEmpty ? nil : trimmedOverall
        store.upsertSnapshotThrottled(j, coordCount: j.coordinates.count)
        store.flushPersist(journey: j)

        snapshotBeforeEdit = draftMemories
        snapshotOverallMemoryBeforeEdit = draftOverallMemory
        isEditing = false
        endEditing()

        // Save is explicit: clear any persisted draft.
        JourneyMemoryDetailDraftStore.clear(userID: sessionStore.currentUserID, journeyID: journey.id)
        JourneyMemoryDetailResumeStore.set(false, userID: sessionStore.currentUserID, journeyID: journey.id)
    }

    // MARK: - Draft persistence (Journey Memory Detail)
    private func persistDetailDraftIfNeeded(force: Bool = false) {
        guard isEditing || force else { return }
        let uid = sessionStore.currentUserID
        let draft = JourneyMemoryDetailDraft(memories: draftMemories, focusedMemoryID: focusedMemoryID)
        JourneyMemoryDetailDraftStore.save(draft, userID: uid, journeyID: journey.id)
        JourneyMemoryDetailResumeStore.set(true, userID: uid, journeyID: journey.id)
    }

    // MARK: - Photo add helpers (edit mode)
    private func openCamera(for index: Int) {
        activeMemoryIndex = index
        showCamera = true
    }

    private func openPhotoLibrary(for index: Int) {
        activeMemoryIndex = index
        showPhotoLibrary = true
    }

    private func appendCapturedToActiveMemory(_ image: UIImage) {
        guard let idx = activeMemoryIndex, draftMemories.indices.contains(idx) else { return }
        guard draftMemories[idx].imagePaths.count < 3 else { return }
        if let filename = try? PhotoStore.saveJPEG(image, userID: sessionStore.currentUserID) {
            draftMemories[idx].imagePaths.append(filename)
        }
    }

    private func appendLibraryImagesToActiveMemory(_ images: [UIImage]) {
        guard let idx = activeMemoryIndex, draftMemories.indices.contains(idx) else { return }
        for image in images {
            if draftMemories[idx].imagePaths.count >= 3 { break }
            if let filename = try? PhotoStore.saveJPEG(image, userID: sessionStore.currentUserID) {
                draftMemories[idx].imagePaths.append(filename)
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

        // Export at ~1080px width (360 * 3)
        let exportWidth: CGFloat = 360

        let view = JourneyMemoryDetailExportSnapshotView(
            journey: journey,
            memories: draftMemories,
            cityName: cityName,
            countryName: countryName,
            journeyDate: journeyDate,
            distanceText: distanceText,
            durationText: durationText,
            userID: sessionStore.currentUserID
        )
        .frame(width: exportWidth)
        .fixedSize(horizontal: false, vertical: true)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = .init(width: exportWidth, height: nil)
        renderer.isOpaque = true

        if let img = renderer.uiImage {
            shareItem = ShareImageItem(image: img)   // ✅ 有图才弹
        }

    }

    
}



// =======================================================
// MARK: - Memory Timeline Item
// =======================================================
private struct ExportMemoryTimelineItem: View {
    let memory: JourneyMemory
    let userID: String

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: memory.timestamp).uppercased()
    }

    private var contentText: String {
        let notes = memory.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { return notes }
        let title = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L10n.t("no_notes") : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(timeText)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color(red: 0.60, green: 0.63, blue: 0.69))

            if !memory.imagePaths.isEmpty || !memory.remoteImageURLs.isEmpty {
                MemoryImagesView(
                    imagePaths: memory.imagePaths,
                    remoteImageURLs: memory.remoteImageURLs,
                    userID: userID
                )
            }

            // ✅ 导出用纯 SwiftUI Text，ImageRenderer 能渲出来
            Text(contentText)
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.21, green: 0.26, blue: 0.32))
                .lineSpacing(8.75)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var contentText: String {
        let notes = memory.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { return notes }
        let title = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L10n.t("no_notes") : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Time
            Text(timeText)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color(red: 0.60, green: 0.63, blue: 0.69))

            // Images（只读态现在也完整展示）
            if !memory.imagePaths.isEmpty || !memory.remoteImageURLs.isEmpty {
                MemoryImagesView(
                    imagePaths: memory.imagePaths,
                    remoteImageURLs: memory.remoteImageURLs,
                    userID: userID
                )
            }

            // Text
            SelectableTextView(
                text: contentText,
                font: .systemFont(ofSize: 14),
                textColor: UIColor(red: 0.21, green: 0.26, blue: 0.32, alpha: 1.0),
                lineSpacing: 8.75
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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


private struct MemoryImagesView: View {
    let imagePaths: [String]
    let remoteImageURLs: [String]
    let userID: String

    var body: some View {
        VStack(spacing: 12) {
            ForEach(imagePaths, id: \.self) { path in
                if let img = PhotoStore.loadImage(named: path, userID: userID) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit() // ✅ keep original aspect ratio, no crop
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
            ForEach(remoteImageURLs, id: \.self) { rawURL in
                if let url = URL(string: rawURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
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
                        case .failure:
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(red: 0.95, green: 0.95, blue: 0.95))
                                .frame(maxWidth: .infinity)
                                .frame(height: 140)
                                .overlay {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.secondary)
                                }
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 140)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }
}

private struct EditableMemoryImagesView: View {
    @Binding var imagePaths: [String]
    let userID: String

    var body: some View {
        VStack(spacing: 12) {
            ForEach(imagePaths, id: \.self) { path in
                ZStack(alignment: .topTrailing) {
                    if let img = PhotoStore.loadImage(named: path, userID: userID) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit() // ✅ keep original aspect ratio, no crop
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

                    Button {
                        PhotoStore.delete(named: path, userID: userID)
                        withAnimation(.easeInOut(duration: 0.15)) {
                            imagePaths.removeAll(where: { $0 == path })
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.65))
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.92))
                                    .frame(width: 26, height: 26)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
        }
    }
}


private struct EditableMemoryTimelineItem: View {
    @Binding var memory: JourneyMemory
    let userID: String
    let maxPhotos: Int
    let focusedMemoryID: FocusState<String?>.Binding
    let onOpenCamera: () -> Void
    let onOpenPhotoLibrary: () -> Void

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: memory.timestamp).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(timeText)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color(red: 0.60, green: 0.63, blue: 0.69))

            HStack(spacing: 12) {
                Button(action: onOpenCamera) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .disabled(memory.imagePaths.count >= maxPhotos)
                .opacity(memory.imagePaths.count >= maxPhotos ? 0.35 : 1.0)

                Button(action: onOpenPhotoLibrary) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .disabled(memory.imagePaths.count >= maxPhotos)
                .opacity(memory.imagePaths.count >= maxPhotos ? 0.35 : 1.0)

                Text(String(format: L10n.t("photo_count"), memory.imagePaths.count, maxPhotos))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)

                Spacer()
            }
            .padding(.top, 2)

            if !memory.imagePaths.isEmpty {
                EditableMemoryImagesView(
                    imagePaths: $memory.imagePaths,
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
    let image: UIImage
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
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct JourneyMemoryDetailExportSnapshotView: View {
    let journey: JourneyRoute
    let memories: [JourneyMemory]
    let cityName: String
    let countryName: String
    let journeyDate: String
    let distanceText: String
    let durationText: String
    let userID: String

    private var sortedMemories: [JourneyMemory] {
        memories.sorted(by: { $0.timestamp < $1.timestamp })
    }

    var body: some View {
        ZStack {
            FigmaTheme.background

            VStack(alignment: .leading, spacing: 24) {
                        headerCard
                        memoriesTimeline
                    }
            .padding(.bottom, 40)
        }
        // 关键：让内容按真实高度撑开，renderer 才能渲出长图
        .fixedSize(horizontal: false, vertical: true)
    }


    // MARK: - Header (match style, hide interactive controls)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {

            // Keep the same top spacing as the real page but hide the BACK control
            HStack(spacing: 0) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
            .frame(height: 20)
            .opacity(0)               // hidden in export
            .padding(.top, 18)

            // Title + (hidden) actions area
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cityName.uppercased())
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))

                    Text("\(countryName.uppercased()) • \(journeyDate)")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(1.2)
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.51))
                }

                Spacer()

                // Reserve the same space as buttons but hide them
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 36, height: 36)

                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 36, height: 36)
                }
                .opacity(0)
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
        .overlay(
            Rectangle()
                .inset(by: 0.5)
                .stroke(Color(red: 0.90, green: 0.91, blue: 0.92), lineWidth: 0.5)
        )
    }

    // MARK: - Memories Timeline (read-only, match spacing)

    private var memoriesTimeline: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(sortedMemories.enumerated()), id: \.element.id) { index, mem in
                ExportMemoryTimelineItem(
                    memory: mem,
                    userID: userID
                )

                if index < sortedMemories.count - 1 {
                    TimelineDivider()
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
    }
}
