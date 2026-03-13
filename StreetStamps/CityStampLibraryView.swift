import Foundation
import SwiftUI
import MapKit
import Combine
import CoreLocation
import UIKit

// =======================================================
// MARK: - CityStampLibraryView
// =======================================================

struct CityStampLibraryView: View {
    private struct CityDigest: Equatable {
        let id: String
        let name: String
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
            name = city.name
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
    @State private var digestByCityID: [String: CityDigest] = [:]

    // ✅ Delete confirmations
    @State private var cityToDelete: City? = nil
    @State private var showDeleteCityAlert = false
    @State private var showPublicDetailUnavailableAlert = false

    @Environment(\.dismiss) private var dismiss
    @Binding var showSidebar: Bool
    private let autoRebuildFromJourneyStore: Bool
    private let usesSidebarHeader: Bool
    private let showHeader: Bool
    private let allowCityDetailNavigation: Bool
    private let headerTitle: String?
    private let emptyTitleKey: String
    private let emptySubtitleKey: String

    init(
        showSidebar: Binding<Bool>,
        autoRebuildFromJourneyStore: Bool = false,
        usesSidebarHeader: Bool = true,
        showHeader: Bool = true,
        allowCityDetailNavigation: Bool = true,
        headerTitle: String? = nil,
        emptyTitleKey: String = "library_empty_title",
        emptySubtitleKey: String = "library_empty_subtitle"
    ) {
        self._showSidebar = showSidebar
        self.autoRebuildFromJourneyStore = autoRebuildFromJourneyStore
        self.usesSidebarHeader = usesSidebarHeader
        self.showHeader = showHeader
        self.allowCityDetailNavigation = allowCityDetailNavigation
        self.headerTitle = headerTitle
        self.emptyTitleKey = emptyTitleKey
        self.emptySubtitleKey = emptySubtitleKey
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
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if store.hasLoaded {
                vm.load(journeyStore: store, cityCache: cache)
                digestByCityID = makeDigestMap(from: cache.cachedCities)
                StartupWarmupService.shared.start(cities: vm.cities, appearanceRaw: MapAppearanceSettings.current.rawValue, renderCacheStore: renderCacheStore, limit: 16)
            }
        }
        .onChange(of: store.hasLoaded) { loaded in
            if loaded {
                vm.load(journeyStore: store, cityCache: cache)
                digestByCityID = makeDigestMap(from: cache.cachedCities)
                StartupWarmupService.shared.start(cities: vm.cities, appearanceRaw: MapAppearanceSettings.current.rawValue, renderCacheStore: renderCacheStore, limit: 16)
            }
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
            StartupWarmupService.shared.start(cities: vm.cities, appearanceRaw: MapAppearanceSettings.current.rawValue, renderCacheStore: renderCacheStore, limit: 16)
        }
        .alert(L10n.t("delete_city_alert_title"), isPresented: $showDeleteCityAlert, presenting: cityToDelete) { city in
            Button(L10n.t("delete"), role: .destructive) {
                cache.deleteCity(id: city.id)
                vm.load(journeyStore: store, cityCache: cache)
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: { city in
            Text(String(format: L10n.t("delete_city_alert_message"), locale: Locale.current, city.localizedName))
        }
        .alert(L10n.t("details_unavailable_title"), isPresented: $showPublicDetailUnavailableAlert) {
            Button(L10n.t("ok"), role: .cancel) {}
        } message: {
            Text(L10n.t("details_unavailable_message"))
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
            if usesSidebarHeader {
                AppTopHeader(title: titleText, showSidebar: $showSidebar)
            } else {
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(titleText)
                        .appHeaderStyle()

                    Spacer()

                    Color.clear.frame(width: 42, height: 42)
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
                ForEach(vm.cities) { city in
                    if allowCityDetailNavigation {
                        NavigationLink(destination: CityDeepView(city: city)) {
                            CityStampCard(city: city, cardWidth: cardW)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                cityToDelete = city
                                showDeleteCityAlert = true
                            } label: {
                                Label(L10n.t("delete"), systemImage: "trash")
                            }
                        }
                    } else {
                        Button {
                            showPublicDetailUnavailableAlert = true
                        } label: {
                            CityStampCard(city: city, cardWidth: cardW)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if vm.cities.isEmpty {
                emptyState(
                    title: L10n.key(emptyTitleKey),
                    subtitle: L10n.key(emptySubtitleKey)
                )
                .padding(.top, 28)
                .padding(.bottom, 60)
            }
        }
    }

    private func emptyState(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(UITheme.softBlack)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(UITheme.subText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
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
        let text = String(format: L10n.t("city_card_stats"), city.explorations, city.memories)

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
// MARK: - In-memory image cache
// =======================================================

final class CityImageMemoryCache {
    static let shared = CityImageMemoryCache()
    private init() {
        cache.countLimit = 220
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    private let cache = NSCache<NSString, UIImage>()

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: cost(of: image))
    }

    private func cost(of image: UIImage) -> Int {
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

    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue
    @EnvironmentObject private var renderCacheStore: CityRenderCacheStore
    @StateObject private var loader = CityThumbnailLoader()

    init(city: City? = nil, basePath: String?, routePath: String?) {
        self.city = city
        self.basePath = basePath
        self.routePath = routePath
    }

    var body: some View {
        let syncCachedImage = CityThumbnailLoader.existingCachedImage(
            city: city,
            routePath: routePath,
            basePath: basePath,
            appearanceRaw: mapAppearanceRaw,
            renderCacheStore: renderCacheStore
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
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "map")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(UITheme.accent.opacity(0.6))

                            Text(L10n.key("preparing_map"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.black.opacity(0.35))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .allowsTightening(true)
                        }
                        .padding(.horizontal, 10)
                    )
            }
        }
        .onAppear {
            loader.load(city: city, routePath: routePath, basePath: basePath, appearanceRaw: mapAppearanceRaw, renderCacheStore: renderCacheStore)
        }
        .onChange(of: routePath) { _ in
            loader.load(city: city, routePath: routePath, basePath: basePath, appearanceRaw: mapAppearanceRaw, renderCacheStore: renderCacheStore)
        }
        .onChange(of: basePath) { _ in
            loader.load(city: city, routePath: routePath, basePath: basePath, appearanceRaw: mapAppearanceRaw, renderCacheStore: renderCacheStore)
        }
        .onChange(of: city?.id ?? "") { _ in
            loader.load(city: city, routePath: routePath, basePath: basePath, appearanceRaw: mapAppearanceRaw, renderCacheStore: renderCacheStore)
        }
        .onChange(of: mapAppearanceRaw) { _ in
            loader.load(city: city, routePath: routePath, basePath: basePath, appearanceRaw: mapAppearanceRaw, renderCacheStore: renderCacheStore)
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

    func load(city: City?, routePath: String?, basePath: String?, appearanceRaw: String, renderCacheStore: CityRenderCacheStore) {
        // City cards use render-keyed persistent caching first, then render on miss.
        if let city {
            let renderKeyParts = Self.renderKeyParts(for: city, appearanceRaw: appearanceRaw)
            let renderKey = renderKeyParts.fullKey
            CityThumbnailDebugLogger.shared.recordRenderKey(
                cityID: city.id,
                cityName: city.localizedName,
                appearanceRaw: appearanceRaw,
                parts: renderKeyParts
            )
            // Fast path: same key, image already showing — nothing to do.
            if currentKey == renderKey, image != nil { return }
            // Also skip if we already rendered this exact key (survives cancel()).
            if renderedKey == renderKey, image != nil {
                currentKey = renderKey
                return
            }
            currentKey = renderKey
            renderTask?.cancel()
            renderTask = nil
            if let cached = CityImageMemoryCache.shared.image(forKey: renderKey) {
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

            CityThumbnailDebugLogger.shared.log(
                .renderMiss,
                cityID: city.id,
                "load city=\(city.id) source=render_miss key=\(renderKey)"
            )
            // Keep stale image visible while rendering the new one — avoids placeholder flash.
            renderOnDemand(city: city, appearanceRaw: appearanceRaw, key: renderKey, renderCacheStore: renderCacheStore)
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

    nonisolated static func renderCacheKey(for city: City, appearanceRaw: String) -> String {
        renderKeyParts(for: city, appearanceRaw: appearanceRaw).fullKey
    }

    nonisolated static func renderKeyParts(for city: City, appearanceRaw: String) -> CityThumbnailDebugLogger.RenderKeyParts {
        let journeySignature = city.journeys
            .sorted { $0.id < $1.id }
            .map(journeySignature)
            .joined(separator: "~")
        let boundarySignature = "ignored-for-cache"
        let anchorSignature = "ignored-for-cache"
        let fullKey = "render|\(city.id)|\(appearanceRaw)|\(journeySignature)"
        return CityThumbnailDebugLogger.RenderKeyParts(
            fullKey: fullKey,
            journeySignature: journeySignature,
            boundarySignature: boundarySignature,
            anchorSignature: anchorSignature
        )
    }

    nonisolated static func renderCacheRelativePath(forKey key: String) -> String {
        "city_\(safeFilenameComponent(key)).jpg"
    }

    nonisolated static func existingPersistentCache(
        for city: City,
        appearanceRaw: String,
        renderCacheStore: CityRenderCacheStore
    ) -> UIImage? {
        let key = renderCacheKey(for: city, appearanceRaw: appearanceRaw)
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
        renderCacheStore: CityRenderCacheStore
    ) -> UIImage? {
        if let city {
            return existingPersistentCache(
                for: city,
                appearanceRaw: appearanceRaw,
                renderCacheStore: renderCacheStore
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

    nonisolated static func ensurePersistentCache(for city: City, appearanceRaw: String, renderCacheStore: CityRenderCacheStore) async {
        let key = renderCacheKey(for: city, appearanceRaw: appearanceRaw)
        if CityImageMemoryCache.shared.image(forKey: key) != nil { return }
        if let diskCached = renderCacheStore.image(forKey: key) {
            CityImageMemoryCache.shared.set(diskCached, forKey: key)
            return
        }

        let fetchedBoundary = await CityBoundaryService.shared.boundaryPolygon(
            cityKey: city.id,
            cityName: city.localizedName,
            countryISO2: city.countryISO2,
            anchor: city.anchor ?? city.journeys.first?.allCLCoords.first
        )
        guard let img = Self.makeSnapshot(city: city, appearanceRaw: appearanceRaw, fetchedBoundary: fetchedBoundary) else { return }

        CityImageMemoryCache.shared.set(img, forKey: key)
        renderCacheStore.save(img, forKey: key)
    }

    private func renderOnDemand(city: City, appearanceRaw: String, key: String, renderCacheStore: CityRenderCacheStore) {
        renderTask?.cancel()
        renderTask = Task(priority: .utility) { [city, appearanceRaw, key] in
            await Self.ensurePersistentCache(for: city, appearanceRaw: appearanceRaw, renderCacheStore: renderCacheStore)
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
                }
            }
        }
    }

    nonisolated private static func journeySignature(_ journey: JourneyRoute) -> String {
        let coords = journey.allCLThumbnailCoords
        let distanceRounded = Int(journey.distance.rounded())
        let endedAt = Int(journey.endTime?.timeIntervalSince1970 ?? 0)
        return "\(journey.id):\(endedAt):\(distanceRounded):\(coords.count):\(coordinateSignature(coords))"
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
        MapAppearanceSettings.mapType(for: appearanceRaw)
    }

    nonisolated private static func interfaceStyle(for appearanceRaw: String) -> UIUserInterfaceStyle {
        MapAppearanceSettings.interfaceStyle(for: appearanceRaw)
    }

    nonisolated private static func routeColor(for appearanceRaw: String) -> UIColor {
        MapAppearanceSettings.routeBaseColor(for: appearanceRaw)
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
    ) -> UIImage? {
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
            cityKey: city.id
        )

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 480, height: 320)
        options.scale = 2
        options.mapType = mapType(for: appearanceRaw)
        options.traitCollection = UITraitCollection(userInterfaceStyle: interfaceStyle(for: appearanceRaw))
        options.showsBuildings = false
        options.showsPointsOfInterest = false

        let sem = DispatchSemaphore(value: 0)
        var out: UIImage?
        MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) { snapshot, _ in
            defer { sem.signal() }
            guard let snapshot else { return }
            out = UIGraphicsImageRenderer(size: options.size).image { renderer in
                snapshot.image.draw(at: .zero)
                CityDeepRenderEngine.drawStyledSegments(styledSegments, snapshot: snapshot, context: renderer.cgContext, appearanceRaw: appearanceRaw)
            }
        }
        _ = sem.wait(timeout: .now() + 15)
        return out
    }
}
