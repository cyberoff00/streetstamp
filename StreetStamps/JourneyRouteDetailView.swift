import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct JourneyRouteDetailView: View {
    let journeyID: String
    let isReadOnly: Bool
    let headerTitle: String?
    let userID: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator

    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @State private var fittedRegion: MKCoordinateRegion? = nil
    @State private var editingMemory: JourneyMemory? = nil
    @State private var viewingMemory: JourneyMemory? = nil
    @State private var sidebarHideToken = UUID().uuidString
    @State private var localizedCityTitle: String? = nil

    init(
        journeyID: String,
        isReadOnly: Bool = false,
        headerTitle: String? = nil,
        userID: String? = nil
    ) {
        self.journeyID = journeyID
        self.isReadOnly = isReadOnly
        self.headerTitle = headerTitle
        self.userID = userID
    }

    private var journey: JourneyRoute? {
        store.journeys.first(where: { $0.id == journeyID })
    }

    private var cachedCitiesByKey: [String: CachedCity] {
        Dictionary(
            uniqueKeysWithValues: cityCache.cachedCities
                .filter { !($0.isTemporary ?? false) }
                .map { ($0.id, $0) }
        )
    }

    private var cityTitle: String {
        if let localizedCityTitle, !localizedCityTitle.isEmpty {
            return localizedCityTitle
        }
        guard let journey else { return L10n.t("unknown") }
        return JourneyCityNamePresentation.title(
            for: journey,
            localizedCityNameByKey: [:],
            cachedCitiesByKey: cachedCitiesByKey
        )
    }

    private var countryTitle: String {
        let iso = (journey?.countryISO2 ?? "").uppercased()
        if iso.count == 2 {
            return Locale.current.localizedString(forRegionCode: iso) ?? iso
        }
        return L10n.t("unknown_country")
    }

    private var dateText: String {
        guard let d = journey?.endTime ?? journey?.startTime else { return "--" }
        let df = DateFormatter()
        df.locale = Locale.current
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

    private var segments: [JourneyDetailMap.AnySegment] {
        guard let j = journey else { return [] }
        return CityDeepRenderEngine.styledSegments(
            journeys: [j],
            countryISO2: j.countryISO2,
            cityKey: j.cityKey
        ).map {
            JourneyDetailMap.AnySegment(coords: $0.coords, isGap: $0.isGap, repeatWeight: $0.repeatWeight)
        }
    }

    private var memoryGroups: [JourneyDetailMap.MemoryGroup] {
        guard let j = journey else { return [] }
        return j.memories.filter { $0.locationStatus != .pending }.map { memory in
            let mapped = JourneyMemoryMapCoordinateResolver.mapCoordinate(
                for: memory,
                fallbackCountryISO2: j.countryISO2,
                fallbackCityKey: j.cityKey
            )
            return JourneyDetailMap.MemoryGroup(id: memory.id, coordinate: mapped, memory: memory)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            JourneyDetailMap(
                segments: segments,
                memoryGroups: memoryGroups,
                initialRegion: fittedRegion,
                onTapMemory: { memory in
                    switch JourneyRouteDetailInteractionPolicy.destinationForMemoryTap(isReadOnly: isReadOnly) {
                    case .editMemory:
                        editingMemory = memory
                    case .viewMemory:
                        viewingMemory = memory
                    }
                }
            )
            .ignoresSafeArea()
            .onAppear {
                refreshRegion()
            }
            .onChange(of: journey?.id) { _ in
                refreshRegion()
            }

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
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
        }
        .task(id: journey?.id) {
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
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
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
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.black)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Color.clear.frame(width: 68, height: 34)
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
            return
        }

        fittedRegion = CityDeepRenderEngine.fittedRegion(
            cityKey: j.cityKey,
            countryISO2: j.countryISO2,
            journeys: [j],
            anchorWGS: j.allCLCoords.first,
            effectiveBoundaryWGS: nil,
            fetchedBoundaryWGS: nil
        )
    }

    private func refreshLocalizedCityTitle() async {
        guard let journey else { return }
        let key = journey.stableCityKey ?? ""
        guard !key.isEmpty, key != "Unknown|" else { return }

        if let cachedCity = cachedCitiesByKey[key] {
            let title = CityPlacemarkResolver.displayTitle(
                cityKey: cachedCity.id,
                iso2: cachedCity.countryISO2,
                fallbackTitle: cachedCity.name,
                availableLevelNamesRaw: cachedCity.reservedAvailableLevelNames,
                storedAvailableLevelNamesLocaleID: cachedCity.reservedAvailableLevelNamesLocaleID,
                parentRegionKey: cachedCity.reservedParentRegionKey,
                preferredLevel: cachedCity.reservedLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
                localizedDisplayNameByLocale: cachedCity.localizedDisplayNameByLocale,
                locale: .current
            )
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { localizedCityTitle = title }
                return
            }
        }

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
            privacy: .exact
        ) { img in
            self.shareImage = img
            self.showShareSheet = true
        }
    }
}

