//
//  GlobeViewScreen.swift
//  StreetStamps
//
//  Created by Claire Yang on 26/01/2026.
//

import SwiftUI
import UIKit

private struct GlobeShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Standalone page for Sidebar tab: Globe View
struct GlobeViewScreen: View {
    @Binding var showSidebar: Bool
    var externalJourneys: [JourneyRoute]? = nil
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var lifelogStore: LifelogStore
    @EnvironmentObject private var trackTileStore: TrackTileStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @State private var dummyPresented: Bool = true
    @State private var shareItem: GlobeShareImageItem? = nil
    @State private var journeysForRender: [JourneyRoute] = []
    @State private var visitedCountries: [String] = []
    @State private var isPreparingData = false
    @State private var didKickoffLifelogBackfill = false

    var body: some View {
        ZStack {
            MapboxGlobeView(
                isPresented: $dummyPresented,
                journeys: journeysForRender,
                visitedCountryISO2Override: visitedCountries,
                showsCloseButton: false
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topHeader
                Spacer()
                bottomSummaryCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 70)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.image])
        }
        .overlay {
            if isPreparingData {
                ProgressView()
                    .tint(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.45), in: Capsule())
            }
        }
        .task {
            guard journeysForRender.isEmpty else { return }
            refreshGlobeData()
        }
        .onAppear {
            kickOffLifelogBackfillIfNeeded()
        }
        .onChange(of: store.hasLoaded) { loaded in
            if loaded {
                kickOffLifelogBackfillIfNeeded()
            }
        }
        .onChange(of: store.trackTileRevision) { _ in
            refreshGlobeData()
        }
        .onChange(of: lifelogStore.trackTileRevision) { _ in
            refreshGlobeData()
        }
        .onChange(of: cityCache.cachedCities.count) { _ in
            refreshGlobeData()
        }
    }

    private var topHeader: some View {
        HStack {
            SidebarHamburgerButton(showSidebar: $showSidebar, size: 42, iconSize: 20, iconWeight: .semibold, foreground: .black)

            Spacer()

            Text(L10n.t("globe_view_title"))
                .appHeaderStyle()
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.45), in: Capsule())
                .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.92))
                    .clipShape(Circle())
            }
        }
    }

    private var bottomSummaryCard: some View {
        let nonTemporaryCities = cityCache.cachedCities.filter { !($0.isTemporary ?? false) }
        let cityCount = nonTemporaryCities.count
        let totalMemories = nonTemporaryCities.reduce(0) { $0 + max(0, $1.memories) }
        let levelProgress = UserLevelProgress.from(journeys: store.journeys)

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 200.0 / 255.0, green: 232.0 / 255.0, blue: 221.0 / 255.0))
                    .frame(width: 68, height: 68)

                RobotRendererView(size: 56, face: .front, loadout: AvatarLoadoutStore.load())
            }
            .overlay(alignment: .topTrailing) {
                LevelBadgeView(level: levelProgress.level)
                    .offset(x: 10, y: -10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(normalizedDisplayName(profileName))
                    .appBodyStrongStyle()
                    .foregroundColor(.black)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(String(format: L10n.t("level_format"), levelProgress.level))
                    Text("·")
                    Text(String(format: L10n.t("level_remaining_short_format"), levelProgress.journeysRemainingToNextLevel))
                }
                    .appCaptionStyle()
                    .foregroundColor(.black.opacity(0.62))
                    .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 6)
                        Capsule()
                            .fill(UITheme.accent)
                            .frame(width: max(8, proxy.size.width * levelProgress.progress), height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(cityCount) CITIES · \(totalMemories) MEMORIES")
                    .appFootnoteStyle()
                    .foregroundColor(.black.opacity(0.56))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button {
                if let image = captureCurrentPageImage() {
                    shareItem = GlobeShareImageItem(image: image)
                }
            } label: {
                Label(L10n.t("share"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(UITheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
    }

    private func normalizedDisplayName(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.t("explorer_fallback") : value
    }

    private func refreshGlobeData() {
        if isPreparingData { return }
        isPreparingData = true

        let countryISO2 = lifelogStore.countryISO2
        let tileSegments = trackTileStore.tiles(for: nil, zoom: TrackRenderAdapter.unifiedRenderZoom)
        let external = externalJourneys
        let summary = store.journeys
        let journeyEvents = store.trackRenderEvents()
        let passiveEvents = lifelogStore.trackRenderEvents()
        let lifelogRoutes = lifelogStore.globeJourneys()
        let cityISO2 = cityCache.cachedCities
            .filter { $0.isTemporary != true }
            .compactMap { $0.countryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { $0.count == 2 }

        DispatchQueue.global(qos: .userInitiated).async {
            let routes = Self.resolveRoutesForGlobe(
                tileSegments: tileSegments,
                externalJourneys: external,
                summaryJourneys: summary,
                journeyEvents: journeyEvents,
                passiveEvents: passiveEvents,
                lifelogRoutes: lifelogRoutes,
                countryISO2: countryISO2
            )
            let countries = Self.resolveVisitedCountries(routes: routes, cityISO2: cityISO2)

            DispatchQueue.main.async {
                journeysForRender = routes
                visitedCountries = countries
                isPreparingData = false
            }
        }
    }

    private static func resolveRoutesForGlobe(
        tileSegments: [TrackTileSegment],
        externalJourneys: [JourneyRoute]?,
        summaryJourneys: [JourneyRoute],
        journeyEvents: [TrackRenderEvent],
        passiveEvents: [TrackRenderEvent],
        lifelogRoutes: [JourneyRoute],
        countryISO2: String?
    ) -> [JourneyRoute] {
        let tileRoutes = TrackRenderAdapter.globeJourneys(
            from: tileSegments,
            countryISO2: countryISO2
        )
        if !tileRoutes.isEmpty {
            return tileRoutes
        }

        if let externalJourneys, !externalJourneys.isEmpty {
            return externalJourneys
        }

        let liveEvents = journeyEvents + passiveEvents
        let liveTiles = TrackTileBuilder.build(
            events: liveEvents,
            zoom: TrackRenderAdapter.unifiedRenderZoom
        ).tiles
        let liveSegments = liveTiles.values.flatMap(\.segments).sorted {
            if $0.startTimestamp != $1.startTimestamp {
                return $0.startTimestamp < $1.startTimestamp
            }
            if $0.endTimestamp != $1.endTimestamp {
                return $0.endTimestamp < $1.endTimestamp
            }
            return $0.sourceType.rawValue < $1.sourceType.rawValue
        }
        let liveRoutes = TrackRenderAdapter.globeJourneys(
            from: liveSegments,
            countryISO2: countryISO2
        )
        if !liveRoutes.isEmpty {
            return liveRoutes
        }

        if !lifelogRoutes.isEmpty {
            return lifelogRoutes
        }

        return summaryJourneys
    }

    private static func resolveVisitedCountries(routes: [JourneyRoute], cityISO2: [String]) -> [String] {
        var set = Set<String>()
        for j in routes {
            if let iso = j.countryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
               iso.count == 2 {
                set.insert(iso)
            }
            if let iso = isoFromCityKey(j.startCityKey) {
                set.insert(iso)
            }
            if let iso = isoFromCityKey(j.cityKey) {
                set.insert(iso)
            }
            if let iso = isoFromCityKey(j.endCityKey) {
                set.insert(iso)
            }
        }

        for iso in cityISO2 {
            set.insert(iso)
        }
        return Array(set).sorted()
    }

    private static func isoFromCityKey(_ cityKey: String?) -> String? {
        guard let cityKey else { return nil }
        let parts = cityKey.split(separator: "|", omittingEmptySubsequences: false)
        guard let raw = parts.last else { return nil }
        let iso = String(raw).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return iso.count == 2 ? iso : nil
    }

    private func kickOffLifelogBackfillIfNeeded() {
        guard !didKickoffLifelogBackfill else { return }
        guard store.hasLoaded else { return }
        didKickoffLifelogBackfill = true

        let snapshot = store.journeys
        Task(priority: .utility) {
            await lifelogStore.backfillHistoricalJourneysIfNeeded(from: snapshot)
        }
    }

    private func captureCurrentPageImage() -> UIImage? {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: \.isKeyWindow)
        else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}
