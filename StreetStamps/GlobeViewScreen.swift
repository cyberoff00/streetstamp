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

/// Shareable poster: a screenshot of the live 3D globe with a counts + Worldo
/// wordmark strip composited over a bottom gradient. Fixed size so `ImageRenderer`
/// produces a consistent image.
private struct GlobeSharePoster: View {
    let globeImage: UIImage
    let countryCount: Int
    let cityCount: Int
    /// Sampled from the captured globe's surround so the whole poster (globe band
    /// + stats panel) is one uniform colour — no white seam under the numbers.
    let backgroundColor: Color

    var body: some View {
        VStack(spacing: 0) {
            // Captured globe (already on clean white) fills the upper area.
            Image(uiImage: globeImage)
                .resizable()
                .scaledToFill()
                .frame(width: 1080, height: 1000)
                .clipped()

            // Light stats panel — the same white as the globe surround, so the
            // whole poster reads as one clean canvas in the app's palette.
            VStack(spacing: 28) {
                HStack(spacing: 64) {
                    statColumn(countryCount, L10n.t("globe_poster_countries"))
                    Rectangle()
                        .fill(FigmaTheme.text.opacity(0.12))
                        .frame(width: 1, height: 72)
                    statColumn(cityCount, L10n.t("globe_poster_cities"))
                }
                Text("WORLDO")
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(12)
                    .foregroundColor(FigmaTheme.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 350)
        }
        .frame(width: 1080, height: 1350)
        .background(backgroundColor)
    }

    private func statColumn(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 8) {
            Text("\(n)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundColor(FigmaTheme.text)
            Text(label)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)
        }
    }
}

/// Standalone page for Sidebar tab: Globe View
struct GlobeViewScreen: View {
    var externalJourneys: [JourneyRoute]? = nil
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var lifelogStore: LifelogStore
    @EnvironmentObject private var trackTileStore: TrackTileStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"
    @ObservedObject private var globeRefreshCoordinator = GlobeRefreshCoordinator.shared
    @ObservedObject private var membership = MembershipStore.shared

    @State private var dummyPresented: Bool = true
    @State private var shareItem: GlobeShareImageItem? = nil
    @State private var journeysForRender: [JourneyRoute] = []
    @State private var visitedCountries: [String] = []
    @State private var isPreparingData = false
    @State private var refreshGate = GlobeRefreshGate()
    @State private var didRequestInitialRefresh = false
    @State private var showMembershipGate = false
    @State private var isCapturingPoster = false

    /// Selected globe base-map style. MapboxGlobeView reads the same AppStorage
    /// key and reloads its style when this changes.
    @AppStorage("streetstamps.globe.mapTheme") private var globeThemeID = GlobeMapTheme.defaultID