private struct JourneyDetailMap: UIViewRepresentable {
    struct AnySegment {
        let coords: [CLLocationCoordinate2D]
        let isGap: Bool
        let repeatWeight: Double
    }

    struct MemoryGroup: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let memory: JourneyMemory
    }

    let segments: [AnySegment]
    let memoryGroups: [MemoryGroup]
    let initialRegion: MKCoordinateRegion?
    let onTapMemory: (JourneyMemory) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = MapAppearanceSettings.interfaceStyle
        map.showsCompass = false
        map.showsScale = false
        map.showsTraffic = false
        map.pointOfInterestFilter = .excludingAll
        map.mapType = MapAppearanceSettings.mapType
        map.isRotateEnabled = false
        map.isPitchEnabled = false

        if let r = initialRegion {
            map.setRegion(r, animated: false)
            context.coordinator.didSetInitialRegion = true
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.overrideUserInterfaceStyle = MapAppearanceSettings.interfaceStyle
        map.mapType = MapAppearanceSettings.mapType

        if let r = initialRegion, !context.coordinator.didSetInitialRegion {
            context.coordinator.didSetInitialRegion = true
            map.setRegion(r, animated: false)
        }

        map.removeOverlays(map.overlays)
        for seg in segments where seg.coords.count >= 2 {
            let poly = JourneyStyledPolyline(coordinates: seg.coords, count: seg.coords.count)
            poly.isGap = seg.isGap
            poly.repeatWeight = max(0, min(1, seg.repeatWeight))
            map.addOverlay(poly)
        }

        map.removeAnnotations(map.annotations)
        for g in memoryGroups {
            map.addAnnotation(JourneyMemoryAnnotation(group: g))
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: JourneyDetailMap
        var didSetInitialRegion = false

        init(_ parent: JourneyDetailMap) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? JourneyStyledPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let base = MapAppearanceSettings.routeBaseColor
            let gapDash = RouteRenderStyleTokens.dashLengths.map { NSNumber(value: Double($0)) }
            let weight = CGFloat(max(0, min(1, poly.repeatWeight)))
            let isGap = poly.isGap

            let glow = MKPolylineRenderer(polyline: poly)
            glow.lineWidth = isGap ? 2.0 : (3.0 + weight * 1.2)
            glow.lineCap = .round
            glow.lineJoin = .round
            glow.strokeColor = base.withAlphaComponent(isGap ? 0.08 : 0.12)
            if isGap { glow.lineDashPattern = gapDash }

            let core = MKPolylineRenderer(polyline: poly)
            core.lineWidth = isGap ? 1.1 : (1.6 + weight * 0.8)
            core.lineCap = .round
            core.lineJoin = .round
            core.strokeColor = base.withAlphaComponent(isGap ? 0.30 : 0.84)
            if isGap { core.lineDashPattern = gapDash }

            let freq = MKPolylineRenderer(polyline: poly)
            freq.lineWidth = isGap ? 0 : (2.2 + weight * 1.2)
            freq.lineCap = .round
            freq.lineJoin = .round
            freq.strokeColor = base.withAlphaComponent(isGap ? 0 : (0.05 + 0.15 * weight))

            return JourneyLayeredPolylineRenderer(renderers: [glow, freq, core])
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? JourneyMemoryAnnotation else { return nil }
            let id = "journeyMem"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: ann, reuseIdentifier: id)

            view.annotation = ann
            view.canShowCallout = false
            view.bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
            view.backgroundColor = .clear
            view.displayPriority = .required
            if #available(iOS 14.0, *) {
                view.zPriority = .max
            }

            let hosting = UIHostingController(rootView: MemoryPin(cluster: [ann.group.memory]))
            hosting.view.backgroundColor = .clear
            hosting.view.frame = view.bounds
            hosting.view.isUserInteractionEnabled = false
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hosting.view)

            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let ann = view.annotation as? JourneyMemoryAnnotation else { return }
            parent.onTapMemory(ann.group.memory)
            mapView.deselectAnnotation(ann, animated: false)
        }
    }
}

private final class JourneyMemoryAnnotation: NSObject, MKAnnotation {
    let group: JourneyDetailMap.MemoryGroup
    var coordinate: CLLocationCoordinate2D { group.coordinate }

    init(group: JourneyDetailMap.MemoryGroup) {
        self.group = group
    }
}

private final class JourneyStyledPolyline: MKPolyline {
    var isGap: Bool = false
    var repeatWeight: Double = 0
}

private final class JourneyLayeredPolylineRenderer: MKOverlayRenderer {
    private let renderers: [MKPolylineRenderer]

    init(renderers: [MKPolylineRenderer]) {
        precondition(!renderers.isEmpty)
        self.renderers = renderers
        super.init(overlay: renderers[0].overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        for renderer in renderers {
            renderer.draw(mapRect, zoomScale: zoomScale, in: context)
        }
    }
}
