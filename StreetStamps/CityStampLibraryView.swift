import Foundation
import SwiftUI
import MapKit
import MapboxMaps
import Turf
import Combine
import CoreLocation
import UIKit

enum FriendSharedEmptyStateStyle {
    static let titleFontSize: CGFloat = 18
    static let subtitleFontSize: CGFloat = 14
    static let verticalSpacing: CGFloat = 16
}

// =======================================================
// MARK: - CityStampLibraryView
// =======================================================

struct CityStampLibraryView: View {
    private struct CityDigest: Equatable {
        let id: String
        let countryISO2: String?
        let journeyIDs: [String]
        let explorations: Int
        let memories: Int
        let thumbnailBasePath: String?
        let thumbnailRoutePath: String?
        let boundaryCount: Int
        let hasAnchor: Bool

        init(_ city: CachedCity) {
            id = city.id
            countryISO2 = city.countryISO2
            journeyIDs = city.journeyIds
            explorations = city.explorations
            memories = city.memories
            thumbnailBasePath = city.thumbnailBasePath
            thumbnailRoutePath = city.thumbnailRoutePath
            boundaryCount = city.boundary?.count ?? 0
            hasAnchor = city.anchor != nil
        }
    }

    @StateObject private var vm = CityLibraryVM()
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cache: CityCache
    @EnvironmentObject private var renderCacheStore: CityRenderCacheStore
    @EnvironmentObject private var renderMaskStore: RenderMaskStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @State private var digestByCityID: [String: CityDigest] = [:]

    // ✅ Delete confirmations
    @State private var cityToDelete: City? = nil
    @State private var showDeleteCityAlert = false
    @State private var cityToEditName: City? = nil
    @State private var showEditNameAlert = false
    @State private var editedNameDraft = ""
    @State private var showPublicDetailUnavailableAlert = false
    @State private var activeCityDetail: City? = nil
    @State private var photoScanPulse = false
    @State private var photoScanTask: Task<Void, Never>?
    @State private var showMembershipGate = false
    @State private var showPhotoScanConfirm = false

    @AppStorage(MapLayerStyle.storageKey) private var layerStyleRaw = MapLayerStyle.current.rawValue
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var languagePreference = LanguagePreference.shared

    private var effectiveAppearanceRaw: String {
        layerStyleRaw
    }
    private let autoRebuildFromJourneyStore: Bool
    private let showHeader: Bool
    private let allowCityDetailNavigation: Bool
    private let headerTitle: String?
    private let emptyTitleKey: String
    private let emptySubtitleKey: String

    init(
        autoRebuildFromJourneyStore: Bool = false,
        showHeader: Bool = true,
        allowCityDetailNavigation: Bool = true,
        headerTitle: String? = nil,
        emptyTitleKey: String = "city_empty_title",
        emptySubtitleKey: String = "city_empty_desc"
    ) {
        self.autoRebuildFromJourneyStore = autoRebuildFromJourneyStore
        self.showHeader = showHeader
        self.allowCityDetailNavigation = allowCityDetailNavigation
        self.headerTitle = headerTitle
        self.emptyTitleKey = emptyTitleKey
        self.emptySubtitleKey = emptySubtitleKey
    }

    private var displayCities: [City] {
        if !vm.cities.isEmpty {
            return vm.cities
        }
        guard store.hasLoaded else { return [] }
        return CityLibraryVM.buildCities(journeyStore: store, cityCache: cache)
    }