    var body: some View {
        ZStack {
            MapboxGlobeView(
                isPresented: $dummyPresented,
                journeys: journeysForRender,
                visitedCountryISO2Override: visitedCountries,
                showsCloseButton: false
            )
            .ignoresSafeArea()

            // Pinch gate sits between the map and the UI controls so it
            // intercepts zoom attempts without blocking button taps.
            if !membership.isPremium {
                PinchGateCatcher { showMembershipGate = true }
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Hidden during capture so the poster screenshot is pure globe.
                if !isCapturingPoster { topHeader }
                Spacer()
                if !isCapturingPoster { themePicker }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.image])
        }
        .sheet(isPresented: $showMembershipGate) {
            MembershipGateView()
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
            guard !didRequestInitialRefresh else { return }
            didRequestInitialRefresh = true
            globeRefreshCoordinator.requestRefresh(reason: .globePageEntered)
        }
        .onChange(of: globeRefreshCoordinator.revision) { _, _ in
            refreshGlobeData()
        }
        // When pushed (e.g. from FootprintView's NavigationLink) the system adds
        // its own back button. Hide the nav bar so only our custom close (✕)
        // shows — dismiss() pops the push or dismisses the cover either way.
        // Globe is full-screen — hide both the nav bar and the app's bottom tab
        // bar while it's pushed (own ✕ dismisses).
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .navigationBarBackButtonHidden(true)
    }

    /// Horizontal carousel of base-map styles. Floats over the map on a dark
    /// glass pill so labels stay readable on any theme (light or dark).
    private var themePicker: some View {
        // Exactly 5 styles — distribute evenly across the width (no scrolling)
        // with larger swatches for a cleaner, more deliberate look.
        HStack(spacing: 0) {
            ForEach(GlobeMapTheme.all) { theme in
                let selected = globeThemeID == theme.id
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { globeThemeID = theme.id }
                } label: {
                    VStack(spacing: 7) {
                        globeSwatch(theme, selected: selected)
                        Text(L10n.t(theme.nameKey))
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundColor(selected ? FigmaTheme.text : FigmaTheme.subtext.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
    }

    private var mapboxToken: String {
        Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
    }

    /// Style picker thumbnail: a real Mapbox preview of the style (clipped to a
    /// circle for a globe feel), falling back to a simulated sphere while the
    /// image loads or offline.
    private func globeSwatch(_ theme: GlobeMapTheme, selected: Bool) -> some View {
        ZStack {
            if let url = theme.staticThumbnailURL(token: mapboxToken) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        simulatedSphere(theme)
                    }
                }
            } else {
                simulatedSphere(theme)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
        .overlay(
            Circle()
                .strokeBorder(selected ? theme.swatchAccent : .clear, lineWidth: 2.5)
                .padding(-3)
        )
        .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        .scaleEffect(selected ? 1.06 : 1.0)
    }

    /// Offline/loading fallback: a shaded sphere in the theme's base colour.
    private func simulatedSphere(_ theme: GlobeMapTheme) -> some View {
        ZStack {
            Circle().fill(theme.swatchBase)
            Circle().fill(
                RadialGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.55), Color.clear]),
                    center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: 28
                )
            )
            Circle().fill(
                RadialGradient(
                    gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.32)]),
                    center: UnitPoint(x: 0.72, y: 0.78), startRadius: 6, endRadius: 32
                )
            )
            Circle().fill(theme.swatchAccent)
                .frame(width: 12, height: 12)
                .offset(x: 6, y: -3)
        }
    }

    private var topHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                circleIconButton("xmark") { dismiss() }
                Spacer()
                circleIconButton("square.and.arrow.up") { shareGlobe() }
            }

            Text(visitedSummaryText)
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(FigmaTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func circleIconButton(_ systemName: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(highlighted ? .white : FigmaTheme.text)
                .frame(width: 38, height: 38)
                .background {
                    if highlighted {
                        Circle().fill(FigmaTheme.primary)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
                .appMinTapTarget()
        }
    }

    /// POSTER = a screenshot of the live 3D globe + a counts/brand strip. Hides
    /// the UI chrome for one frame, captures the window (drawHierarchy captures
    /// the Metal-backed globe), then composes the poster via ImageRenderer.
    private func shareGlobe() {
        // China-unified counts (Taiwan/HK/Macao fold into China).
        let isoSet = Set(visitedCountries.map { FootprintFactsBuilder.unifiedISO($0) })
        let countryCount = isoSet.count
        let cityCount = cityCache.cachedCities.filter { !($0.isTemporary ?? false) }.count

        isCapturingPoster = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000) // let chrome hide + globe redraw
            let globeImage = captureWindowImage()
            isCapturingPoster = false
            guard let globeImage else { return }
            // Sample the surround (top-centre, above the globe) so the poster's
            // panel matches the captured globe background exactly.
            let surround = globeImage.ss_pixelColor(atUnit: CGPoint(x: 0.5, y: 0.12)) ?? .white
            let poster = GlobeSharePoster(
                globeImage: globeImage,
                countryCount: countryCount,
                cityCount: cityCount,
                backgroundColor: Color(surround)
            )
            let renderer = ImageRenderer(content: poster)
            renderer.scale = 2
            if let image = renderer.uiImage {
                shareItem = GlobeShareImageItem(image: image)
            }
        }
    }

    private func captureWindowImage() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    /// "去过 N 个国家 · M 个城市" — shown in the top blank area.
    private var visitedSummaryText: String {
        let cityCount = cityCache.cachedCities.filter { !($0.isTemporary ?? false) }.count
        let countryCount = visitedCountries.count
        return String(format: L10n.t("globe_visited_summary"), countryCount, cityCount)
    }

    private func normalizedDisplayName(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.t("explorer_fallback") : value
    }

    private func refreshGlobeData() {
        var gate = refreshGate
        guard gate.startOrQueue() else {
            print("🟡 [GlobeScreen] refreshGlobeData GATED (already refreshing)")
            refreshGate = gate
            return
        }
        refreshGate = gate

        let countryISO2 = lifelogStore.countryISO2
        let external = externalJourneys
        let summary = store.journeys
        let tileSegments = trackTileStore.tiles(
            for: nil,
            zoom: TrackRenderAdapter.unifiedRenderZoom
        )
        let cityISO2 = cityCache.cachedCities
            .filter { $0.isTemporary != true }
            .compactMap { $0.countryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { $0.count == 2 }

        // Cache fast-path: when no external override is provided, the resolved
        // routes+countries are a deterministic function of (journey rev,
        // passive rev, tile-refresh rev). Re-entering Globe with unchanged
        // upstream data skips the entire passiveCountryRuns + resolve pipeline.
        // External override paths skip the cache because external journeys
        // are not part of the cache key.
        if external == nil {
            let cacheJourneyRev = store.trackTileRevision
            let cachePassiveRev = lifelogStore.trackTileRevision
            let cacheTileRev = trackTileStore.refreshRevision
            if let hit = GlobeDataCache.shared.get(
                journeyRevision: cacheJourneyRev,
                passiveRevision: cachePassiveRev,
                tileRefreshRevision: cacheTileRev
            ) {
                print("🟢 [GlobeScreen] cache HIT routes=\(hit.routes.count) countries=\(hit.countries.count)")
                journeysForRender = hit.routes
                visitedCountries = hit.countries
                isPreparingData = false
                var gate = refreshGate
                let shouldRefreshAgain = gate.finish()
                refreshGate = gate
                if shouldRefreshAgain {
                    refreshGlobeData()
                }
                return
            }
        }

        isPreparingData = true
        print("🟡 [GlobeScreen] refreshGlobeData START: tileSegments=\(tileSegments.count) summary=\(summary.count) external=\(external?.count ?? -1) country=\(countryISO2 ?? "nil")")
        Task(priority: .userInitiated) {
            let passiveCountryRuns = await lifelogStore.passiveCountryRuns()
            print("🟡 [GlobeScreen] passiveCountryRuns=\(passiveCountryRuns.count)")
            let previewRoutes = GlobeRouteResolver.resolve(
                externalJourneys: external,
                summaryJourneys: summary,
                segments: tileSegments,
                passiveCountryRuns: passiveCountryRuns,
                countryISO2: countryISO2
            )
            print("🟡 [GlobeScreen] previewRoutes=\(previewRoutes.count)")
            let previewCountries = Self.resolveVisitedCountries(routes: previewRoutes, cityISO2: cityISO2)

            await MainActor.run {
                journeysForRender = previewRoutes
                visitedCountries = previewCountries
            }

            let shouldFetchUnifiedSegments = GlobeRouteResolver.shouldFetchUnifiedSegments(tileSegments: tileSegments)
            guard shouldFetchUnifiedSegments else {
                await MainActor.run {
                    if external == nil {
                        GlobeDataCache.shared.store(
                            journeyRevision: store.trackTileRevision,
                            passiveRevision: lifelogStore.trackTileRevision,
                            tileRefreshRevision: trackTileStore.refreshRevision,
                            routes: previewRoutes,
                            countries: previewCountries
                        )
                    }
                    var gate = refreshGate
                    let shouldRefreshAgain = gate.finish()
                    refreshGate = gate
                    isPreparingData = false
                    if shouldRefreshAgain {
                        refreshGlobeData()
                    }
                }
                return
            }

            let segments = await UnifiedLifelogRenderProvider.segmentsAsync(
                journeyStore: store,
                lifelogStore: lifelogStore,
                zoom: TrackRenderAdapter.unifiedRenderZoom
            )
            let routes = GlobeRouteResolver.resolve(
                externalJourneys: external,
                summaryJourneys: summary,
                segments: segments,
                passiveCountryRuns: passiveCountryRuns,
                countryISO2: countryISO2
            )
            let countries = Self.resolveVisitedCountries(routes: routes, cityISO2: cityISO2)

            await MainActor.run {
                journeysForRender = routes
                visitedCountries = countries

                if external == nil {
                    GlobeDataCache.shared.store(
                        journeyRevision: store.trackTileRevision,
                        passiveRevision: lifelogStore.trackTileRevision,
                        tileRefreshRevision: trackTileStore.refreshRevision,
                        routes: routes,
                        countries: countries
                    )
                }

                var gate = refreshGate
                let shouldRefreshAgain = gate.finish()
                refreshGate = gate
                isPreparingData = false
                if shouldRefreshAgain {
                    refreshGlobeData()
                }
            }
        }
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
        // Shared canonicalization: China-unify (TW/HK/MO → CN) + dedup + sort,
        // identical to the footprint page so the two country counts always match.
        return FootprintFactsBuilder.canonicalVisitedISO2(Array(set))
    }

    private static func isoFromCityKey(_ cityKey: String?) -> String? {
        guard let cityKey else { return nil }
        let parts = cityKey.split(separator: "|", omittingEmptySubsequences: false)
        guard let raw = parts.last else { return nil }
        let iso = String(raw).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return iso.count == 2 ? iso : nil
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

private extension UIImage {
    /// Colour of the pixel at a unit point (0…1). Used to match the share
    /// poster's background to the captured globe's surround. The surround is
    /// near-grey/white so RGBA-vs-BGRA channel order is irrelevant here.
    func ss_pixelColor(atUnit p: CGPoint) -> UIColor? {
        guard let cg = cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let x = max(0, min(cg.width - 1, Int(CGFloat(cg.width) * p.x)))
        let y = max(0, min(cg.height - 1, Int(CGFloat(cg.height) * p.y)))
        let bpp = cg.bitsPerPixel / 8
        let offset = y * cg.bytesPerRow + x * bpp
        let c0 = CGFloat(ptr[offset]) / 255.0
        let c1 = CGFloat(ptr[offset + 1]) / 255.0
        let c2 = CGFloat(ptr[offset + 2]) / 255.0
        return UIColor(red: c0, green: c1, blue: c2, alpha: 1.0)
    }
}

// MARK: - Pinch Gate Catcher

/// Transparent overlay that detects 2-finger pinch gestures and fires a callback.
/// Single-finger pan/rotate pass through unaffected.
private struct PinchGateCatcher: UIViewRepresentable {
    let onPinch: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPinch = onPinch
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPinch: onPinch) }

    final class Coordinator: NSObject {
        var onPinch: () -> Void
        private var fired = false

        init(onPinch: @escaping () -> Void) { self.onPinch = onPinch }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                fired = false
            case .changed:
                if !fired {
                    fired = true
                    onPinch()
                }
            case .ended, .cancelled, .failed:
                fired = false
            default:
                break
            }
        }
    }
}
