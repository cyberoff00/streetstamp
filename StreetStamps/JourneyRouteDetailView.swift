import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct JourneyRouteDetailView: View {
    let journeyID: String
    let isReadOnly: Bool
    let headerTitle: String?
    let userID: String?
    let friendLoadout: RobotLoadout?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var locationHub: LocationHub
    @EnvironmentObject private var flow: AppFlowCoordinator
    @ObservedObject private var languagePreference = LanguagePreference.shared

    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @State private var fittedRegion: MKCoordinateRegion? = nil
    @State private var initialCameraCommand: MapCameraCommand? = nil
    @State private var editingMemory: JourneyMemory? = nil
    @State private var viewingMemory: JourneyMemory? = nil
    @State private var sidebarHideToken = UUID().uuidString
    @State private var localizedCityTitle: String? = nil
    @AppStorage(MapLayerStyle.storageKey) private var layerStyleRaw = MapLayerStyle.current.rawValue

    init(
        journeyID: String,
        isReadOnly: Bool = false,
        headerTitle: String? = nil,
        userID: String? = nil,
        friendLoadout: RobotLoadout? = nil
    ) {
        self.journeyID = journeyID
        self.isReadOnly = isReadOnly
        self.headerTitle = headerTitle
        self.userID = userID
        self.friendLoadout = friendLoadout
    }

    private var journey: JourneyRoute? {
        store.journeys.first(where: { $0.id == journeyID })
    }

    private var cachedCitiesByKey: [String: CachedCity] {
        cityCache.cachedCitiesByKey
    }

    private var cityTitle: String {
        if let localizedCityTitle, !localizedCityTitle.isEmpty {
            return localizedCityTitle
        }
        guard let journey else { return L10n.t("unknown") }
        let fallbackTitle = JourneyCityNamePresentation.title(
            for: journey,
            localizedCityNameByKey: [:],
            cachedCitiesByKey: cachedCitiesByKey
        )
        let cityKey = (journey.startCityKey ?? journey.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
        return CityDisplayResolver.title(
            for: cityKey,
            fallbackTitle: fallbackTitle
        )
    }

    private var countryTitle: String {
        let iso = (journey?.countryISO2 ?? "").uppercased()
        if iso.count == 2 {
            return LanguagePreference.shared.displayLocale.localizedString(forRegionCode: iso) ?? iso
        }
        return L10n.t("unknown_country")
    }

    private var dateText: String {
        guard let d = journey?.endTime ?? journey?.startTime else { return "--" }
        let df = DateFormatter()
        df.locale = LanguagePreference.shared.displayLocale
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: d)
    }

    private var durationText: String {
        guard let j = journey, let s = j.startTime, let e = j.endTime else { return "--" }
        let sec = max(0, Int(e.timeIntervalSince(s)))
        let h = sec / 3600
        let m = (sec % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }

    private var mapSegments: [MapRouteSegment] {
        guard let j = journey else { return [] }
        let surface: RouteRenderSurface = (MapLayerStyle(rawValue: layerStyleRaw) ?? .mutedDark).engine == .mapbox ? .mapbox : .mapKit
        return CityDeepRenderEngine.styledSegments(
            journeys: [j],
            countryISO2: j.countryISO2,
            cityKey: j.cityKey,
            surface: surface
        ).enumerated().map { (i, seg) in
            MapRouteSegment(id: "jd-\(i)", coordinates: seg.coords, isGap: seg.isGap, repeatWeight: seg.repeatWeight)
        }
    }

    private var mapAnnotations: [MapAnnotationItem] {
        guard let j = journey else { return [] }
        return j.memories.filter { $0.locationStatus != .pending }.map { memory in
            let mapped = JourneyMemoryMapCoordinateResolver.mapCoordinate(
                for: memory,
                fallbackCountryISO2: j.countryISO2,
                fallbackCityKey: j.cityKey
            )
            return MapAnnotationItem(id: memory.id, coordinate: mapped, kind: .memoryGroup(key: memory.id, items: [memory]))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            UnifiedMapView(
                segments: mapSegments,
                annotations: mapAnnotations,
                cameraCommand: initialCameraCommand,
                config: .journeyDetail(),
                callbacks: MapCallbacks(
                    onSelectMemories: { memories in
                        guard let memory = memories.first else { return }
                        switch JourneyRouteDetailInteractionPolicy.destinationForMemoryTap(isReadOnly: isReadOnly) {
                        case .editMemory:
                            editingMemory = memory
                        case .viewMemory:
                            viewingMemory = memory
                        }
                    }
                )
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                routeHeader

                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(cityTitle) · \(countryTitle)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text("\(dateText) · \(durationText) · \(String(format: "%.1f km", max(0, (journey?.distance ?? 0) / 1000.0)))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
        }
        .overlay {
            if let tappedMemory = viewingMemory {
                MemoryDetailPage(
                    memory: tappedMemory,
                    isPresented: Binding(
                        get: { viewingMemory != nil },
                        set: { if !$0 { viewingMemory = nil } }
                    ),
                    allowsEditing: false,
                    maxCardWidth: 300,
                    maxCardHeight: 440,
                    onUpdated: { _ in },
                    userID: userID
                )
                .environmentObject(sessionStore)
            } else if !isReadOnly, let tappedMemory = editingMemory {
                MemoryEditorSheet(
                    isPresented: Binding(
                        get: { editingMemory != nil },
                        set: { if !$0 { editingMemory = nil } }
                    ),
                    userID: sessionStore.currentUserID,
                    existing: tappedMemory,
                    onSave: { updated in
                        let targetId = tappedMemory.id
                        guard let jIdx = store.journeys.firstIndex(where: { $0.id == journeyID }) else { return }
                        var j = store.journeys[jIdx]
                        guard let mIdx = j.memories.firstIndex(where: { $0.id == targetId }) else { return }

                        if let updated {
                            var normalized = updated
                            normalized.id = tappedMemory.id
                            normalized.timestamp = tappedMemory.timestamp
                            normalized.coordinate = tappedMemory.coordinate
                            normalized.type = .memory
                            normalized.cityKey = tappedMemory.cityKey
                            normalized.cityName = tappedMemory.cityName
                            j.memories[mIdx] = normalized
                        } else {
                            j.memories.removeAll(where: { $0.id == targetId })
                        }

                        store.upsertSnapshotThrottled(j, coordCount: j.coordinates.count)
                        store.flushPersist(journey: j)
                    }
                )
                .environmentObject(sessionStore)
            }
        }
        .overlay {
            if isReadOnly, let loadout = friendLoadout, let j = journey {
                let distText = FriendJourneyDistancePresentation.makeDistanceText(
                    currentLocation: locationHub.currentLocation,
                    lastKnownLocation: locationHub.lastKnownLocation,
                    journeyEndCoordinate: j.coordinates.last?.cl
                )
                FriendMapCharacterOverlay(friendLoadout: loadout, distanceText: distText)
            }
        }
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
            refreshRegion()
        }
        .onChange(of: journey?.id) { _ in
            refreshRegion()
        }
        .task(id: "\(journey?.id ?? "")|\(languagePreference.currentLanguage ?? "sys")") {
            await refreshLocalizedCityTitle()
        }
        .onDisappear {
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .navigationBarBackButtonHidden(true)
        .confirmationDialog(L10n.t("delete_journey_confirm_title"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("delete"), role: .destructive) {
                store.deleteJourney(id: journeyID)
                dismiss()
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareImage {
                ShareSheet(activityItems: [shareImage])
            }
        }
    }

    private var routeHeader: some View {
        ZStack {
            HStack {
                AppBackButton(foreground: .black)
                .frame(width: 88, alignment: .leading)

                Spacer(minLength: 0)

                if !isReadOnly {
                    HStack(spacing: 10) {
                        Button {
                            shareCurrent()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.black)
                                .appMinTapTarget()
                        }
                        .buttonStyle(.plain)

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.black)
                                .appMinTapTarget()
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Color.clear.frame(width: 88, height: 44)
                }
            }

            Text(headerTitle ?? L10n.t("journey_route_title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FigmaTheme.border)
                .frame(height: 1)
        }
    }

    private func refreshRegion() {
        guard let j = journey else {
            fittedRegion = nil
            initialCameraCommand = nil
            return
        }

        let region = CityDeepRenderEngine.fittedRegion(
            cityKey: j.cityKey,
            countryISO2: j.countryISO2,
            journeys: [j],
            anchorWGS: j.allCLCoords.first,
            effectiveBoundaryWGS: nil,
            fetchedBoundaryWGS: nil
        )
        fittedRegion = region
        if let region {
            initialCameraCommand = .setRegion(region, animated: false)
        }
    }

    private func refreshLocalizedCityTitle() async {
        guard let journey else { return }
        let key = journey.stableCityKey ?? ""
        guard !key.isEmpty, key != "Unknown|" else { return }

        // Single source of truth: CachedCity.displayTitle
        if let cachedCity = cachedCitiesByKey[key] {
            let title = cachedCity.displayTitle
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { localizedCityTitle = title }
                return
            }
        }

        // Fallback for journeys without a city card: async geocode
        let parentRegionKey = JourneyCityNamePresentation.parentRegionKey(for: journey, cachedCitiesByKey: cachedCitiesByKey)

        if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key, parentRegionKey: parentRegionKey),
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await MainActor.run { localizedCityTitle = cached }
            return
        }

        guard let start = journey.startCoordinate, start.isValid else { return }
        let loc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        if let title = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: parentRegionKey),
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await MainActor.run { localizedCityTitle = title }
        }
    }

    private func shareCurrent() {
        guard let j = journey else { return }
        ShareCardGenerator.generate(
            journey: j,
            cachedCitiesByKey: cachedCitiesByKey,
            privacy: .exact,
            applyJourneyPrivacy: true
        ) { img in
            self.shareImage = img
            self.showShareSheet = true
        }
    }
}

// Old JourneyDetailMap, JourneyStyledPolyline, JourneyLayeredPolylineRenderer removed — now using UnifiedMapView