    var body: some View {
        ZStack(alignment: .top) {
            UITheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if showHeader {
                    headerBar
                    Color.clear.frame(height: 6)
                }

                GeometryReader { geo in
                    ScrollView {
                        let sidePadding: CGFloat = 24
                        let colGap: CGFloat = 16
                        let rowGap: CGFloat = 24
                        let available = geo.size.width - sidePadding * 2 - colGap
                        let cardW = floor(available / 2)

                        cityGrid(cardW: cardW, colGap: colGap, rowGap: rowGap)
                            .padding(.horizontal, sidePadding)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
        .background(SwipeBackEnabler())
        .navigationBarBackButtonHidden(true)
        .onAppear {
            guard store.hasLoaded, vm.cities.isEmpty else { return }
            vm.load(journeyStore: store, cityCache: cache)
            digestByCityID = makeDigestMap(from: cache.cachedCities)
            StartupWarmupService.shared.start(cities: displayCities, appearanceRaw: effectiveAppearanceRaw, renderCacheStore: renderCacheStore, limit: 16, renderMaskByJourney: renderMaskStore.snapshot())
        }
        .onChange(of: store.hasLoaded) { _, loaded in
            if loaded {
                vm.load(journeyStore: store, cityCache: cache)
                digestByCityID = makeDigestMap(from: cache.cachedCities)
                StartupWarmupService.shared.start(cities: displayCities, appearanceRaw: effectiveAppearanceRaw, renderCacheStore: renderCacheStore, limit: 16, renderMaskByJourney: renderMaskStore.snapshot())
            }
        }
        .onChange(of: languagePreference.currentLanguage) { _, _ in
            guard store.hasLoaded else { return }
            vm.load(journeyStore: store, cityCache: cache)
        }
        .onReceive(cache.$cachedCities) { nextCities in
            guard store.hasLoaded else { return }

            let nextDigests = makeDigestMap(from: nextCities)
            if digestByCityID.isEmpty {
                vm.load(journeyStore: store, cityCache: cache)
                digestByCityID = nextDigests
                return
            }

            let previousKeys = Set(digestByCityID.keys)
            let nextKeys = Set(nextDigests.keys)

            let removed = previousKeys.subtracting(nextKeys)
            for key in removed {
                vm.removeCity(cityKey: key)
            }

            let maybeChanged = nextKeys.filter { digestByCityID[$0] != nextDigests[$0] }
            for key in maybeChanged {
                vm.upsertCity(cityKey: key, journeyStore: store, cityCache: cache)
            }

            digestByCityID = nextDigests
            StartupWarmupService.shared.start(cities: displayCities, appearanceRaw: effectiveAppearanceRaw, renderCacheStore: renderCacheStore, limit: 16, renderMaskByJourney: renderMaskStore.snapshot())
        }
        .alert(L10n.t("delete_city_alert_title"), isPresented: $showDeleteCityAlert, presenting: cityToDelete) { city in
            Button(L10n.t("delete"), role: .destructive) {
                let keys = city.sourceCityKeys.isEmpty ? [city.id] : city.sourceCityKeys
                for key in keys {
                    cache.deleteCity(id: key)
                    CityDisplayOverrideStore.shared.clear(for: key)
                }
                CityDisplayOverrideStore.shared.clear(for: city.id)
                vm.load(journeyStore: store, cityCache: cache)
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: { city in
            Text(String(format: L10n.t("delete_city_alert_message"), locale: Locale.current, city.localizedName))
        }
        .alert(L10n.t("city_edit_display_name_title"), isPresented: $showEditNameAlert, presenting: cityToEditName) { city in
            TextField(L10n.t("city_edit_display_name_placeholder"), text: $editedNameDraft)
            Button(L10n.t("save")) {
                CityDisplayOverrideStore.shared.setOverride(editedNameDraft, for: city.id)
                vm.load(journeyStore: store, cityCache: cache)
            }
            Button(L10n.t("reset"), role: .destructive) {
                CityDisplayOverrideStore.shared.clear(for: city.id)
                vm.load(journeyStore: store, cityCache: cache)
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: { _ in
            Text(L10n.t("city_edit_display_name_hint"))
        }
        .alert(L10n.t("details_unavailable_title"), isPresented: $showPublicDetailUnavailableAlert) {
            Button(L10n.t("ok"), role: .cancel) {}
        } message: {
            Text(L10n.t("details_unavailable_message"))
        }
        .fullScreenCover(item: $activeCityDetail) { city in
            CityDeepView(city: city)
        }
        .sheet(isPresented: $showMembershipGate) {
            MembershipGateView(feature: .photoCityDiscovery)
        }
        .alert(L10n.t("photo_scan_confirm_title"), isPresented: $showPhotoScanConfirm) {
            Button(L10n.t("photo_scan_confirm_start")) {
                if MembershipStore.shared.isPremium {
                    triggerPhotoDiscoveryScan()
                } else {
                    showMembershipGate = true
                }
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("photo_scan_confirm_message"))
        }
        .onChange(of: cache.photoDiscoveryProgress) { _, progress in
            if case .scanning = progress {
                photoScanPulse = true
            } else {
                photoScanPulse = false
            }
            if case .completed = progress {
                // Force full reload to ensure new photo cities appear immediately
                vm.load(journeyStore: store, cityCache: cache)
                digestByCityID = makeDigestMap(from: cache.cachedCities)
            }
        }
    }

    private func makeDigestMap(from cities: [CachedCity]) -> [String: CityDigest] {
        var out: [String: CityDigest] = [:]
        for city in cities where !(city.isTemporary ?? false) {
            out[city.id] = CityDigest(city)
        }
        return out
    }

    private var headerBar: some View {
        let titleText = (headerTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (headerTitle ?? "")
            : L10n.t("collection_segment_cities")
        return Group {
            HStack(spacing: 10) {
                AppBackButton(foreground: .black)

                Spacer()

                Text(titleText)
                    .appHeaderStyle()

                Spacer()

                if !hasEverScannedPhotos || isScanning {
                    Button {
                        if isScanning {
                            photoScanTask?.cancel()
                            photoScanTask = nil
                            return
                        }
                        showPhotoScanConfirm = true
                    } label: {
                        ZStack {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(UITheme.softBlack)
                                .frame(width: 42, height: 42)
                                .opacity(photoScanPulse ? 0.4 : 1.0)
                                .animation(
                                    isScanning ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                                    value: photoScanPulse
                                )
                        }
                    }
                } else {
                    Color.clear.frame(width: 42, height: 42)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FigmaTheme.border)
                    .frame(height: 1)
            }
        }
    }

    private func cityGrid(cardW: CGFloat, colGap: CGFloat, rowGap: CGFloat) -> some View {
        VStack(spacing: 0) {
            LazyVGrid(
                columns: [
                    GridItem(.fixed(cardW), spacing: colGap, alignment: .top),
                    GridItem(.fixed(cardW), spacing: 0, alignment: .top)
                ],
                spacing: rowGap
            ) {
                ForEach(Array(displayCities.enumerated()), id: \.element.id) { index, city in
                    if allowCityDetailNavigation {
                        Button {
                            activeCityDetail = city
                        } label: {
                            CityStampCard(city: city, cardWidth: cardW)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                cityToEditName = city
                                editedNameDraft = CityDisplayOverrideStore.shared.override(for: city.id) ?? city.localizedName
                                showEditNameAlert = true
                            } label: {
                                Label(L10n.t("city_edit_display_name"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                cityToDelete = city
                                showDeleteCityAlert = true
                            } label: {
                                Label(L10n.t("delete"), systemImage: "trash")
                            }
                        }
                        .scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.85))) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.2)
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                        }
                    } else {
                        Button {
                            showPublicDetailUnavailableAlert = true
                        } label: {
                            CityStampCard(city: city, cardWidth: cardW)
                        }
                        .buttonStyle(.plain)
                        .scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.85))) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.2)
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                        }
                    }
                }
            }

            // Scanning progress banner
            if case .scanning(let done, let total) = cache.photoDiscoveryProgress, total > 0 {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(format: L10n.t("photo_discovery_scanning"), done, total))
                        .font(.system(size: 12))
                        .foregroundColor(UITheme.subText)
                }
                .padding(.vertical, 8)
            }

            if case .noNewCities = cache.photoDiscoveryProgress {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13))
                    Text(L10n.t("photo_discovery_no_new_cities"))
                        .font(.system(size: 13))
                }
                .foregroundColor(UITheme.subText)
                .padding(.vertical, 10)
                .task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if case .noNewCities = cache.photoDiscoveryProgress {
                        cache.photoDiscoveryProgress = .idle
                    }
                }
            }

            if displayCities.isEmpty {
                emptyState(
                    title: L10n.key(emptyTitleKey),
                    subtitle: L10n.key(emptySubtitleKey)
                )
                .padding(.top, 40)
                .padding(.bottom, 60)
            }
        }
    }

    private func emptyState(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: 20) {
            ghostCityCard
                .frame(width: 140, height: 180)

            if allowCityDetailNavigation {
                Text(L10n.t("city_empty_explainer"))
                    .font(.system(size: FriendSharedEmptyStateStyle.subtitleFontSize))
                    .foregroundColor(UITheme.subText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                emptyStateActions
                    .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: FriendSharedEmptyStateStyle.titleFontSize, weight: .semibold))
                        .foregroundColor(UITheme.softBlack)

                    Text(subtitle)
                        .font(.system(size: FriendSharedEmptyStateStyle.subtitleFontSize))
                        .foregroundColor(UITheme.subText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var ghostCityCard: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
            )
            .foregroundColor(UITheme.subText.opacity(0.35))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.05))
            )
            .overlay(
                Image(systemName: "map")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(UITheme.subText.opacity(0.45))
            )
    }

    @ViewBuilder
    private var emptyStateActions: some View {
        Button {
            flow.requestSelectTab(.start)
        } label: {
            Text(L10n.t("city_empty_action_start"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FigmaTheme.primary)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 260)
        .padding(.horizontal, 24)
    }

    // MARK: - Photo discovery

    private var hasEverScannedPhotos: Bool {
        // Cheap existence check — never decode the full scan result from `body`.
        cache.hasPhotoScanResultOnDisk
    }

    private var photoDiscoveryIntroCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.blue.opacity(0.6))

            Text(L10n.t("photo_discovery_intro_title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(UITheme.softBlack)
                .multilineTextAlignment(.center)

            Text(L10n.t("photo_discovery_intro_subtitle"))
                .font(.system(size: 13))
                .foregroundColor(UITheme.subText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                triggerPhotoDiscoveryScan()
            } label: {
                Text(L10n.t("photo_discovery_intro_button"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
    }


    private var isScanning: Bool {
        if case .scanning = cache.photoDiscoveryProgress { return true }
        return false
    }

    private func triggerPhotoDiscoveryScan() {
        guard !isScanning else { return }
        photoScanPulse = true
        cache.photoDiscoveryProgress = .scanning(done: 0, total: 0)

        let cityCache = cache
        photoScanTask = Task {
            let previous = cityCache.loadPreviousPhotoScanResult()
            let result = await PhotoCityDiscoveryService.shared.scan(
                previousResult: previous,
                onProgress: { done, total in
                    Task { @MainActor in
                        cityCache.photoDiscoveryProgress = .scanning(done: done, total: total)
                    }
                }
            )

            photoScanPulse = false
            photoScanTask = nil
            guard let result else {
                cityCache.photoDiscoveryProgress = .idle
                return
            }

            let oldKeys = Set(previous?.cities.map { $0.cityKey } ?? [])
            let newCities = result.cities
                .filter { !oldKeys.contains($0.cityKey) }
                .map { $0.cityName }

            cityCache.applyPhotoDiscoveredCities(result.cities, scanResult: result)

            if !newCities.isEmpty {
                cityCache.photoDiscoveryProgress = .completed(newCities: newCities)
            } else {
                cityCache.photoDiscoveryProgress = .noNewCities
            }
        }
    }

}

// =======================================================
// MARK: - City Card
// =======================================================

struct CityStampCard: View {
    let city: City
    let cardWidth: CGFloat

    private let imageH: CGFloat = 120
    private let textH: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            CityThumbnailView(
                city: city,
                basePath: city.thumbnailBasePath,
                routePath: city.thumbnailRoutePath
            )
            .frame(width: cardWidth, height: imageH)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(city.localizedName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(UITheme.softBlack)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 6)

                    if let iso = city.countryISO2, !iso.isEmpty {
                        Text(iso)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(UITheme.subText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(UITheme.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .fixedSize(horizontal: true, vertical: true)
                    }
                }

                statsLine
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: cardWidth, height: textH, alignment: .leading)
        }
        .background(UITheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(UITheme.cardStroke, lineWidth: 0.8)
        )
    }

    private var statsLine: some View {
        let text: String
        if city.isPhotoDiscovered {
            let count = city.photoCount ?? 0
            let countText = String(format: L10n.t("photo_count_format"), count)
            if let range = city.photoDateRange, !range.isEmpty {
                text = "\(countText) · \(range)"
            } else {
                text = countText
            }
        } else {
            text = String(format: L10n.t("city_card_stats"), city.explorations, city.memories)
        }

        return Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundColor(UITheme.subText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }
}

// =======================================================
// MARK: - Photo discovery scan button (reusable)
// =======================================================

struct PhotoDiscoveryScanButton: View {
    @ObservedObject var cityCache: CityCache
    @State private var pulse = false
    @State private var scanTask: Task<Void, Never>?
    @State private var showConfirm = false
    @State private var showMembershipGate = false

    private var isScanning: Bool {
        if case .scanning = cityCache.photoDiscoveryProgress { return true }
        return false
    }

    var body: some View {
        Button {
            if isScanning {
                scanTask?.cancel()
                scanTask = nil
                return
            }
            showConfirm = true
        } label: {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(UITheme.softBlack)
                .frame(width: 42, height: 42)
                .opacity(pulse ? 0.4 : 1.0)
                .animation(
                    isScanning ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                    value: pulse
                )
        }
        .onChange(of: cityCache.photoDiscoveryProgress) { _, progress in
            if case .scanning = progress {
                pulse = true
            } else {
                pulse = false
            }
        }
        .alert(L10n.t("photo_scan_confirm_title"), isPresented: $showConfirm) {
            Button(L10n.t("photo_scan_confirm_start")) {
                if MembershipStore.shared.isPremium {
                    triggerScan()
                } else {
                    showMembershipGate = true
                }
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("photo_scan_confirm_message"))
        }
        .sheet(isPresented: $showMembershipGate) {
            MembershipGateView(feature: .photoCityDiscovery)
        }
    }

    @State private var lastScanTime: Date = .distantPast

    private func triggerScan() {
        guard !isScanning else { return }
        // 60s cooldown to avoid repeated taps
        guard Date().timeIntervalSince(lastScanTime) > 60 else { return }
        lastScanTime = Date()
        pulse = true
        cityCache.photoDiscoveryProgress = .scanning(done: 0, total: 0)

        let cache = cityCache
        scanTask = Task {
            let previous = cache.loadPreviousPhotoScanResult()
            let result = await PhotoCityDiscoveryService.shared.scan(
                previousResult: previous,
                onProgress: { done, total in
                    Task { @MainActor in
                        cache.photoDiscoveryProgress = .scanning(done: done, total: total)
                    }
                }
            )

            pulse = false
            scanTask = nil
            guard let result else {
                cache.photoDiscoveryProgress = .idle
                return
            }

            let oldKeys = Set(previous?.cities.map { $0.cityKey } ?? [])
            let newCities = result.cities
                .filter { !oldKeys.contains($0.cityKey) }
                .map { $0.cityName }

            cache.applyPhotoDiscoveredCities(result.cities, scanResult: result)

            if !newCities.isEmpty {
                cache.photoDiscoveryProgress = .completed(newCities: newCities)
            } else {
                cache.photoDiscoveryProgress = .noNewCities
            }
        }
    }
}

// =======================================================
// MARK: - Render throttle
// =======================================================

/// Limits concurrent MKMapSnapshotter / Mapbox snapshot requests to avoid
/// tile-server rate-limiting (which can make renders fail outright).
private actor RenderThrottle {
    static let shared = RenderThrottle(limit: 4)

    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func release() {
        active -= 1
        if !waiters.isEmpty {
            active += 1
            waiters.removeFirst().resume()
        }
    }
}

// =======================================================
// MARK: - In-memory image cache
// =======================================================

final class CityImageMemoryCache: @unchecked Sendable {
    nonisolated static let shared = CityImageMemoryCache()
    private init() {
        cache.countLimit = 220
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    private let cache = NSCache<NSString, UIImage>()

    nonisolated func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    nonisolated func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: cost(of: image))
    }

    nonisolated func removeAll() {
        cache.removeAllObjects()
    }

    nonisolated private func cost(of image: UIImage) -> Int {
        let w = Int(image.size.width * image.scale)
        let h = Int(image.size.height * image.scale)
        return max(1, w * h * 4)
    }
}

// =======================================================
// MARK: - City thumbnail debug logging
// =======================================================

@MainActor
final class CityThumbnailDebugLogger {
    static let shared = CityThumbnailDebugLogger()

    enum LogKind {
        case keyFirstSeen
        case keyChanged
        case keySame
        case memoryHit
        case diskHit
        case renderMiss
        case renderComplete
        case cancel

        var logsByDefault: Bool {
            switch self {
            case .keyFirstSeen, .keyChanged, .diskHit, .renderMiss:
                return true
            case .keySame, .memoryHit, .renderComplete, .cancel:
                return false
            }
        }
    }

    struct RenderKeyParts: Equatable {
        let fullKey: String
        let journeySignature: String
        let boundarySignature: String
        let anchorSignature: String
    }

    private var lastPartsByCityID: [String: RenderKeyParts] = [:]

    private init() {}

    var isEnabled: Bool {
#if DEBUG
        return launchArguments.contains("-CityThumbnailDebug")
            || UserDefaults.standard.bool(forKey: "city.thumbnail.debug.enabled")
#else
        return false
#endif
    }

    private var isVerboseEnabled: Bool {
#if DEBUG
        return launchArguments.contains("-CityThumbnailDebugVerbose")
            || UserDefaults.standard.bool(forKey: "city.thumbnail.debug.verbose")
#else
        return false
#endif
    }

    private var launchArguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private var cityFilter: String? {
        if let index = launchArguments.firstIndex(of: "-CityThumbnailDebugCity"),
           launchArguments.indices.contains(index + 1) {
            let value = launchArguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    func log(_ kind: LogKind, cityID: String? = nil, _ message: String) {
        guard isEnabled else { return }
        guard kind.logsByDefault || isVerboseEnabled else { return }
        if let filter = cityFilter, let cityID, cityID != filter { return }
        let line = "🧭 [CityThumb] \(message)"
        print(line)
        appendToFile(line)
    }

    private func appendToFile(_ line: String) {
        guard let url = logFileURL() else { return }
        let payload = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        let data = Data(payload.utf8)

        if FileManager.default.fileExists(atPath: url.path) == false {
            try? data.write(to: url, options: .atomic)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Ignore debug logging failures.
        }
    }

    private func logFileURL() -> URL? {
        FileManager.default.temporaryDirectory.appendingPathComponent("city-thumbnail-debug.log", isDirectory: false)
    }

    func recordRenderKey(cityID: String, cityName: String, appearanceRaw: String, parts: RenderKeyParts) {
        guard isEnabled else { return }
        if let filter = cityFilter, cityID != filter { return }

        if let previous = lastPartsByCityID[cityID] {
            if previous == parts {
                log(.keySame, cityID: cityID, "key_same city=\(cityID) name=\(cityName) appearance=\(appearanceRaw)")
            } else {
                let changedSections = [
                    previous.journeySignature != parts.journeySignature ? "journey" : nil,
                    previous.boundarySignature != parts.boundarySignature ? "boundary" : nil,
                    previous.anchorSignature != parts.anchorSignature ? "anchor" : nil
                ]
                .compactMap { $0 }
                .joined(separator: ",")

                log(
                    .keyChanged,
                    cityID: cityID,
                    """
                    key_changed city=\(cityID) name=\(cityName) appearance=\(appearanceRaw) changed=\(changedSections)
                       old.key=\(previous.fullKey)
                       new.key=\(parts.fullKey)
                       old.journey=\(previous.journeySignature)
                       new.journey=\(parts.journeySignature)
                       old.boundary=\(previous.boundarySignature)
                       new.boundary=\(parts.boundarySignature)
                       old.anchor=\(previous.anchorSignature)
                       new.anchor=\(parts.anchorSignature)
                    """
                )
            }
        } else {
            log(
                .keyFirstSeen,
                cityID: cityID,
                """
                key_first_seen city=\(cityID) name=\(cityName) appearance=\(appearanceRaw)
                   key=\(parts.fullKey)
                   journey=\(parts.journeySignature)
                   boundary=\(parts.boundarySignature)
                   anchor=\(parts.anchorSignature)
                """
            )
        }

        lastPartsByCityID[cityID] = parts
    }
}

// =======================================================
// MARK: - CityThumbnailView
// =======================================================

struct CityThumbnailView: View {
    let city: City?
    let basePath: String?
    let routePath: String?

    @AppStorage(MapLayerStyle.storageKey) private var layerStyleRaw = MapLayerStyle.current.rawValue
    @EnvironmentObject private var renderCacheStore: CityRenderCacheStore
    @EnvironmentObject private var renderMaskStore: RenderMaskStore
    @StateObject private var loader = CityThumbnailLoader()

    init(city: City? = nil, basePath: String?, routePath: String?) {
        self.city = city
        self.basePath = basePath
        self.routePath = routePath
    }

    /// Use the full layer style raw value as cache key so thumbnails update on every style switch.
    private var effectiveAppearanceRaw: String {
        layerStyleRaw
    }

    /// Snapshot of the user's render mask. Driven by `maskRevision` so the
    /// view re-evaluates `loadKey` when the mask changes.
    private var maskSnapshot: [String: Set<Int>] {
        _ = renderMaskStore.maskRevision
        return renderMaskStore.snapshot()
    }

    private var loadKey: String {
        // For city-mode rendering, use the full render key so any journey data change
        // (new journey added, distance updated, etc.) triggers a reload. Mask
        // sig is part of the render key so cleanups in CityDeepView invalidate
        // this thumbnail next time we appear.
        if let city {
            return CityThumbnailLoader.renderCacheKey(for: city, appearanceRaw: effectiveAppearanceRaw, renderMaskByJourney: maskSnapshot)
        }
        return "\(routePath ?? "")||\(basePath ?? "")||\(effectiveAppearanceRaw)"
    }

    var body: some View {
        let snapshot = maskSnapshot
        let syncCachedImage = CityThumbnailLoader.existingCachedImage(
            city: city,
            routePath: routePath,
            basePath: basePath,
            appearanceRaw: effectiveAppearanceRaw,
            renderCacheStore: renderCacheStore,
            renderMaskByJourney: snapshot
        )

        Group {
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if let syncCachedImage {
                Image(uiImage: syncCachedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Button {
                    loader.forceReload(city: city, routePath: routePath, basePath: basePath, appearanceRaw: effectiveAppearanceRaw, renderCacheStore: renderCacheStore, renderMaskByJourney: snapshot)
                } label: {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: loader.renderFailed ? "arrow.clockwise.circle" : "map")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(UITheme.accent.opacity(0.6))

                                Text(L10n.key(loader.renderFailed ? "city_thumbnail_tap_to_retry" : "preparing_map"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color.black.opacity(0.35))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .allowsTightening(true)
                            }
                            .padding(.horizontal, 10)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!loader.renderFailed)
            }
        }
        .task(id: loadKey) {
            loader.load(city: city, routePath: routePath, basePath: basePath, appearanceRaw: effectiveAppearanceRaw, renderCacheStore: renderCacheStore, renderMaskByJourney: snapshot)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

// =======================================================
// MARK: - CityThumbnailLoader
// =======================================================

@MainActor
final class CityThumbnailLoader: ObservableObject {
    @Published var image: UIImage?
    /// True after at least one render attempt completed without an image. Drives
    /// the placeholder UI to surface a "tap to retry" affordance instead of the
    /// neutral "preparing map" copy. Reset on success or on `forceReload`.
    @Published private(set) var renderFailed = false
    private var currentKey: String?
    /// Tracks the render key that produced the current `image`.
    /// Survives `cancel()` so we can skip redundant reloads.
    private var renderedKey: String?
    private var renderTask: Task<Void, Never>?

    private nonisolated static let cityFocusRadiusMeters: CLLocationDistance = 80_000
    private nonisolated static let cityFocusWindowMeters: CLLocationDistance = 40_000
    private nonisolated static let cityFocusMinPoints = 2
    private nonisolated static let cityFocusWindowMaxPoints = 80
    private nonisolated static let boundaryTrustMaxDistanceMeters: CLLocationDistance = 120_000
    private nonisolated static let boundaryTrustMaxSpanDegrees: CLLocationDegrees = 3.0

    func load(city: City?, routePath: String?, basePath: String?, appearanceRaw: String, renderCacheStore: CityRenderCacheStore, renderMaskByJourney: [String: Set<Int>] = [:]) {
        // City cards use render-keyed persistent caching first, then render on miss.
        if let city {
            let coordCounts = city.journeys.prefix(5).map { ($0.id.prefix(8), $0.coordinates.count, $0.correctedCoordinates.count, $0.matchedCoordinates.count, $0.allCLCoords.count) }
            print("[CityThumbnail] LOAD city=\(city.id) appearance=\(appearanceRaw) journeys=\(city.journeys.count) coords=\(coordCounts)")
            let renderKeyParts = Self.renderKeyParts(for: city, appearanceRaw: appearanceRaw, renderMaskByJourney: renderMaskByJourney)
            let renderKey = renderKeyParts.fullKey
            CityThumbnailDebugLogger.shared.recordRenderKey(
                cityID: city.id,
                cityName: city.localizedName,
                appearanceRaw: appearanceRaw,
                parts: renderKeyParts
            )
            // Fast path: same key, image already rendered — nothing to do.
            // Must also check renderedKey: after cancel(), currentKey is preserved
            // but the render never completed, so we must not skip the re-render.
            if currentKey == renderKey, renderedKey == renderKey, image != nil { return }
            // Also skip if we already rendered this exact key (survives cancel()).
            if renderedKey == renderKey, image != nil {
                currentKey = renderKey
                return
            }
            currentKey = renderKey
            renderTask?.cancel()
            renderTask = nil
            if let cached = CityImageMemoryCache.shared.image(forKey: renderKey) {
                print("[CityThumbnail] LOAD city=\(city.id) cache=MEMORY_HIT key=\(renderKey)")
                CityThumbnailDebugLogger.shared.log(
                    .memoryHit,
                    cityID: city.id,
                    "load city=\(city.id) source=memory_hit key=\(renderKey)"
                )
                image = cached
                renderedKey = renderKey
                return
            }

            if let diskCached = renderCacheStore.image(forKey: renderKey) {
                print("[CityThumbnail] LOAD city=\(city.id) cache=DISK_HIT key=\(renderKey)")
                CityThumbnailDebugLogger.shared.log(
                    .diskHit,
                    cityID: city.id,
                    "load city=\(city.id) source=disk_hit key=\(renderKey)"
                )
                CityImageMemoryCache.shared.set(diskCached, forKey: renderKey)
                image = diskCached
                renderedKey = renderKey
                return
            }

            print("[CityThumbnail] LOAD city=\(city.id) cache=MISS_WILL_RENDER key=\(renderKey)")
            CityThumbnailDebugLogger.shared.log(
                .renderMiss,
                cityID: city.id,
                "load city=\(city.id) source=render_miss key=\(renderKey)"
            )
            // The previously displayed image (if any) belongs to a different render
            // key — typically a different appearance/layer. If we keep showing it
            // while the new key renders, a slow or failing render leaves the user
            // looking at the old layer's content with no signal that anything is
            // happening. Drop to placeholder immediately on key change so the
            // tap-to-retry affordance and "preparing map" copy reflect reality.
            // The early returns above already short-circuited any stale-key/image
            // pair where renderedKey matches renderKey, so clearing here only
            // affects genuine cross-key transitions.
            if renderedKey != renderKey {
                image = nil
            }
            renderOnDemand(city: city, appearanceRaw: appearanceRaw, key: renderKey, renderCacheStore: renderCacheStore, renderMaskByJourney: renderMaskByJourney)
            return
        }

        // Fallback for legacy payload surfaces.
        let sources = [routePath, basePath].compactMap { $0 }
        guard !sources.isEmpty else {
            image = nil
            currentKey = nil
            return
        }

        var orderedCandidates: [String] = []
        var seen = Set<String>()
        for source in sources {
            for key in candidateKeys(from: source, appearanceRaw: appearanceRaw) {
                if seen.insert(key).inserted { orderedCandidates.append(key) }
            }
        }

        guard let chosen = orderedCandidates.first(where: { CityThumbnailCache.thumbnailExists($0) }) else {
            image = nil
            currentKey = nil
            return
        }

        if currentKey == chosen, image != nil { return }
        currentKey = chosen

        if let cached = CityImageMemoryCache.shared.image(forKey: chosen) {
            image = cached
            return
        }

        guard let fullPath = CityThumbnailCache.resolveFullPath(chosen) else {
            image = nil
            return
        }

        Task.detached(priority: .utility) { [chosen, fullPath] in
            guard FileManager.default.fileExists(atPath: fullPath),
                  let img = UIImage(contentsOfFile: fullPath) else {
                await MainActor.run {
                    if self.currentKey == chosen { self.image = nil }
                }
                return
            }

            CityImageMemoryCache.shared.set(img, forKey: chosen)
            await MainActor.run {
                if self.currentKey == chosen { self.image = img }
            }
        }
    }

    func cancel() {
        CityThumbnailDebugLogger.shared.log(.cancel, "cancel key=\(currentKey ?? "nil")")
        renderTask?.cancel()
        renderTask = nil
        // Intentionally keep currentKey and image so re-appear is instant.
    }

    nonisolated static func renderCacheKey(for city: City, appearanceRaw: String, renderMaskByJourney: [String: Set<Int>] = [:]) -> String {
        renderKeyParts(for: city, appearanceRaw: appearanceRaw, renderMaskByJourney: renderMaskByJourney).fullKey
    }

    nonisolated static func renderKeyParts(for city: City, appearanceRaw: String, renderMaskByJourney: [String: Set<Int>] = [:]) -> CityThumbnailDebugLogger.RenderKeyParts {
        let journeySignature = city.journeys
            .sorted { $0.id < $1.id }
            .map(journeySignature)
            .joined(separator: "~")
        let boundarySignature = "ignored-for-cache"
        let anchorSignature = "ignored-for-cache"
        // v11: dropped the isBlankImage pixel heuristic (no more false-rejected
        // uniform maps → no infinite-retry cards) + satellite thumbnails render at
        // scale 3 (sharper raster).
        // v12: invalidate blank thumbnails poisoned on cold start. v11 trusted Mapbox's
        // .success unconditionally, so a Mapbox "success-but-unrendered" frame got cached
        // as a permanent blank. ensurePersistentCache now rejects fully-uniform frames for
        // route-bearing cities before caching; bump to force a re-render of any blank
        // already saved to disk under v11.
        // v13: extend the uniform-frame rejection to route-less (photo-discovered) cities.
        // v12 only guarded route-bearing cities, so a Mapbox cold-start blank frame for a
        // photo city slipped through and was cached permanently (renderedKey set → never
        // retried). Bump to flush any blank photo-city thumbnail already saved under v12.
        let styleVersion = 13
        let colorVersion = (MapLayerStyle(rawValue: appearanceRaw) ?? .mutedDark).isSatelliteStyle ? 2 : 1
        // Include only the masks for journeys that belong to this city, so
        // edits to one city's polylines don't invalidate every other city's
        // thumbnail cache.
        let maskSig: String = {
            guard !renderMaskByJourney.isEmpty else { return "" }
            let parts: [String] = city.journeys
                .compactMap { j -> String? in
                    guard let mask = renderMaskByJourney[j.id], !mask.isEmpty else { return nil }
                    return "\(j.id)#" + mask.sorted().map(String.init).joined(separator: ",")
                }
                .sorted()
            return parts.isEmpty ? "" : "|m=\(parts.joined(separator: ";"))"
        }()
        let fullKey = "render|v\(styleVersion)c\(colorVersion)|\(city.id)|\(appearanceRaw)|\(journeySignature)\(maskSig)"
        return CityThumbnailDebugLogger.RenderKeyParts(
            fullKey: fullKey,
            journeySignature: journeySignature,
            boundarySignature: boundarySignature,
            anchorSignature: anchorSignature
        )
    }

    nonisolated static func renderCacheRelativePath(forKey key: String) -> String {
        let hash = stableHash(key)
        // Extract a short human-readable prefix (city ID) for easier debugging.
        let parts = key.split(separator: "|")
        let prefix = parts.count >= 4 ? safeFilenameComponent(String(parts[2])) : "unknown"
        return "city_\(prefix)_\(hash).jpg"
    }

    /// Stable 64-bit hash encoded as lowercase hex. Does not rely on Swift's
    /// `Hashable` (which is randomised per process) — uses FNV-1a instead.
    nonisolated private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 14695981039346656037 // FNV offset basis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211 // FNV prime
        }
        return String(hash, radix: 16, uppercase: false)
    }

    nonisolated static func existingPersistentCache(
        for city: City,
        appearanceRaw: String,
        renderCacheStore: CityRenderCacheStore,
        renderMaskByJourney: [String: Set<Int>] = [:]
    ) -> UIImage? {
        let key = renderCacheKey(for: city, appearanceRaw: appearanceRaw, renderMaskByJourney: renderMaskByJourney)
        if let cached = CityImageMemoryCache.shared.image(forKey: key) {
            return cached
        }
        if let diskCached = renderCacheStore.image(forKey: key) {
            CityImageMemoryCache.shared.set(diskCached, forKey: key)
            return diskCached
        }
        return nil
    }

    nonisolated static func existingCachedImage(
        city: City?,
        routePath: String?,
        basePath: String?,
        appearanceRaw: String,
        renderCacheStore: CityRenderCacheStore,
        renderMaskByJourney: [String: Set<Int>] = [:]
    ) -> UIImage? {
        if let city {
            return existingPersistentCache(
                for: city,
                appearanceRaw: appearanceRaw,
                renderCacheStore: renderCacheStore,
                renderMaskByJourney: renderMaskByJourney
            )
        }

        let sources = [routePath, basePath].compactMap { $0 }
        guard !sources.isEmpty else { return nil }

        var orderedCandidates: [String] = []
        var seen = Set<String>()
        for source in sources {
            for key in legacyCandidateKeys(from: source, appearanceRaw: appearanceRaw) {
                if seen.insert(key).inserted { orderedCandidates.append(key) }
            }
        }

        for chosen in orderedCandidates {
            if let cached = CityImageMemoryCache.shared.image(forKey: chosen) {
                return cached
            }

            guard let fullPath = CityThumbnailCache.resolveFullPath(chosen),
                  FileManager.default.fileExists(atPath: fullPath),
                  let diskCached = UIImage(contentsOfFile: fullPath) else {
                continue
            }

            CityImageMemoryCache.shared.set(diskCached, forKey: chosen)
            return diskCached
        }

        return nil
    }

    nonisolated static func ensurePersistentCache(for city: City, appearanceRaw: String, renderCacheStore: CityRenderCacheStore, renderMaskByJourney: [String: Set<Int>] = [:]) async {
        let entryCounts = city.journeys.prefix(5).map { ($0.id.prefix(8), $0.coordinates.count, $0.allCLCoords.count) }
        print("[CityThumbnail] ENSURE city=\(city.id) appearance=\(appearanceRaw) journeys=\(city.journeys.count) coords=\(entryCounts)")
        let key = renderCacheKey(for: city, appearanceRaw: appearanceRaw, renderMaskByJourney: renderMaskByJourney)
        if CityImageMemoryCache.shared.image(forKey: key) != nil {
            await MainActor.run {
                CityThumbnailDebugLogger.shared.log(
                    .memoryHit,
                    cityID: city.id,
                    "ensurePersistentCache city=\(city.id) source=memory_hit key=\(key)"
                )
            }
            return
        }
        if let diskCached = renderCacheStore.image(forKey: key) {
            CityImageMemoryCache.shared.set(diskCached, forKey: key)
            await MainActor.run {
                CityThumbnailDebugLogger.shared.log(
                    .diskHit,
                    cityID: city.id,
                    "ensurePersistentCache city=\(city.id) source=disk_hit key=\(key)"
                )
            }
            return
        }

        await MainActor.run {
            CityThumbnailDebugLogger.shared.log(
                .renderMiss,
                cityID: city.id,
                "ensurePersistentCache city=\(city.id) source=render_miss key=\(key)"
            )
        }

        let fetchedBoundary = await CityBoundaryService.shared.boundaryPolygon(
            cityKey: city.id,
            cityName: city.localizedName,
            countryISO2: city.countryISO2,
            anchor: city.anchor ?? city.journeys.first?.allCLCoords.first
        )

        // Substitute the city's journeys with mask-applied splits so the
        // thumbnail polylines reflect the user's render mask. Original
        // journey data on disk is untouched.
        let maskedCity: City
        if !renderMaskByJourney.isEmpty,
           city.journeys.contains(where: { (renderMaskByJourney[$0.id] ?? []).isEmpty == false }) {
            var copy = city
            copy.journeys = city.journeys.flatMap { $0.applyingRenderMaskSplit(renderMaskByJourney[$0.id] ?? []) }
            maskedCity = copy
        } else {
            maskedCity = city
        }

        let hasRoutes = !maskedCity.journeys.isEmpty
        await RenderThrottle.shared.acquire()

        // ROOT-CAUSE FIX (recurring "card won't load / retry does nothing"):
        // A non-nil result here means the renderer SUCCEEDED — MKMapSnapshotter only
        // calls back a snapshot once its tiles have loaded, and Mapbox
        // Snapshotter.start() completes only after the requested tiles render. The
        // real "the whole thumbnail loaded no map at all" failure surfaces as nil
        // (tile/style error, invalid region, or our own timeout), which we treat as
        // failure below and let scheduleRetry handle.
        //
        // We deliberately do NOT pixel-inspect the result to second-guess success.
        // The previous isBlankImage heuristic sampled 9 pixels and rejected "uniform"
        // frames, but a flat frame is fundamentally ambiguous: it looks identical for
        // "tiles never loaded" and for a perfectly valid map over open sea / desert /
        // a sparse dark area. That ambiguity made it false-reject real renders whose
        // thin route missed the sampled points (and even route-less ocean/desert
        // cities), returning nil → renderFailed → infinite deterministic retry where
        // even manual "tap to retry" just restarted the same failure. Pixels can't
        // tell blank-failure from uniform-terrain, so trust the renderer's own
        // success/failure signal instead — with ONE narrow exception applied after the
        // render below: a route-bearing city whose frame is 100% one flat colour. That is
        // unambiguous (a drawn route would paint pixels), and it specifically catches
        // Mapbox returning .success with an unrendered cold-start frame. See the
        // isFullyUniformFrame guard before caching.
        let primary = await Self.makeSnapshot(city: maskedCity, appearanceRaw: appearanceRaw, fetchedBoundary: fetchedBoundary)
        let candidate: UIImage?
        if primary != nil {
            candidate = primary
        } else if !hasRoutes {
            // Route-less (photo-discovered) city: primary failed, so try a plain wider
            // map tile centered on the city before giving up.
            candidate = await Self.makeFallbackSnapshot(city: maskedCity, appearanceRaw: appearanceRaw)
        } else {
            candidate = nil
        }
        let img: UIImage? = candidate

        await RenderThrottle.shared.release()

        guard let img else { return }

        // A rendered frame that is a single flat colour means the renderer reported success
        // but the tiles/route never rasterised — observed with Mapbox Snapshotter on cold
        // start, which can return .success with an unrendered frame (see makeMapboxSnapshot).
        // Caching it would persist a blank thumbnail on disk forever (renderedKey gets set →
        // never retried). Do NOT cache it: returning here leaves the cache empty so
        // renderOnDemand/scheduleRetry re-render on a now-warm GPU instead.
        //
        // This applies to BOTH route-bearing and route-less (photo-discovered) cities. The
        // v12 guard was route-bearing only, on the theory that a uniform-terrain map over
        // open sea/desert is a legitimate blank-looking frame for a route-less city. But
        // photo-discovered cities are by definition populated places the user photographed,
        // so a real render is never a single flat colour; whereas a Mapbox cold-start blank
        // frame for such a city was silently cached forever. False-rejecting here only costs
        // a retry (capped at maxAutoRetries → "tap to retry"), which is strictly better than
        // a permanent silent blank. Still requires the WHOLE frame to be one colour.
        if Self.isFullyUniformFrame(img) {
            await MainActor.run {
                CityThumbnailDebugLogger.shared.log(
                    .renderMiss,
                    cityID: city.id,
                    "ensurePersistentCache city=\(city.id) action=rejected_blank_frame key=\(key)"
                )
            }
            print("[CityThumbnail] ▶ rejected uniform/blank frame city=\(city.id) (treated as render failure → retry)")
            return
        }

        CityImageMemoryCache.shared.set(img, forKey: key)
        // Satellite/hybrid are photographic: JPEG 0.82 softens them visibly. Persist raster
        // styles near-lossless; vector styles stay at the default quality (flat colours
        // survive JPEG fine and it keeps disk use down).
        let isRasterStyle = (MapLayerStyle(rawValue: appearanceRaw) ?? .mutedDark).isSatelliteStyle
        renderCacheStore.save(img, forKey: key, highQuality: isRasterStyle)
        await MainActor.run {
            CityThumbnailDebugLogger.shared.log(
                .renderComplete,
                cityID: city.id,
                "ensurePersistentCache city=\(city.id) action=saved_to_disk key=\(key)"
            )
        }
    }

    /// Background retry counter. Resets on every fresh `renderOnDemand` (i.e. when
    /// `.task(id:)` re-fires after the cell scrolls back into view, or on user
    /// `forceReload`). Auto-retry is capped at `maxAutoRetries` because deterministic
    /// failures (specific city + style combo that just won't render) gain nothing
    /// from indefinite background retries — they only waste battery. Once the cap
    /// is hit, the placeholder surfaces "tap to retry" and waits for the user.
    private var renderRetryCount = 0
    /// First retry is fast: failures right after a style switch / many cards loading
    /// at once are usually transient tile-server contention that clears in ~1–2s, so
    /// waiting the full backoff feels like the card is stuck. Retry quickly once, then
    /// fall back to exponential backoff for genuinely persistent failures.
    private static let firstRetryDelaySec: Double = 1.2
    private static let initialRetryDelaySec: Double = 5
    private static let maxRetryDelaySec: Double = 600
    private static let maxAutoRetries = 5

    private func renderOnDemand(city: City, appearanceRaw: String, key: String, renderCacheStore: CityRenderCacheStore, renderMaskByJourney: [String: Set<Int>] = [:]) {
        renderTask?.cancel()
        renderRetryCount = 0
        renderTask = Task(priority: .utility) { [city, appearanceRaw, key, renderMaskByJourney] in
            await Self.ensurePersistentCache(for: city, appearanceRaw: appearanceRaw, renderCacheStore: renderCacheStore, renderMaskByJourney: renderMaskByJourney)
            guard !Task.isCancelled else { return }
            let img = CityImageMemoryCache.shared.image(forKey: key) ?? renderCacheStore.image(forKey: key)
            await MainActor.run {
                guard self.currentKey == key else { return }
                CityThumbnailDebugLogger.shared.log(
                    .renderComplete,
                    cityID: city.id,
                    "render_complete city=\(city.id) image=\(img == nil ? "nil" : "ready") key=\(key)"
                )
                if let img {
                    self.image = img
                    self.renderedKey = key
                    self.renderRetryCount = 0
                    self.renderFailed = false
                } else {
                    // Render failed — keep the placeholder visible. Queue a
                    // background retry up to maxAutoRetries; beyond that, fall
                    // through to the manual tap-to-retry affordance instead of
                    // burning battery on what looks like a deterministic failure.
                    self.image = nil
                    self.renderRetryCount += 1
                    self.renderFailed = true
                    if self.renderRetryCount <= Self.maxAutoRetries {
                        self.scheduleRetry(city: city, appearanceRaw: appearanceRaw, key: key, renderCacheStore: renderCacheStore, renderMaskByJourney: renderMaskByJourney)
                    } else {
                        print("[CityThumbnail] LOAD city=\(city.id) auto-retry budget exhausted — awaiting manual retry")
                    }
                }
            }
        }
    }

    /// User-initiated retry: cancel any in-flight task, reset the backoff window,
    /// and kick off a fresh render. Use when the cell is stuck on the placeholder
    /// and the user taps it to force progress.
    func forceReload(city: City?, routePath: String?, basePath: String?, appearanceRaw: String, renderCacheStore: CityRenderCacheStore, renderMaskByJourney: [String: Set<Int>] = [:]) {
        renderTask?.cancel()
        renderTask = nil
        renderRetryCount = 0
        renderFailed = false
        image = nil
        renderedKey = nil
        currentKey = nil
        load(city: city, routePath: routePath, basePath: basePath, appearanceRaw: appearanceRaw, renderCacheStore: renderCacheStore, renderMaskByJourney: renderMaskByJourney)
    }

    private func scheduleRetry(city: City, appearanceRaw: String, key: String, renderCacheStore: CityRenderCacheStore, renderMaskByJourney: [String: Set<Int>] = [:]) {
        renderTask?.cancel()
        // First retry is fast (~1.2s) to recover quickly from transient contention
        // after a style switch / many-card burst. Subsequent retries use exponential
        // backoff capped at maxRetryDelaySec: 5s, 10s, 20s, 40s, 80s... — giving the
        // tile server room between bursts for genuinely persistent failures.
        let attempt = max(1, renderRetryCount)
        let delaySec: Double
        if attempt == 1 {
            delaySec = Self.firstRetryDelaySec
        } else {
            let raw = Self.initialRetryDelaySec * pow(2.0, Double(attempt - 2))
            delaySec = min(raw, Self.maxRetryDelaySec)
        }
        let delayNs = UInt64(delaySec * 1_000_000_000)
        renderTask = Task(priority: .utility) { [city, appearanceRaw, key, renderMaskByJourney] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled, await self.currentKey == key else { return }
            await Self.ensurePersistentCache(for: city, appearanceRaw: appearanceRaw, renderCacheStore: renderCacheStore, renderMaskByJourney: renderMaskByJourney)
            guard !Task.isCancelled else { return }
            let img = CityImageMemoryCache.shared.image(forKey: key) ?? renderCacheStore.image(forKey: key)
            await MainActor.run {
                guard self.currentKey == key else { return }
                if let img {
                    self.image = img
                    self.renderedKey = key
                    self.renderRetryCount = 0
                    self.renderFailed = false
                } else {
                    self.renderRetryCount += 1
                    self.renderFailed = true
                    if self.renderRetryCount <= Self.maxAutoRetries {
                        self.scheduleRetry(city: city, appearanceRaw: appearanceRaw, key: key, renderCacheStore: renderCacheStore, renderMaskByJourney: renderMaskByJourney)
                    } else {
                        print("[CityThumbnail] scheduleRetry city=\(city.id) auto-retry budget exhausted — awaiting manual retry")
                    }
                }
            }
        }
    }

    /// True only when EVERY pixel of the frame is essentially one flat colour — i.e. the
    /// renderer handed back a single fill with nothing drawn on it. Used solely to detect a
    /// Mapbox "success-but-unrendered" cold-start frame BEFORE caching, and only consulted
    /// for route-bearing cities (where a full-opacity route line would otherwise paint
    /// contrasting pixels, so a uniform frame can only mean the render failed). Scans the
    /// whole frame downsampled to 24×16 rather than the old 9 fixed points, so a valid map
    /// whose thin route happens to miss a few sample points is never false-rejected.
    nonisolated private static func isFullyUniformFrame(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let w = 24, h = 16
        let bytesPerRow = w * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * h)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        let r0 = Int(data[0]), g0 = Int(data[1]), b0 = Int(data[2])
        let tolerance = 6
        var i = 0
        while i < data.count {
            if abs(Int(data[i]) - r0) > tolerance
                || abs(Int(data[i + 1]) - g0) > tolerance
                || abs(Int(data[i + 2]) - b0) > tolerance {
                return false
            }
            i += 4
        }
        return true
    }

    nonisolated private static func journeySignature(_ journey: JourneyRoute) -> String {
        // Runs per visible card per render (via `loadKey` as a `.task(id:)`),
        // so it must not materialize `allCLThumbnailCoords` — that map+filter
        // allocates an array over every coordinate. Sample in place instead.
        // The output string must stay byte-identical to the old implementation
        // or every cached thumbnail on disk is invalidated.
        let src = journey.thumbnailCoordinates.isEmpty ? journey.coordinates : journey.thumbnailCoordinates
        var validCount = 0
        for c in src where c.cl.isValid { validCount += 1 }
        let distanceRounded = Int(journey.distance.rounded())
        let endedAt = Int(journey.endTime?.timeIntervalSince1970 ?? 0)
        let coordSig = sampledCoordinateSignature(src: src, validCount: validCount)
        return "\(journey.id):\(endedAt):\(distanceRounded):\(validCount):\(coordSig)"
    }

    /// Produces the same output as `coordinateSignature` applied to the
    /// valid-filtered coordinates, without allocating the filtered array.
    nonisolated private static func sampledCoordinateSignature(src: [CoordinateCodable], validCount: Int) -> String {
        guard validCount > 0 else { return "empty" }
        let wantedIndices: Set<Int> = [0, validCount / 2, validCount - 1]
        var samples: [Int: String] = [:]
        var validIndex = 0
        for c in src {
            let cl = c.cl
            guard cl.isValid else { continue }
            if wantedIndices.contains(validIndex) {
                let lat = Int((cl.latitude * 10_000).rounded())
                let lon = Int((cl.longitude * 10_000).rounded())
                samples[validIndex] = "\(lat)_\(lon)"
                if samples.count == wantedIndices.count { break }
            }
            validIndex += 1
        }
        let first = samples[0] ?? "empty"
        let middle = samples[validCount / 2] ?? first
        let last = samples[validCount - 1] ?? first
        return "\(first)-\(middle)-\(last)"
    }

    nonisolated private static func polygonSignature(_ coords: [CLLocationCoordinate2D]) -> String {
        "\(coords.count):\(coordinateSignature(coords))"
    }

    nonisolated private static func coordinateSignature(_ coords: [CLLocationCoordinate2D]) -> String {
        guard !coords.isEmpty else { return "empty" }

        func sample(_ idx: Int) -> String {
            let c = coords[min(max(idx, 0), coords.count - 1)]
            let lat = Int((c.latitude * 10_000).rounded())
            let lon = Int((c.longitude * 10_000).rounded())
            return "\(lat)_\(lon)"
        }

        let first = sample(0)
        let middle = sample(coords.count / 2)
        let last = sample(coords.count - 1)
        return "\(first)-\(middle)-\(last)"
    }

    nonisolated private static func safeFilenameComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(Character(scalar)) : "_"
        }
        .joined()
    }

    private func candidateKeys(from preferred: String, appearanceRaw: String) -> [String] {
        Self.legacyCandidateKeys(from: preferred, appearanceRaw: appearanceRaw)
    }

    nonisolated private static func legacyCandidateKeys(from preferred: String, appearanceRaw: String) -> [String] {
        let dotRange = preferred.range(of: ".", options: .backwards)
        let stem = dotRange.map { String(preferred[..<$0.lowerBound]) } ?? preferred
        let ext = dotRange.map { String(preferred[$0.lowerBound...]) } ?? ""

        func normalize(_ s: String) -> String {
            s.replacingOccurrences(of: "_dark", with: "")
                .replacingOccurrences(of: "_light", with: "")
        }

        func suffixMode(in s: String) -> String? {
            if s.hasSuffix("_dark") { return "dark" }
            if s.hasSuffix("_light") { return "light" }
            return nil
        }

        let baseStem = normalize(stem)
        let modeKey = (appearanceRaw == MapAppearanceStyle.light.rawValue) ? "light" : "dark"
        let preferredMode = suffixMode(in: stem)

        var keys: [String] = []
        keys.append("\(baseStem)_\(modeKey)\(ext)")
        if preferredMode == nil || preferredMode == modeKey {
            keys.append(preferred)
        }

        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    nonisolated private static func mapType(for appearanceRaw: String) -> MKMapType {
        (MapLayerStyle(rawValue: appearanceRaw) ?? .mutedDark).mapKitType
    }

    nonisolated private static func interfaceStyle(for appearanceRaw: String) -> UIUserInterfaceStyle {
        (MapLayerStyle(rawValue: appearanceRaw) ?? .mutedDark).mapKitInterfaceStyle
    }

    nonisolated private static func routeColor(for appearanceRaw: String) -> UIColor {
        (MapLayerStyle(rawValue: appearanceRaw) ?? .mutedDark).routeBaseColor
    }

    nonisolated private static func clampedRegion(_ region: MKCoordinateRegion) -> MKCoordinateRegion? {
        guard CLLocationCoordinate2DIsValid(region.center),
              region.center.latitude.isFinite, region.center.longitude.isFinite,
              region.span.latitudeDelta.isFinite, region.span.longitudeDelta.isFinite
        else { return nil }

        var center = region.center
        var span = region.span
        center.latitude = min(max(center.latitude, -90.0), 90.0)
        center.longitude = min(max(center.longitude, -180.0), 180.0)
        if span.latitudeDelta <= 0 || span.longitudeDelta <= 0 { return nil }
        span.latitudeDelta = min(max(span.latitudeDelta, 0.0001), 180.0)
        span.longitudeDelta = min(max(span.longitudeDelta, 0.0001), 360.0)
        return MKCoordinateRegion(center: center, span: span)
    }

    nonisolated private static func isBoundaryTrusted(_ region: MKCoordinateRegion, anchor: CLLocationCoordinate2D?) -> Bool {
        guard let anchor else { return true }
        let anchorLoc = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        let centerLoc = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let centerDistance = centerLoc.distance(from: anchorLoc)
        return centerDistance <= boundaryTrustMaxDistanceMeters
            && region.span.latitudeDelta <= boundaryTrustMaxSpanDegrees
            && region.span.longitudeDelta <= boundaryTrustMaxSpanDegrees
    }

    nonisolated private static func clampCenter(
        _ center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        inside boundary: MKCoordinateRegion
    ) -> CLLocationCoordinate2D {
        let minLat = boundary.center.latitude - boundary.span.latitudeDelta / 2 + span.latitudeDelta / 2
        let maxLat = boundary.center.latitude + boundary.span.latitudeDelta / 2 - span.latitudeDelta / 2
        let minLon = boundary.center.longitude - boundary.span.longitudeDelta / 2 + span.longitudeDelta / 2
        let maxLon = boundary.center.longitude + boundary.span.longitudeDelta / 2 - span.longitudeDelta / 2

        return CLLocationCoordinate2D(
            latitude: min(max(center.latitude, minLat), maxLat),
            longitude: min(max(center.longitude, minLon), maxLon)
        )
    }

    nonisolated private static func zoomRegionInsideBoundary(
        boundaryRegion: MKCoordinateRegion,
        journeyCoordsForMap: [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        guard let journeyRegion = regionToFit(coords: journeyCoordsForMap, minSpan: 0.04, paddingFactor: 1.25),
              !journeyCoordsForMap.isEmpty else {
            return boundaryRegion
        }

        let minZoomSpan: CLLocationDegrees = 0.04
        let targetSpan = MKCoordinateSpan(
            latitudeDelta: min(boundaryRegion.span.latitudeDelta, max(minZoomSpan, journeyRegion.span.latitudeDelta)),
            longitudeDelta: min(boundaryRegion.span.longitudeDelta, max(minZoomSpan, journeyRegion.span.longitudeDelta))
        )
        let targetCenter = clampCenter(journeyRegion.center, span: targetSpan, inside: boundaryRegion)
        return MKCoordinateRegion(center: targetCenter, span: targetSpan)
    }

    nonisolated private static func focusedCoords(
        journey: JourneyRoute,
        anchorWGS: CLLocationCoordinate2D?
    ) -> [CLLocationCoordinate2D] {
        let coords = journey.allCLCoords
        guard let anchorWGS else { return coords }
        guard !coords.isEmpty else { return [] }

        let anchorLoc = CLLocation(latitude: anchorWGS.latitude, longitude: anchorWGS.longitude)
        let near = coords.filter {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: anchorLoc) < cityFocusRadiusMeters
        }
        if near.count >= cityFocusMinPoints { return near }

        var out: [CLLocationCoordinate2D] = []
        let head = CLLocation(latitude: coords[0].latitude, longitude: coords[0].longitude)
        for c in coords {
            out.append(c)
            if out.count >= cityFocusWindowMaxPoints { break }
            let d = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: head)
            if d >= cityFocusWindowMeters, out.count >= cityFocusMinPoints { break }
        }
        return out
    }

    nonisolated private static func fittedRegion(
        city: City,
        focusedCoordsWGS: [CLLocationCoordinate2D],
        fetchedBoundary: [CLLocationCoordinate2D]?
    ) -> MKCoordinateRegion? {
        let anchorForMap: CLLocationCoordinate2D? = {
            if let a = city.anchor {
                return MapCoordAdapter.forMapKit(a, countryISO2: city.countryISO2, cityKey: city.id)
            }
            if let first = city.journeys.first?.allCLCoords.first {
                return MapCoordAdapter.forMapKit(first, countryISO2: city.countryISO2, cityKey: city.id)
            }
            return nil
        }()

        let boundaryCandidates = [fetchedBoundary, city.boundaryPolygon]
        if let boundary = boundaryCandidates.compactMap({ $0 }).first(where: { $0.count >= 3 }) {
            let mappedBoundary = MapCoordAdapter.forMapKit(boundary, countryISO2: city.countryISO2, cityKey: city.id)
            if let boundaryRegion = regionToFit(coords: mappedBoundary, minSpan: 0.01, paddingFactor: 1.25),
               isBoundaryTrusted(boundaryRegion, anchor: anchorForMap) {
                let journeyForMap = MapCoordAdapter.forMapKit(focusedCoordsWGS, countryISO2: city.countryISO2, cityKey: city.id)
                return zoomRegionInsideBoundary(boundaryRegion: boundaryRegion, journeyCoordsForMap: journeyForMap)
            }
        }

        if !focusedCoordsWGS.isEmpty {
            let coordsForMap = MapCoordAdapter.forMapKit(focusedCoordsWGS, countryISO2: city.countryISO2, cityKey: city.id)
            if let r = regionToFit(coords: coordsForMap, minSpan: 0.01, paddingFactor: 1.25) { return r }
        }

        if let mappedAnchor = anchorForMap {
            return MKCoordinateRegion(center: mappedAnchor, span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18))
        }
        return nil
    }

    nonisolated private static func makeSnapshot(
        city: City,
        appearanceRaw: String,
        fetchedBoundary: [CLLocationCoordinate2D]?
    ) async -> UIImage? {
        let style = MapLayerStyle(rawValue: appearanceRaw) ?? .mutedDark
        if style.engine == .mapbox {
            return await makeMapboxSnapshot(city: city, style: style, fetchedBoundary: fetchedBoundary)
        }
        return await makeMapKitSnapshot(city: city, appearanceRaw: appearanceRaw, fetchedBoundary: fetchedBoundary)
    }

    /// Fallback: render a plain map tile without routes.
    /// Prefers the city's stored anchor (always available for photo-discovered cities,
    /// and bypasses CLGeocoder rate-limit / unknown-name failures for places like
    /// "Alxa", "Lhasa" that Apple's English geocoder may not recognize).
    /// Falls through to forward-geocoding the name only when no anchor is available.
    private static func makeFallbackSnapshot(city: City, appearanceRaw: String) async -> UIImage? {
        let parts = city.id.split(separator: "|")
        guard parts.count >= 2 else { return nil }
        let cityName = String(parts[0])
        let countryISO2 = String(parts[1])

        let resolvedCenter: CLLocationCoordinate2D?
        if let anchor = city.anchor, CLLocationCoordinate2DIsValid(anchor) {
            resolvedCenter = anchor
        } else {
            resolvedCenter = await withCheckedContinuation { cont in
                let geocoder = CLGeocoder()
                geocoder.geocodeAddressString("\(cityName), \(countryISO2)") { placemarks, _ in
                    cont.resume(returning: placemarks?.first?.location?.coordinate)
                }
            }
        }

        guard let center = resolvedCenter, CLLocationCoordinate2DIsValid(center) else { return nil }
        let style = MapLayerStyle(rawValue: appearanceRaw) ?? .mutedDark

        if style.engine == .mapbox {
            return await makeMapboxFallbackSnapshot(center: center, style: style)
        }

        let mappedCenter = MapCoordAdapter.forMapKit(center, countryISO2: countryISO2, cityKey: city.id)
        let region = MKCoordinateRegion(center: mappedCenter, span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18))
        guard let clamped = clampedRegion(region) else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = clamped
        options.size = CGSize(width: 480, height: 320)
        options.scale = 2
        options.mapType = mapType(for: appearanceRaw)
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: interfaceStyle(for: appearanceRaw)),
            UITraitCollection(displayScale: options.scale),
            UITraitCollection(activeAppearance: .active),
            UITraitCollection(userInterfaceLevel: .base)
        ])
        options.showsBuildings = false
        options.showsPointsOfInterest = false

        return await withCheckedContinuation { cont in
            let snapshotter = MKMapSnapshotter(options: options)
            var resolved = false
            let timeoutWork = DispatchWorkItem {
                guard !resolved else { return }
                resolved = true
                snapshotter.cancel()
                print("[CityThumbnail] ▶ MapKit fallback snapshot TIMEOUT")
                cont.resume(returning: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: timeoutWork)
            snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, _ in
                guard !resolved else { return }
                resolved = true
                timeoutWork.cancel()
                cont.resume(returning: snapshot?.image)
            }
        }
    }

    // MARK: - MapKit snapshot (Apple Maps styles)

    nonisolated private static func makeMapKitSnapshot(
        city: City,
        appearanceRaw: String,
        fetchedBoundary: [CLLocationCoordinate2D]?
    ) async -> UIImage? {
        guard let rawRegion = CityDeepRenderEngine.fittedRegion(
            cityKey: city.id,
            countryISO2: city.countryISO2,
            journeys: city.journeys,
            anchorWGS: city.anchor,
            effectiveBoundaryWGS: city.boundaryPolygon,
            fetchedBoundaryWGS: fetchedBoundary
        ),
              let region = clampedRegion(rawRegion) else { return nil }
        let styledSegments = CityDeepRenderEngine.styledSegments(
            journeys: city.journeys,
            countryISO2: city.countryISO2,
            cityKey: city.id,
            dedupGranularity: .coarse
        )

        // Satellite/hybrid are RASTER. MKMapSnapshotter chooses which zoom tiles to
        // fetch from size × scale (in pixels): a higher scale → higher-zoom, sharper
        // imagery. A previous fix hardcoded scale = 2 to "avoid upsampling raster to
        // the device's 3x scale", but that starved the raster of detail and the
        // thumbnails stayed soft. Request scale 3 for raster so the snapshot itself
        // carries crisp imagery; vector styles repaint cleanly at any scale, so keep
        // them at 2 to save thumbnail memory.
        let isRaster = (MapLayerStyle(rawValue: appearanceRaw) ?? .mutedDark).isSatelliteStyle
        let renderScale: CGFloat = isRaster ? 3 : 2

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 480, height: 320)
        options.scale = renderScale
        options.mapType = mapType(for: appearanceRaw)
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: interfaceStyle(for: appearanceRaw)),
            UITraitCollection(displayScale: options.scale),
            UITraitCollection(activeAppearance: .active),
            UITraitCollection(userInterfaceLevel: .base)
        ])
        options.showsBuildings = false
        options.showsPointsOfInterest = false

        let snapshotSize = options.size
        return await withCheckedContinuation { cont in
            // MKMapSnapshotter under tile-server throttle can keep its completion
            // pending for tens of seconds, holding the RenderThrottle slot and
            // blocking other cells. 12s is a generous ceiling — typical fast-path
            // snapshots return in 1–3s. Timing out here calls .cancel() to drop
            // the in-flight request and lets scheduleRetry's exponential backoff
            // try again in a fresh window.
            let snapshotter = MKMapSnapshotter(options: options)
            var resolved = false
            let timeoutWork = DispatchWorkItem {
                guard !resolved else { return }
                resolved = true
                snapshotter.cancel()
                print("[CityThumbnail] ▶ MapKit snapshot TIMEOUT city=\(city.id)")
                cont.resume(returning: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: timeoutWork)
            snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, _ in
                guard !resolved else { return }
                resolved = true
                timeoutWork.cancel()
                guard let snapshot else {
                    cont.resume(returning: nil)
                    return
                }
                // Redraw at the same scale the snapshot was rendered at (renderScale)
                // so the crisp raster tiles fetched above are preserved 1:1 — drawing
                // a 3x snapshot into a 2x context would throw away the detail we just
                // paid for. The route overlay is vector (CoreGraphics) and stays sharp
                // at any scale.
                let format = UIGraphicsImageRendererFormat()
                format.scale = renderScale
                let img = UIGraphicsImageRenderer(size: snapshotSize, format: format).image { renderer in
                    snapshot.image.draw(at: .zero)
                    CityDeepRenderEngine.drawStyledSegments(styledSegments, snapshot: snapshot, context: renderer.cgContext, appearanceRaw: appearanceRaw)
                }
                cont.resume(returning: img)
            }
        }
    }

    // MARK: - Mapbox snapshot (Mapbox styles)

    nonisolated private static func makeMapboxSnapshot(
        city: City,
        style: MapLayerStyle,
        fetchedBoundary: [CLLocationCoordinate2D]?
    ) async -> UIImage? {
        // Use the same fittedRegion logic as MapKit, but with applyGCJ: false
        // so the output region is in WGS84 — correct for Mapbox.
        guard let wgs84Region = CityDeepRenderEngine.fittedRegion(
            cityKey: city.id,
            countryISO2: city.countryISO2,
            journeys: city.journeys,
            anchorWGS: city.anchor,
            effectiveBoundaryWGS: city.boundaryPolygon,
            fetchedBoundaryWGS: fetchedBoundary,
            applyGCJ: false
        ),
              let region = clampedRegion(wgs84Region) else { return nil }

        // Build segments in WGS84 for Mapbox. Use the shared engine so we get
        // the same signature-based dedup + repeatWeight as the MapKit thumbnail.
        let styledSegments = CityDeepRenderEngine.styledSegments(
            journeys: city.journeys,
            countryISO2: city.countryISO2,
            cityKey: city.id,
            surface: .mapbox,
            dedupGranularity: .coarse
        )

        let coordCounts = city.journeys.map { ($0.id, $0.coordinates.count, $0.correctedCoordinates.count, $0.matchedCoordinates.count, $0.allCLCoords.count) }
        print("[CityThumbnail] ▶ city=\(city.id) journeys=\(city.journeys.count) coordsPerJourney=\(coordCounts.prefix(5))")

        let snapshotSize = CGSize(width: 480, height: 320)
        let styleURI = StyleURI(rawValue: style.mapboxStyleURI) ?? .dark
        let isDark = style.isDarkStyle
        let baseColor = style.routeBaseColor
        let glowColor = style.routeGlowColor

        // Camera bounds from the WGS84 fittedRegion — same focus/boundary logic as MapKit.
        let sw = CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        )
        let ne = CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        )

        print("[CityThumbnail] ▶ Mapbox snapshot START city=\(city.id) style=\(style.rawValue) segments=\(styledSegments.count) sw=\(sw.latitude),\(sw.longitude) ne=\(ne.latitude),\(ne.longitude)")
        return await withCheckedContinuation { cont in
            // Mapbox Snapshotter must be created and driven from the main thread.
            DispatchQueue.main.async {
                let snapOptions = MapSnapshotOptions(size: snapshotSize, pixelRatio: 2, showsLogo: false, showsAttribution: false)
                let snapshotter = MapboxMaps.Snapshotter(options: snapOptions)

                // Use load(mapStyle:completion:) instead of `styleURI = ...` + onNext(.styleLoaded).
                // The event-stream variant has a race: Snapshotter starts loading a default style
                // on init, and its styleLoaded can fire before our setStyleURI takes effect — the
                // callback then adds layers to the wrong style, which the new style load wipes.
                // load(mapStyle:) gives a deterministic completion tied to *this* style request.
                snapshotter.load(mapStyle: MapStyle(uri: styleURI)) { [snapshotter] error in
                    if let error {
                        print("[CityThumbnail] ▶ Mapbox style load FAILED city=\(city.id) error=\(error)")
                        cont.resume(returning: nil)
                        return
                    }
                    print("[CityThumbnail] ▶ Mapbox style loaded city=\(city.id) styleURI=\(styleURI.rawValue)")
                    let routeSourceId = "thumb-routes"
                    var src = GeoJSONSource(id: routeSourceId)
                    var feats: [Turf.Feature] = []
                    var skippedSegments = 0
                    for seg in styledSegments {
                        guard seg.coords.count >= 2 else { skippedSegments += 1; continue }
                        var f = Turf.Feature(geometry: .lineString(Turf.LineString(seg.coords)))
                        f.properties = [
                            "isGap": .init(booleanLiteral: seg.isGap),
                            "repeatWeight": .init(floatLiteral: seg.repeatWeight)
                        ]
                        feats.append(f)
                    }
                    print("[CityThumbnail] ▶ city=\(city.id) styledSegments=\(styledSegments.count) feats=\(feats.count) skipped=\(skippedSegments)")
                    src.data = .featureCollection(Turf.FeatureCollection(features: feats))
                    do { try snapshotter.addSource(src) }
                    catch { print("[CityThumbnail] ▶ addSource FAILED city=\(city.id) error=\(error)") }

                    var glow = LineLayer(id: "thumb-glow", source: routeSourceId)
                    glow.filter = Exp(.eq) { Exp(.get) { "isGap" }; false }
                    glow.lineColor = .constant(StyleColor(glowColor))
                    glow.lineCap = .constant(.round)
                    glow.lineJoin = .constant(.round)
                    glow.lineOpacity = .constant(isDark ? 0.25 : 0.22)
                    glow.lineWidth = .constant(6.0)
                    glow.lineBlur = .constant(3.0)
                    do { try snapshotter.addLayer(glow) }
                    catch { print("[CityThumbnail] ▶ addLayer thumb-glow FAILED city=\(city.id) error=\(error)") }

                    var main = LineLayer(id: "thumb-main", source: routeSourceId)
                    main.filter = Exp(.eq) { Exp(.get) { "isGap" }; false }
                    main.lineColor = .constant(StyleColor(baseColor))
                    main.lineCap = .constant(.round)
                    main.lineJoin = .constant(.round)
                    main.lineOpacity = .constant(1.0)
                    main.lineWidth = .constant(2.5)
                    do { try snapshotter.addLayer(main) }
                    catch { print("[CityThumbnail] ▶ addLayer thumb-main FAILED city=\(city.id) error=\(error)") }

                    var dash = LineLayer(id: "thumb-dash", source: routeSourceId)
                    dash.filter = Exp(.eq) { Exp(.get) { "isGap" }; true }
                    dash.lineColor = .constant(StyleColor(baseColor))
                    dash.lineCap = .constant(.round)
                    dash.lineJoin = .constant(.round)
                    dash.lineOpacity = .constant(0.5)
                    dash.lineDasharray = .constant([10, 10])
                    dash.lineWidth = .constant(1.5)
                    do { try snapshotter.addLayer(dash) }
                    catch { print("[CityThumbnail] ▶ addLayer thumb-dash FAILED city=\(city.id) error=\(error)") }

                    let layerIDs = snapshotter.allLayerIdentifiers.map(\.id)
                    let hasGlow = layerIDs.contains("thumb-glow")
                    let hasMain = layerIDs.contains("thumb-main")
                    let hasDash = layerIDs.contains("thumb-dash")
                    print("[CityThumbnail] ▶ city=\(city.id) layers glow=\(hasGlow) main=\(hasMain) dash=\(hasDash) totalLayers=\(layerIDs.count)")

                    let cam = snapshotter.camera(for: [sw, ne], padding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), bearing: 0, pitch: 0)
                    snapshotter.setCamera(to: cam)

                    // Mapbox Snapshotter doesn't continuously render — it only renders
                    // once when start() is called. .mapIdle on Snapshotter therefore
                    // doesn't reliably fire (no render loop to go idle from), so we
                    // can't gate start() on it. start() itself waits for the style and
                    // the tiles required by the current camera before its completion
                    // fires, so a .success result is a fully-rendered frame; a real
                    // failure comes back as .failure (→ nil → retry).
                    // Defensive timeout: if start() never calls back (rare SDK edge
                    // case), the throttle slot would be held forever. 15s is well
                    // above any normal render time and guarantees the slot returns.
                    var resolved = false
                    let timeoutWork = DispatchWorkItem {
                        guard !resolved else { return }
                        resolved = true
                        print("[CityThumbnail] ▶ Mapbox snapshot start() TIMEOUT city=\(city.id)")
                        cont.resume(returning: nil)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWork)
                    snapshotter.start(overlayHandler: nil) { [snapshotter] result in
                        _ = snapshotter // retain until rendering completes
                        guard !resolved else { return }
                        resolved = true
                        timeoutWork.cancel()
                        switch result {
                        case .success(let image):
                            print("[CityThumbnail] ▶ Mapbox snapshot SUCCESS city=\(city.id)")
                            cont.resume(returning: image)
                        case .failure(let error):
                            print("[CityThumbnail] ▶ Mapbox snapshot FAILED city=\(city.id) error=\(error)")
                            cont.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }

    nonisolated private static func makeMapboxFallbackSnapshot(
        center: CLLocationCoordinate2D,
        style: MapLayerStyle
    ) async -> UIImage? {
        let snapshotSize = CGSize(width: 480, height: 320)
        let styleURI = StyleURI(rawValue: style.mapboxStyleURI) ?? .dark
        let zoom = MapboxEngineView.Coordinator.altitudeToZoom(80_000, latitude: center.latitude)

        return await withCheckedContinuation { cont in
            DispatchQueue.main.async {
                let snapOptions = MapSnapshotOptions(size: snapshotSize, pixelRatio: 2, showsLogo: false, showsAttribution: false)
                let snapshotter = MapboxMaps.Snapshotter(options: snapOptions)

                // See makeMapboxSnapshot for why we avoid onNext(.styleLoaded) and
                // .mapIdle here — Snapshotter's event lifecycle doesn't match those
                // assumptions. Direct start() after setCamera is the correct flow.
                snapshotter.load(mapStyle: MapStyle(uri: styleURI)) { [snapshotter] error in
                    if let error {
                        print("[CityThumbnail] ▶ Mapbox fallback style load FAILED error=\(error)")
                        cont.resume(returning: nil)
                        return
                    }
                    snapshotter.setCamera(to: CameraOptions(center: center, zoom: zoom))

                    var resolved = false
                    let timeoutWork = DispatchWorkItem {
                        guard !resolved else { return }
                        resolved = true
                        print("[CityThumbnail] ▶ Mapbox fallback start() TIMEOUT")
                        cont.resume(returning: nil)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWork)
                    snapshotter.start(overlayHandler: nil) { [snapshotter] result in
                        _ = snapshotter
                        guard !resolved else { return }
                        resolved = true
                        timeoutWork.cancel()
                        switch result {
                        case .success(let image):
                            print("[CityThumbnail] ▶ Mapbox fallback snapshot SUCCESS")
                            cont.resume(returning: image)
                        case .failure(let error):
                            print("[CityThumbnail] ▶ Mapbox fallback snapshot FAILED error=\(error)")
                            cont.resume(returning: nil)
                        }
                    }
                }
            }
        }
    }
}
