import SwiftUI
import MapKit
import CoreLocation
import Foundation
import Combine
import UIKit

// =======================================================
// MARK: - Unlock payload (City)
// =======================================================

enum UnlockKind: String, Codable {
    case city
}

struct UnlockedPayload: Identifiable, Codable {
    let id: String
    let kind: UnlockKind
    let title: String
    let subtitle: String?
    let baseThumbPath: String?
    let routeThumbPath: String?
}

// =======================================================
//  City Feature (CACHE-FIRST):
//  - onJourneyStarted: create TEMP city card keyed by journeyId (prevents duplicates)
//  - onJourneyCompleted: merge TEMP -> canonical "city|ISO2", recompute stats, route snapshot
//  - Snapshot tuned for performance + in-flight de-dupe
// =======================================================


// MARK: - Coordinate helpers
extension CLLocationCoordinate2D {
    var isValid: Bool {
        CLLocationCoordinate2DIsValid(self) && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

// MARK: - Region safety (prevents MKMapSnapshotOptions crash)
private extension MKCoordinateRegion {
    func clampedForSnapshot() -> MKCoordinateRegion? {
        // Validate center
        guard CLLocationCoordinate2DIsValid(center), center.latitude.isFinite, center.longitude.isFinite else { return nil }
        var c = center

        // Clamp center to legal ranges
        c.latitude = min(max(c.latitude, -90.0), 90.0)
        c.longitude = normalizeLongitude(c.longitude)

        // Validate / clamp span
        var s = span
        guard s.latitudeDelta.isFinite, s.longitudeDelta.isFinite else { return nil }

        // Negative/zero span is invalid
        if s.latitudeDelta <= 0 || s.longitudeDelta <= 0 {
            return nil
        }

        // MapKit requires: latDelta <= 180, lonDelta <= 360
        s.latitudeDelta = min(s.latitudeDelta, 180.0)
        s.longitudeDelta = min(s.longitudeDelta, 360.0)

        // Avoid extreme tiny deltas that can also behave badly
        s.latitudeDelta = max(s.latitudeDelta, 0.0001)
        s.longitudeDelta = max(s.longitudeDelta, 0.0001)

        return MKCoordinateRegion(center: c, span: s)
    }

    private func normalizeLongitude(_ lon: Double) -> Double {
        // Normalize into [-180, 180)
        var x = lon
        if !x.isFinite { return 0 }
        x = x.truncatingRemainder(dividingBy: 360.0)
        if x >= 180.0 { x -= 360.0 }
        if x < -180.0 { x += 360.0 }
        return x
    }
}

// MARK: - Journey helpers
extension JourneyRoute {
    var startCoordinate: CLLocationCoordinate2D? {
        coordinates.first?.cl
        
    }

    var allCLCoords: [CLLocationCoordinate2D] {
        coordinates.map { $0.cl }.filter { $0.isValid }
    }

    /// Lightweight polyline for overview UIs (city card / list / globe).
    /// Falls back to full coords if empty.
    var allCLThumbnailCoords: [CLLocationCoordinate2D] {
        let src = thumbnailCoordinates.isEmpty ? coordinates : thumbnailCoordinates
        return src.map { $0.cl }.filter { $0.isValid }
    }

    var memoryCount: Int { memories.count }

    /// canonical cache key (only reliable after reverse geocode filled)
    var canonicalCityKey: String {
        let name = displayCityName
        let iso = (countryISO2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "\(name)|\(iso)"
    }

        /// Canonical key based on Journey fields (fallback only; CityCache canonical should be fixed-locale geocode)
    var canonicalCityKeyFallback: String {
        let name = displayCityName
        let iso = (countryISO2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return "\(name)|\(iso)"
        }
    
}

// MARK: - Simple LatLon codable
struct LatLon: Codable {
    var lat: Double
    var lon: Double
    var cl: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    init(_ c: CLLocationCoordinate2D) { self.lat = c.latitude; self.lon = c.longitude }
}

// MARK: - CachedCity (disk)
struct CachedCity: Identifiable, Codable {
    let id: String                 // identity key; canonical: "name|ISO2" or temp: "__TMP__|journeyId"
    let cityKey: String
    let name: String
    let canonicalNameEN: String
    let countryISO2: String?

    var journeyIds: [String]
    var explorations: Int
    var memories: Int

    var boundary: [LatLon]?
    var anchor: LatLon?

    var thumbnailBasePath: String?
    var thumbnailRoutePath: String?

    // Identity/display split:
    // - identityLevelRaw is inferred from cityKey and does not move with display changes.
    // - selectedDisplayLevelRaw is the current UI level and can move upward.
    var identityLevelRaw: String? = nil
    var selectedDisplayLevelRaw: String? = nil
    var parentScopeKey: String? = nil
    var availableLevelNames: [String: String]? = nil
    var availableLevelNamesLocaleID: String? = nil

    /// Persisted localized display names keyed by locale identifier (e.g. "zh-Hans": "上海").
    /// Populated by CityLibraryVM after successful reverse-geocode localization.
    var localizedDisplayNameByLocale: [String: String]? = nil

    var isTemporary: Bool? = false

    init(
        id: String,
        cityKey: String? = nil,
        name: String,
        canonicalNameEN: String? = nil,
        countryISO2: String?,
        journeyIds: [String],
        explorations: Int,
        memories: Int,
        boundary: [LatLon]?,
        anchor: LatLon?,
        thumbnailBasePath: String?,
        thumbnailRoutePath: String?,
        identityLevelRaw: String? = nil,
        selectedDisplayLevelRaw: String? = nil,
        parentScopeKey: String? = nil,
        availableLevelNames: [String: String]? = nil,
        availableLevelNamesLocaleID: String? = nil,
        localizedDisplayNameByLocale: [String: String]? = nil,
        isTemporary: Bool? = false,
        reservedLevelRaw: String? = nil,
        reservedParentRegionKey: String? = nil,
        reservedAvailableLevelNames: [String: String]? = nil,
        reservedAvailableLevelNamesLocaleID: String? = nil
    ) {
        self.id = id
        self.cityKey = (cityKey ?? id).trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name
        self.canonicalNameEN = canonicalNameEN ?? name
        self.countryISO2 = countryISO2
        self.journeyIds = journeyIds
        self.explorations = explorations
        self.memories = memories
        self.boundary = boundary
        self.anchor = anchor
        self.thumbnailBasePath = thumbnailBasePath
        self.thumbnailRoutePath = thumbnailRoutePath
        self.identityLevelRaw = identityLevelRaw
        self.selectedDisplayLevelRaw = selectedDisplayLevelRaw ?? reservedLevelRaw
        self.parentScopeKey = parentScopeKey ?? reservedParentRegionKey
        self.availableLevelNames = availableLevelNames ?? reservedAvailableLevelNames
        self.availableLevelNamesLocaleID = availableLevelNamesLocaleID ?? reservedAvailableLevelNamesLocaleID
        self.localizedDisplayNameByLocale = localizedDisplayNameByLocale
        self.isTemporary = isTemporary
    }

    var reservedLevelRaw: String? {
        get { selectedDisplayLevelRaw }
        set { selectedDisplayLevelRaw = newValue }
    }

    var reservedParentRegionKey: String? {
        get { parentScopeKey }
        set { parentScopeKey = newValue }
    }

    var reservedAvailableLevelNames: [String: String]? {
        get { availableLevelNames }
        set { availableLevelNames = newValue }
    }

    var reservedAvailableLevelNamesLocaleID: String? {
        get { availableLevelNamesLocaleID }
        set { availableLevelNamesLocaleID = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case cityKey
        case name
        case canonicalNameEN
        case countryISO2
        case journeyIds
        case explorations
        case memories
        case boundary
        case anchor
        case thumbnailBasePath
        case thumbnailRoutePath
        case identityLevelRaw
        case selectedDisplayLevelRaw
        case parentScopeKey
        case availableLevelNames
        case availableLevelNamesLocaleID
        case localizedDisplayNameByLocale
        case isTemporary
        case reservedLevelRaw
        case reservedParentRegionKey
        case reservedAvailableLevelNames
        case reservedAvailableLevelNamesLocaleID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)

        self.init(
            id: id,
            cityKey: try container.decodeIfPresent(String.self, forKey: .cityKey),
            name: name,
            canonicalNameEN: try container.decodeIfPresent(String.self, forKey: .canonicalNameEN),
            countryISO2: try container.decodeIfPresent(String.self, forKey: .countryISO2),
            journeyIds: try container.decodeIfPresent([String].self, forKey: .journeyIds) ?? [],
            explorations: try container.decodeIfPresent(Int.self, forKey: .explorations) ?? 0,
            memories: try container.decodeIfPresent(Int.self, forKey: .memories) ?? 0,
            boundary: try container.decodeIfPresent([LatLon].self, forKey: .boundary),
            anchor: try container.decodeIfPresent(LatLon.self, forKey: .anchor),
            thumbnailBasePath: try container.decodeIfPresent(String.self, forKey: .thumbnailBasePath),
            thumbnailRoutePath: try container.decodeIfPresent(String.self, forKey: .thumbnailRoutePath),
            identityLevelRaw: try container.decodeIfPresent(String.self, forKey: .identityLevelRaw),
            selectedDisplayLevelRaw: try container.decodeIfPresent(String.self, forKey: .selectedDisplayLevelRaw),
            parentScopeKey: try container.decodeIfPresent(String.self, forKey: .parentScopeKey),
            availableLevelNames: try container.decodeIfPresent([String: String].self, forKey: .availableLevelNames),
            availableLevelNamesLocaleID: try container.decodeIfPresent(String.self, forKey: .availableLevelNamesLocaleID),
            localizedDisplayNameByLocale: try container.decodeIfPresent([String: String].self, forKey: .localizedDisplayNameByLocale),
            isTemporary: try container.decodeIfPresent(Bool.self, forKey: .isTemporary),
            reservedLevelRaw: try container.decodeIfPresent(String.self, forKey: .reservedLevelRaw),
            reservedParentRegionKey: try container.decodeIfPresent(String.self, forKey: .reservedParentRegionKey),
            reservedAvailableLevelNames: try container.decodeIfPresent([String: String].self, forKey: .reservedAvailableLevelNames),
            reservedAvailableLevelNamesLocaleID: try container.decodeIfPresent(String.self, forKey: .reservedAvailableLevelNamesLocaleID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(cityKey, forKey: .cityKey)
        try container.encode(name, forKey: .name)
        try container.encode(canonicalNameEN, forKey: .canonicalNameEN)
        try container.encodeIfPresent(countryISO2, forKey: .countryISO2)
        try container.encode(journeyIds, forKey: .journeyIds)
        try container.encode(explorations, forKey: .explorations)
        try container.encode(memories, forKey: .memories)
        try container.encodeIfPresent(boundary, forKey: .boundary)
        try container.encodeIfPresent(anchor, forKey: .anchor)
        try container.encodeIfPresent(thumbnailBasePath, forKey: .thumbnailBasePath)
        try container.encodeIfPresent(thumbnailRoutePath, forKey: .thumbnailRoutePath)
        try container.encodeIfPresent(identityLevelRaw, forKey: .identityLevelRaw)
        try container.encodeIfPresent(selectedDisplayLevelRaw, forKey: .selectedDisplayLevelRaw)
        try container.encodeIfPresent(parentScopeKey, forKey: .parentScopeKey)
        try container.encodeIfPresent(availableLevelNames, forKey: .availableLevelNames)
        try container.encodeIfPresent(availableLevelNamesLocaleID, forKey: .availableLevelNamesLocaleID)
        try container.encodeIfPresent(localizedDisplayNameByLocale, forKey: .localizedDisplayNameByLocale)
        try container.encodeIfPresent(isTemporary, forKey: .isTemporary)
    }
}

extension CachedCity: @unchecked Sendable {}


// =======================================================
// MARK: - Snapshot rendering (FAST + in-flight de-dupe)
// =======================================================

final class CitySnapshotService {
    static let shared = CitySnapshotService()
    private let renderSemaphore = DispatchSemaphore(value: 2)

    // ✅ in-flight de-dupe: same key requests share the same render
    private var inFlight: [String: [((UIImage?) -> Void)]] = [:]
    private let lock = NSLock()
    

    /// Perf tokens (you can tune)
    struct Tokens {
        static let size = CGSize(width: 240, height: 160) // ✅ smaller than 360x240
        static let scale: CGFloat = 2                     // ✅ stable; don't use UIScreen.main.scale
        static let buildings = false
        static let poi = false
    }

    /// cacheKey should include drawRoute + region rough identity
    func renderSnapshot(
        cacheKey: String,
        region: MKCoordinateRegion,
        overlaySegments: [RenderRouteSegment],
        isFlightLike: Bool,
        drawRoute: Bool,
        completion: @escaping (UIImage?) -> Void
    ) {

        lock.lock()
        if inFlight[cacheKey] != nil {
            inFlight[cacheKey]?.append(completion)
            lock.unlock()
            return
        } else {
            inFlight[cacheKey] = [completion]
            lock.unlock()
        }

        // ✅ harden region (prevents MapKit exception: Invalid Region span)
        guard let safeRegion = region.clampedForSnapshot() else {
            self.lock.lock()
            let callbacks = self.inFlight[cacheKey] ?? []
            self.inFlight[cacheKey] = nil
            self.lock.unlock()
            callbacks.forEach { $0(nil) }
            return
        }

        // ✅ limit concurrent snapshot renders (prevents scroll/jank)
        renderSemaphore.wait()

        let options = MKMapSnapshotter.Options()
        let appearance = MapAppearanceSettings.current
        options.region = safeRegion
        options.size = Tokens.size
        options.scale = Tokens.scale
        options.mapType = MapAppearanceSettings.mapType(for: appearance)
        options.traitCollection = UITraitCollection(userInterfaceStyle: MapAppearanceSettings.interfaceStyle(for: appearance))
        options.showsBuildings = Tokens.buildings
        options.showsPointsOfInterest = Tokens.poi

        MKMapSnapshotter(options: options)
            .start(with: .global(qos: .userInitiated)) { [weak self] snapshot, error in
                defer { self?.renderSemaphore.signal() }
                guard let self else { return }

                var final: UIImage? = nil
                if let snapshot {
                    final = UIGraphicsImageRenderer(size: Tokens.size).image { renderer in
                        snapshot.image.draw(at: .zero)

                        if drawRoute, overlaySegments.count >= 1 {
                            RouteSnapshotDrawer.draw(
                                segments: overlaySegments,
                                isFlightLike: isFlightLike,
                                snapshot: snapshot,
                                ctx: renderer.cgContext,
                                coreColor: MapAppearanceSettings.routeCoreColorForSnapshot(for: appearance),
                                stroke: .init(coreWidth: 3.5)
                            )
                        }
                        // Dots removed - only show route line
                    }
                } else {
                    print("❌ snapshot failed:", error?.localizedDescription ?? "unknown")
                }

                self.lock.lock()
                let callbacks = self.inFlight[cacheKey] ?? []
                self.inFlight[cacheKey] = nil
                self.lock.unlock()

                callbacks.forEach { $0(final) }
            }
    }

    private func drawDot(_ ctx: CGContext, at p: CGPoint, color: UIColor) {
        let r: CGFloat = 6
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: rect)
    }
}


// =======================================================
// MARK: - Thumbnail disk cache
// =======================================================

final class CityThumbnailCache {
    private let fm = FileManager.default
    private let dir: URL

    // MARK: - Static path resolver (for CityThumbnailLoader)
    /// Shared reference to the current thumbnails directory.
    /// Set when CityThumbnailCache is initialized.
    static var sharedThumbnailsDir: URL?

    /// Resolves a relative thumbnail path (filename) to a full file path.
    /// Returns nil if sharedThumbnailsDir is not set or the path is empty.
    static func resolveFullPath(_ relativePath: String?) -> String? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        guard let baseDir = sharedThumbnailsDir else { return nil }
        
        // If it's already an absolute path (legacy data), extract filename
        if relativePath.hasPrefix("/") {
            let filename = (relativePath as NSString).lastPathComponent
            return baseDir.appendingPathComponent(filename).path
        }
        
        return baseDir.appendingPathComponent(relativePath).path
    }
    
    /// Checks if a thumbnail file exists at the given relative path.
    static func thumbnailExists(_ relativePath: String?) -> Bool {
        guard let fullPath = resolveFullPath(relativePath) else { return false }
        return FileManager.default.fileExists(atPath: fullPath)
    }

    static func storeRenderedImage(_ image: UIImage, relativePath: String) {
        guard let fullPath = resolveFullPath(relativePath),
              let data = image.jpegData(compressionQuality: 0.82) else { return }
        let url = URL(fileURLWithPath: fullPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try? data.write(to: url, options: [.atomic])
    }

    /// `dir` should be user-scoped (e.g. .../<userID>/Thumbnails)
    init(dir: URL) {
        self.dir = dir
        // Set shared reference for path resolution
        CityThumbnailCache.sharedThumbnailsDir = dir
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }

    func urlBase(cityKey: String) -> URL {
        dir.appendingPathComponent("base_\(safe(cityKey)).jpg")
    }

    func urlRoute(cityKey: String) -> URL {
        dir.appendingPathComponent("route_\(safe(cityKey)).jpg")
    }
    
    /// Returns just the filename (relative path) for storage
    func filenameBase(cityKey: String) -> String {
        "base_\(safe(cityKey)).jpg"
    }
    
    /// Returns just the filename (relative path) for storage
    func filenameRoute(cityKey: String) -> String {
        "route_\(safe(cityKey)).jpg"
    }

    func save(_ img: UIImage, to url: URL) {
        guard let data = img.jpegData(compressionQuality: 0.82) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func safe(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        return s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
            .map(String.init)
            .joined()
    }
}

final class CityRenderCacheStore: ObservableObject {
    private let fm: FileManager
    private var rootDir: URL

    init(rootDir: URL, fm: FileManager = .default) {
        self.rootDir = rootDir
        self.fm = fm
        ensureDirectoryExists()
    }

    func rebind(rootDir: URL) {
        self.rootDir = rootDir
        ensureDirectoryExists()
    }

    func relativePath(forKey key: String) -> String {
        CityThumbnailLoader.renderCacheRelativePath(forKey: key)
    }

    func fullPath(forKey key: String) -> String {
        rootDir.appendingPathComponent(relativePath(forKey: key), isDirectory: false).path
    }

    func fullPath(forRelativePath relativePath: String) -> String {
        rootDir.appendingPathComponent(relativePath, isDirectory: false).path
    }

    func exists(forKey key: String) -> Bool {
        fm.fileExists(atPath: fullPath(forKey: key))
    }

    func image(forKey key: String) -> UIImage? {
        let path = fullPath(forKey: key)
        guard fm.fileExists(atPath: path) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    func save(_ image: UIImage, forKey key: String) {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        let url = rootDir.appendingPathComponent(relativePath(forKey: key), isDirectory: false)
        try? fm.createDirectory(at: rootDir, withIntermediateDirectories: true, attributes: nil)
        try? data.write(to: url, options: [.atomic])
    }

    private func ensureDirectoryExists() {
        if !fm.fileExists(atPath: rootDir.path) {
            try? fm.createDirectory(at: rootDir, withIntermediateDirectories: true, attributes: nil)
        }
    }
}

// =======================================================
// MARK: - CityCache
// =======================================================

@MainActor
final class CityCache: ObservableObject {

    // MARK: - Polyline downsampling (for deep views / list previews)
    static func downsample(coords: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard maxPoints > 2, coords.count > maxPoints else { return coords }
        let step = max(1, coords.count / maxPoints)
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(maxPoints)
        var i = 0
        while i < coords.count {
            out.append(coords[i])
            i += step
        }
        if let last = coords.last, out.last != last { out.append(last) }
        return out
    }

    enum CityEvent: Equatable {
        case addedNewCity(cityKey: String, name: String)
        case updatedCity(cityKey: String)
    }

    @Published private(set) var cachedCities: [CachedCity] = []
    @Published private(set) var lastEvent: CityEvent? = nil
    @Published private(set) var pendingUnlock: UnlockedPayload? = nil

    private let fm = FileManager.default

    /// `@Published` 只会在属性本身被重新赋值时触发更新。
    /// 对数组元素的"就地修改"（例如 `cachedCities[idx].thumbnailBasePath = ...`）不会自动触发 SwiftUI 刷新。
    /// 这里用一次自赋值来强制触发 Combine 通知。
    @MainActor
    private func notifyCitiesChanged() {
        cachedCities = cachedCities
    }

    // ✅ Cancel stale callbacks
    private var geocodeTask: Task<Void, Never>? = nil

    private var fileURL: URL
    private var membershipIndexURL: URL
    private unowned let journeyStore: JourneyStore
    private var thumbnails: CityThumbnailCache
    private var migrationMarkerV2URL: URL
    private var migrationMarkerV3URL: URL
    private var migrationMarkerV4URL: URL
    private var paths: StoragePath
    private var membershipIndex = CityMembershipIndex()
    private var cancellables: Set<AnyCancellable> = []
    private var hasRebuiltForCurrentLoadedState = false

    init(paths: StoragePath, journeyStore: JourneyStore) {
        self.fileURL = paths.cityCacheURL
        self.membershipIndexURL = paths.cityMembershipIndexURL
        self.journeyStore = journeyStore
        self.thumbnails = CityThumbnailCache(dir: paths.thumbnailsDir)
        self.migrationMarkerV2URL = paths.migrationMarkerV2_thumbnailPaths
        self.migrationMarkerV3URL = paths.migrationMarkerV3_intercityToStartingCity
        self.migrationMarkerV4URL = paths.migrationMarkerV4_removeLegacyThumbnails
        self.paths = paths
        loadFromDisk()
        loadMembershipIndexFromDisk()

        // Migrate thumbnail paths from absolute to relative (V2 migration)
        migrateThumbnailPathsIfNeeded()

        // Migrate intercity routes to starting cities (V3 migration)
        migrateInterCityRoutesToStartingCitiesIfNeeded()
        removeLegacyDiskThumbnailsIfNeeded()
        handleJourneyStoreLoadedState(journeyStore.hasLoaded)

        journeyStore.$hasLoaded
            .receive(on: RunLoop.main)
            .sink { [weak self] loaded in
                self?.handleJourneyStoreLoadedState(loaded)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .journeyStoreDidDiscardJourneys, object: journeyStore)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildFromJourneyStore()
            }
            .store(in: &cancellables)
    }

    func rebind(paths: StoragePath) {
        self.paths = paths
        self.fileURL = paths.cityCacheURL
        self.membershipIndexURL = paths.cityMembershipIndexURL
        self.thumbnails = CityThumbnailCache(dir: paths.thumbnailsDir)
        self.migrationMarkerV2URL = paths.migrationMarkerV2_thumbnailPaths
        self.migrationMarkerV3URL = paths.migrationMarkerV3_intercityToStartingCity
        self.migrationMarkerV4URL = paths.migrationMarkerV4_removeLegacyThumbnails

        loadFromDisk()
        loadMembershipIndexFromDisk()
        migrateThumbnailPathsIfNeeded()
        migrateInterCityRoutesToStartingCitiesIfNeeded()
        removeLegacyDiskThumbnailsIfNeeded()
        handleJourneyStoreLoadedState(journeyStore.hasLoaded)
    }

    private func handleJourneyStoreLoadedState(_ loaded: Bool) {
        if !loaded {
            hasRebuiltForCurrentLoadedState = false
            return
        }
        guard membershipIndex.entries.isEmpty || !hasRebuiltForCurrentLoadedState else { return }
        hasRebuiltForCurrentLoadedState = true
        rebuildFromJourneyStore()
    }
    
    /// Migrate thumbnail paths from absolute paths to relative paths (filenames only).
    private func migrateThumbnailPathsIfNeeded() {
        // Note: routes parameter removed as intercity routes are no longer stored separately
        var emptyRoutes: [CachedInterCityRoute] = []
        let needsSave = DataMigrator.migrateThumbnailPathsToRelative(
            cities: &cachedCities,
            routes: &emptyRoutes,
            markerURL: migrationMarkerV2URL
        )

        if needsSave {
            print("✅ Migrated thumbnail paths to relative format")
            saveToDisk()
        }
    }

    /// Migrate intercity routes to starting cities (V3 migration).
    private func migrateInterCityRoutesToStartingCitiesIfNeeded() {
        // Load routes from disk for migration (they may still exist from old version)
        var oldRoutes: [CachedInterCityRoute] = []
        if let routesFileURL = try? paths.routeCacheURL,
           FileManager.default.fileExists(atPath: routesFileURL.path) {
            do {
                let data = try Data(contentsOf: routesFileURL)
                oldRoutes = try JSONDecoder().decode([CachedInterCityRoute].self, from: data)
            } catch {
                print("⚠️ Failed to load old routes for migration: \(error)")
            }
        }

        let needsSave = DataMigrator.migrateInterCityRoutesToStartingCities(
            routes: oldRoutes,
            cities: &cachedCities,
            journeys: journeyStore.journeys,
            markerURL: migrationMarkerV3URL
        )

        if needsSave {
            print("✅ Migrated intercity routes to starting cities")
            saveToDisk()

            // Delete old routes file after successful migration
            if let routesFileURL = try? paths.routeCacheURL {
                try? FileManager.default.removeItem(at: routesFileURL)
                print("✅ Deleted old intercity routes storage file")
            }
        }
    }

    /// Remove legacy thumbnail files/paths now that city cards render live snapshots.
    private func removeLegacyDiskThumbnailsIfNeeded() {
        guard !fm.fileExists(atPath: migrationMarkerV4URL.path) else { return }

        if fm.fileExists(atPath: paths.thumbnailsDir.path) {
            let files = (try? fm.contentsOfDirectory(at: paths.thumbnailsDir, includingPropertiesForKeys: nil)) ?? []
            for u in files {
                try? fm.removeItem(at: u)
            }
        }

        for i in cachedCities.indices {
            cachedCities[i].thumbnailBasePath = nil
            cachedCities[i].thumbnailRoutePath = nil
        }
        saveToDisk()
        try? Data("ok".utf8).write(to: migrationMarkerV4URL, options: .atomic)
    }

    /// Populate in-memory cities directly without disk I/O.
    /// Used by FriendMirrorContext to avoid async loading flash.
    func loadFromMemory(_ cities: [CachedCity]) {
        var seen = Set<String>()
        self.cachedCities = cities.filter { city in
            if seen.contains(city.id) { return false }
            seen.insert(city.id)
            return true
        }
    }

    // MARK: disk
    func loadFromDisk() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([CachedCity].self, from: data)
            // Deduplicate by city ID
            var seen = Set<String>()
            self.cachedCities = decoded.filter { city in
                if seen.contains(city.id) {
                    return false
                }
                seen.insert(city.id)
                return true
            }
        } catch {
            self.cachedCities = []
        }
        backfillLocalizedNamesFromGeocodeDefaults()
    }

    private func loadMembershipIndexFromDisk() {
        do {
            let data = try Data(contentsOf: membershipIndexURL)
            membershipIndex = try JSONDecoder().decode(CityMembershipIndex.self, from: data)
        } catch {
            membershipIndex = CityMembershipIndex()
        }
    }

    fileprivate func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(cachedCities)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("❌ city cache save failed:", error)
        }
    }

    /// Backfill `localizedDisplayNameByLocale` for historical cities from
    /// ReverseGeocodeService's persisted UserDefaults cache. Runs synchronously
    /// on cold start so all views see localized names immediately.
    private func backfillLocalizedNamesFromGeocodeDefaults() {
        let defaults = UserDefaults(suiteName: "group.com.streetstamps.shared") ?? .standard
        guard let data = defaults.data(forKey: "reverseGeocode.displayCacheByLocaleKey.v2"),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              !dict.isEmpty
        else { return }

        let localeID = LanguagePreference.shared.effectiveLocaleIdentifier
        var changed = false

        for i in cachedCities.indices {
            let city = cachedCities[i]
            if let existing = city.localizedDisplayNameByLocale?[localeID],
               !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            let scope = CityLevelPreferenceStore.shared.displayCacheScope(for: city.parentScopeKey)
            let cacheKey = "\(city.id)|\(localeID)|\(scope)"
            if let title = dict[cacheKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                var d = cachedCities[i].localizedDisplayNameByLocale ?? [:]
                d[localeID] = title
                cachedCities[i].localizedDisplayNameByLocale = d
                changed = true
            }
        }

        if changed { saveToDisk() }
    }

    private func saveMembershipIndexToDisk() {
        do {
            let data = try JSONEncoder().encode(membershipIndex)
            try data.write(to: membershipIndexURL, options: [.atomic])
        } catch {
            print("❌ city membership index save failed:", error)
        }
    }

    // MARK: - Delete
    /// Delete a city card and all journeys under it (hard delete).
    @MainActor
    func deleteCity(id: String) {
        guard let idx = cachedCities.firstIndex(where: { $0.id == id }) else { return }
        let journeyIDs = cachedCities[idx].journeyIds

        if !journeyIDs.isEmpty {
            journeyStore.discardJourneys(ids: journeyIDs)
            rebuildFromJourneyStore()
            return
        }

        cachedCities.remove(at: idx)
        saveToDisk()
        notifyCitiesChanged()
    }

    @MainActor
    func applyCityLevelReassignment(
        from sourceCityKey: String,
        to targetCityKey: String,
        targetCityName: String,
        targetISO2: String?,
        movedJourneys: [JourneyRoute],
        anchor: CLLocationCoordinate2D?
    ) {
        guard !movedJourneys.isEmpty else { return }

        let movedIDs = movedJourneys.map(\.id)
        let movedIDSet = Set(movedIDs)
        let movedMemoriesByID = Dictionary(uniqueKeysWithValues: movedJourneys.map { ($0.id, $0.memories.count) })

        let normalizedISO: String? = {
            let trimmed = (targetISO2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return trimmed.isEmpty ? nil : trimmed
        }()

        var sourceBoundary: [LatLon]? = nil
        var sourceAnchor: LatLon? = nil

        if let sourceIdx = cachedCities.firstIndex(where: { $0.id == sourceCityKey }) {
            sourceBoundary = cachedCities[sourceIdx].boundary
            sourceAnchor = cachedCities[sourceIdx].anchor

            let removedIDs = cachedCities[sourceIdx].journeyIds.filter { movedIDSet.contains($0) }
            let removedMemories = removedIDs.reduce(0) { $0 + (movedMemoriesByID[$1] ?? 0) }

            cachedCities[sourceIdx].journeyIds.removeAll(where: { movedIDSet.contains($0) })
            cachedCities[sourceIdx].explorations = cachedCities[sourceIdx].journeyIds.count
            cachedCities[sourceIdx].memories = max(0, cachedCities[sourceIdx].memories - removedMemories)

            if cachedCities[sourceIdx].journeyIds.isEmpty {
                cachedCities.remove(at: sourceIdx)
            }
        }

        if let targetIdx = cachedCities.firstIndex(where: { $0.id == targetCityKey }) {
            let existingSet = Set(cachedCities[targetIdx].journeyIds)
            let newlyAddedIDs = movedIDs.filter { !existingSet.contains($0) }
            let addedMemories = newlyAddedIDs.reduce(0) { $0 + (movedMemoriesByID[$1] ?? 0) }

            cachedCities[targetIdx].journeyIds.append(contentsOf: newlyAddedIDs)
            cachedCities[targetIdx].explorations = cachedCities[targetIdx].journeyIds.count
            cachedCities[targetIdx].memories += addedMemories
            cachedCities[targetIdx] = CachedCity(
                id: cachedCities[targetIdx].id,
                cityKey: cachedCities[targetIdx].cityKey,
                name: targetCityName,
                canonicalNameEN: cachedCities[targetIdx].canonicalNameEN,
                countryISO2: normalizedISO ?? cachedCities[targetIdx].countryISO2,
                journeyIds: cachedCities[targetIdx].journeyIds,
                explorations: cachedCities[targetIdx].explorations,
                memories: cachedCities[targetIdx].memories,
                boundary: cachedCities[targetIdx].boundary,
                anchor: cachedCities[targetIdx].anchor ?? anchor.map(LatLon.init) ?? sourceAnchor,
                thumbnailBasePath: cachedCities[targetIdx].thumbnailBasePath,
                thumbnailRoutePath: cachedCities[targetIdx].thumbnailRoutePath,
                identityLevelRaw: cachedCities[targetIdx].identityLevelRaw,
                selectedDisplayLevelRaw: cachedCities[targetIdx].selectedDisplayLevelRaw,
                parentScopeKey: cachedCities[targetIdx].parentScopeKey,
                availableLevelNames: cachedCities[targetIdx].availableLevelNames,
                availableLevelNamesLocaleID: cachedCities[targetIdx].availableLevelNamesLocaleID,
                localizedDisplayNameByLocale: cachedCities[targetIdx].localizedDisplayNameByLocale,
                isTemporary: cachedCities[targetIdx].isTemporary
            )
        } else {
            let created = CachedCity(
                id: targetCityKey,
                cityKey: targetCityKey,
                name: targetCityName,
                canonicalNameEN: targetCityName,
                countryISO2: normalizedISO,
                journeyIds: movedIDs,
                explorations: movedIDs.count,
                memories: movedJourneys.reduce(0) { $0 + $1.memories.count },
                boundary: sourceBoundary,
                anchor: anchor.map(LatLon.init) ?? sourceAnchor,
                thumbnailBasePath: nil,
                thumbnailRoutePath: nil,
                identityLevelRaw: nil,
                selectedDisplayLevelRaw: nil,
                parentScopeKey: nil,
                availableLevelNames: nil,
                availableLevelNamesLocaleID: nil,
                isTemporary: false
            )
            cachedCities.append(created)
        }

        generateRouteThumbnail(cityKey: targetCityKey)
        saveToDisk()
        notifyCitiesChanged()
    }

    @MainActor
    func updateCityLevelReserveProfile(
        cityKey: String,
        level: CityPlacemarkResolver.CardLevel?,
        parentRegionKey: String?,
        availableLevels: [CityPlacemarkResolver.CardLevel: String]?,
        availableLevelsLocaleIdentifier: String? = nil,
        anchor: CLLocationCoordinate2D?,
        force: Bool
    ) {
        guard let idx = cachedCities.firstIndex(where: { $0.id == cityKey }) else { return }

        CityLocalizationDebugLogger.log(
            "reserveProfileWrite",
            CityLocalizationDebugTrace.reserveProfileWrite(
                cityKey: cityKey,
                locale: LanguagePreference.shared.displayLocale,
                level: level,
                parentRegionKey: parentRegionKey,
                availableLevels: availableLevels
            )
        )

        if let level, (force || cachedCities[idx].selectedDisplayLevelRaw == nil) {
            cachedCities[idx].selectedDisplayLevelRaw = level.rawValue
        }
        if let parentRegionKey, !parentRegionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cachedCities[idx].parentScopeKey = parentRegionKey
        }
        if let availableLevels {
            let mapped = Dictionary(uniqueKeysWithValues: availableLevels.map { ($0.key.rawValue, $0.value) })
            cachedCities[idx].availableLevelNames = mapped
            let fallbackLocaleID = LanguagePreference.shared.effectiveLocaleIdentifier
            let localeID = (availableLevelsLocaleIdentifier ?? fallbackLocaleID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            cachedCities[idx].availableLevelNamesLocaleID = localeID.isEmpty ? fallbackLocaleID : localeID
            if cachedCities[idx].identityLevelRaw == nil {
                let inferred = CityPlacemarkResolver.identityLevel(
                    cityKey: cachedCities[idx].cityKey,
                    availableLevelNames: availableLevels,
                    iso2: cachedCities[idx].countryISO2
                )
                cachedCities[idx].identityLevelRaw = inferred?.rawValue ?? level?.rawValue
            }
        }
        if let anchor, anchor.isValid, cachedCities[idx].anchor == nil {
            cachedCities[idx].anchor = LatLon(anchor)
        }

        saveToDisk()
        notifyCitiesChanged()
    }

    /// Persist a localized display name for the given city + locale.
    /// Called by CityLibraryVM after a successful reverse-geocode localization.
    @MainActor
    func updateLocalizedDisplayName(cityKey: String, locale: Locale, displayName: String) {
        guard let idx = cachedCities.firstIndex(where: { $0.id == cityKey }) else { return }
        let localeID = locale.identifier
        var dict = cachedCities[idx].localizedDisplayNameByLocale ?? [:]
        guard dict[localeID] != displayName else { return }
        dict[localeID] = displayName
        cachedCities[idx].localizedDisplayNameByLocale = dict
        saveToDisk()
    }

    /// Batch-persist localized display names (avoids repeated disk writes).
    @MainActor
    func updateLocalizedDisplayNames(_ updates: [(cityKey: String, displayName: String)], locale: Locale) {
        let localeID = locale.identifier
        var changed = false
        for update in updates {
            guard let idx = cachedCities.firstIndex(where: { $0.id == update.cityKey }) else { continue }
            var dict = cachedCities[idx].localizedDisplayNameByLocale ?? [:]
            guard dict[localeID] != update.displayName else { continue }
            dict[localeID] = update.displayName
            cachedCities[idx].localizedDisplayNameByLocale = dict
            changed = true
        }
        if changed { saveToDisk() }
    }

    func refreshThumbnailsForCurrentMapAppearance() {
        let stableKeys = cachedCities
            .filter { !($0.isTemporary ?? false) }
            .map(\.id)
        for key in stableKeys {
            generateRouteThumbnail(cityKey: key)
        }
    }

    func rebuildFromJourneyStore() {
        guard journeyStore.hasLoaded else { return }
        membershipIndex = CityCache.buildMembershipIndex(from: journeyStore.journeys)
        saveMembershipIndexToDisk()
        replaceCachedCitiesFromMembershipIndex()
    }

    func applyJourneyMutation(oldJourney: JourneyRoute?, newJourney: JourneyRoute?) {
        let oldContribution = CityMembershipContribution(journey: oldJourney)
        let newContribution = CityMembershipContribution(journey: newJourney)
        guard oldContribution != nil || newContribution != nil else { return }

        membershipIndex.applyJourneyMutation(oldJourney: oldJourney, newJourney: newJourney)
        saveMembershipIndexToDisk()

        let affectedCityKeys = Set([
            oldContribution?.cityKey,
            newContribution?.cityKey
        ].compactMap { $0 })
        refreshCachedCities(for: affectedCityKeys, preferredAnchorJourney: newJourney)
    }

    private static func buildMembershipIndex(from journeys: [JourneyRoute]) -> CityMembershipIndex {
        var index = CityMembershipIndex()
        for journey in journeys where journey.isCompleted {
            index.applyJourneyMutation(oldJourney: nil, newJourney: journey)
        }
        return index
    }

    private func replaceCachedCitiesFromMembershipIndex() {
        let stableExistingByKey = Dictionary(
            uniqueKeysWithValues: cachedCities
                .filter { !($0.isTemporary ?? false) }
                .map { ($0.id, $0) }
        )

        let rebuilt = membershipIndex.entries.values.map { entry in
            makeCachedCity(from: entry, previous: stableExistingByKey[entry.cityKey], preferredAnchorJourney: nil)
        }

        let temps = cachedCities.filter { $0.isTemporary ?? false }
        let sortedStable = sortStableCities(rebuilt)
        cachedCities = sortedStable + temps
        saveToDisk()
        notifyCitiesChanged()
    }

    private func refreshCachedCities(for cityKeys: Set<String>, preferredAnchorJourney: JourneyRoute?) {
        guard !cityKeys.isEmpty else { return }

        var stableCities = cachedCities.filter { !($0.isTemporary ?? false) }
        let existingByKey = Dictionary(uniqueKeysWithValues: stableCities.map { ($0.id, $0) })

        stableCities.removeAll { cityKeys.contains($0.id) }

        for cityKey in cityKeys {
            guard let entry = membershipIndex.entries[cityKey] else { continue }
            let preferredJourney: JourneyRoute?
            if let preferredAnchorJourney, entry.journeyIDs.contains(preferredAnchorJourney.id) {
                preferredJourney = preferredAnchorJourney
            } else {
                preferredJourney = nil
            }
            stableCities.append(
                makeCachedCity(from: entry, previous: existingByKey[cityKey], preferredAnchorJourney: preferredJourney)
            )
        }

        let temps = cachedCities.filter { $0.isTemporary ?? false }
        cachedCities = sortStableCities(stableCities) + temps
        saveToDisk()
        notifyCitiesChanged()
    }

    private func makeCachedCity(
        from entry: CityMembershipEntry,
        previous: CachedCity?,
        preferredAnchorJourney: JourneyRoute?
    ) -> CachedCity {
        let anchorCoord = preferredAnchorJourney?.startCoordinate?.isValid == true
            ? preferredAnchorJourney?.startCoordinate
            : previous?.anchor?.cl

        return CachedCity(
            id: entry.cityKey,
            cityKey: entry.cityKey,
            name: entry.cityName,
            canonicalNameEN: previous?.canonicalNameEN ?? entry.cityName,
            countryISO2: entry.countryISO2,
            journeyIds: entry.journeyIDs,
            explorations: entry.explorations,
            memories: entry.memories,
            boundary: previous?.boundary,
            anchor: anchorCoord.map(LatLon.init),
            thumbnailBasePath: previous?.thumbnailBasePath,
            thumbnailRoutePath: previous?.thumbnailRoutePath,
            identityLevelRaw: previous?.identityLevelRaw,
            selectedDisplayLevelRaw: previous?.selectedDisplayLevelRaw,
            parentScopeKey: previous?.parentScopeKey,
            availableLevelNames: previous?.availableLevelNames,
            availableLevelNamesLocaleID: previous?.availableLevelNamesLocaleID,
            localizedDisplayNameByLocale: previous?.localizedDisplayNameByLocale,
            isTemporary: false
        )
    }

    private func sortStableCities(_ cities: [CachedCity]) -> [CachedCity] {
        cities.sorted {
            if $0.explorations != $1.explorations { return $0.explorations > $1.explorations }
            return $0.name < $1.name
        }
    }

    // ===================================================
    // MARK: - Public APIs
    // ===================================================

    /// 完成旅程：TEMP -> canonical + route thumb
    ///
    /// Key policy:
    /// - Prefer journey's own card key (`startCityKey` / `cityKey`) as the single city concept.
    /// - Only fall back to reverse geocode when no usable key exists.
    /// - Unlock is tied to card creation, not level reassignment.
    private func normalizedCardKey(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Unknown|" else { return nil }
        return trimmed
    }

    private func splitCityKey(_ cityKey: String) -> (name: String, iso: String) {
        let parts = cityKey.split(separator: "|", omittingEmptySubsequences: false)
        let name = parts.first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let iso = parts.dropFirst().first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        return (name, iso)
    }

    private func resolveCardIdentity(for journey: JourneyRoute) -> (key: String, name: String, iso: String)? {
        guard let key = normalizedCardKey(journey.startCityKey) ?? normalizedCardKey(journey.cityKey) else {
            return nil
        }
        let split = splitCityKey(key)
        let canonicalName = journey.canonicalCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = split.name.isEmpty ? canonicalName : split.name
        guard !finalName.isEmpty else { return nil }
        let fallbackISO = (journey.countryISO2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let finalISO = split.iso.isEmpty ? fallbackISO : split.iso
        guard !finalISO.isEmpty, finalISO.count == 2 else { return nil }
        return (key, finalName, finalISO)
    }

    @discardableResult
    func onJourneyCompleted(_ journey: JourneyRoute) -> CityEvent? {
        guard journey.isCompleted else { return nil }

        // Primary path: trust the journey's own card key to keep city identity stable.
        if let identity = resolveCardIdentity(for: journey) {
            return finishCompleteWithCanonical(
                journey: journey,
                canonicalKey: identity.key,
                canonicalName: identity.name,
                iso: identity.iso,
                reserveLevel: nil,
                reserveParentRegionKey: nil,
                reserveAvailableLevels: nil,
                reserveAnchor: journey.startCoordinate
            )
        }

        // Fallback path: derive from START coordinate when key is unavailable.
        if let start = journey.allCLCoords.first {
            let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)

            reverseGeocodeCity(startLoc) { [weak self] result in
                guard let self else { return }

                if let r = result {
                    let identityKey = r.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    let identityName = CityPlacemarkResolver.stableCityName(
                        from: identityKey,
                        fallback: r.cityName
                    )
                    _ = self.finishCompleteWithCanonical(
                        journey: journey,
                        canonicalKey: identityKey,
                        canonicalName: identityName,
                        iso: (r.iso2 ?? ""),
                        reserveLevel: r.level,
                        reserveParentRegionKey: r.parentRegionKey,
                        reserveAvailableLevels: r.availableLevels,
                        reserveAvailableLevelsLocaleIdentifier: r.localeIdentifier,
                        reserveAnchor: journey.startCoordinate
                    )
                    return
                }

                // Final fallback - if no reliable key exists, skip card creation.
                let fallbackKey = self.normalizedCardKey(journey.canonicalCityKeyFallback)
                guard let fallbackKey else { return }
                let collectionKey = CityCollectionResolver.resolveCollectionKey(cityKey: fallbackKey)
                let fallbackName = CityDisplayResolver.title(
                    for: collectionKey,
                    fallbackTitle: journey.displayCityName
                )
                let fallbackIso = (journey.countryISO2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

                _ = self.finishCompleteWithCanonical(
                    journey: journey,
                    canonicalKey: fallbackKey,
                    canonicalName: fallbackName,
                    iso: fallbackIso,
                    reserveLevel: nil,
                    reserveParentRegionKey: nil,
                    reserveAvailableLevels: nil,
                    reserveAnchor: journey.startCoordinate
                )
            }

            // async path: event will be published via lastEvent
            return nil
        }

        // no coords fallback
        guard let fallbackKey = normalizedCardKey(journey.canonicalCityKeyFallback) else {
            return nil
        }
        let collectionKey = CityCollectionResolver.resolveCollectionKey(cityKey: fallbackKey)
        let fallbackName = CityDisplayResolver.title(
            for: collectionKey,
            fallbackTitle: journey.displayCityName
        )
        let fallbackIso = (journey.countryISO2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return finishCompleteWithCanonical(
            journey: journey,
            canonicalKey: fallbackKey,
            canonicalName: fallbackName,
            iso: fallbackIso,
            reserveLevel: nil,
            reserveParentRegionKey: nil,
            reserveAvailableLevels: nil,
            reserveAnchor: journey.startCoordinate
        )
    }

    func payload(for cityKey: String) -> UnlockedPayload? {
        guard let c = cachedCities.first(where: { $0.id == cityKey && !($0.isTemporary ?? false) }) else {
            return nil
        }
        return UnlockedPayload(
            id: c.id,
            kind: .city,
            title: CityPlacemarkResolver.displayTitle(
                cityKey: c.id,
                iso2: c.countryISO2,
                fallbackTitle: c.name,
                availableLevelNamesRaw: c.availableLevelNames,
                storedAvailableLevelNamesLocaleID: c.availableLevelNamesLocaleID,
                parentRegionKey: c.parentScopeKey,
                preferredLevel: c.selectedDisplayLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
                localizedDisplayNameByLocale: c.localizedDisplayNameByLocale,
                locale: LanguagePreference.shared.displayLocale
            ),
            subtitle: c.countryISO2,
            baseThumbPath: nil,
            routeThumbPath: nil
        )
    }

    func consumePendingUnlock() -> UnlockedPayload? {
        let p = pendingUnlock
        pendingUnlock = nil
        return p
    }

    // ===================================================
    // MARK: - Finish logic (shared)
    // ===================================================

    @discardableResult
    private func finishCompleteWithCanonical(
        journey: JourneyRoute,
        canonicalKey: String,
        canonicalName: String,
        iso: String,
        reserveLevel: CityPlacemarkResolver.CardLevel?,
        reserveParentRegionKey: String?,
        reserveAvailableLevels: [CityPlacemarkResolver.CardLevel: String]?,
        reserveAvailableLevelsLocaleIdentifier: String? = nil,
        reserveAnchor: CLLocationCoordinate2D?
    ) -> CityEvent? {
        let key = canonicalKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "Unknown|" else { return nil }

        let tmpKey = temporaryCityKey(for: journey.id)
        let existedBefore = cachedCities.contains(where: { $0.id == key && !($0.isTemporary ?? false) })

        mergeTemporaryCityIfNeeded(
            tmpKey: tmpKey,
            canonicalKey: key,
            canonicalName: canonicalName,
            iso: iso
        )

        var indexedJourney = journey
        indexedJourney.startCityKey = key
        indexedJourney.cityKey = key
        indexedJourney.cityName = canonicalName
        indexedJourney.canonicalCity = canonicalName
        indexedJourney.countryISO2 = iso.isEmpty ? journey.countryISO2 : iso

        applyJourneyMutation(oldJourney: nil, newJourney: indexedJourney)
        updateCityLevelReserveProfile(
            cityKey: key,
            level: reserveLevel,
            parentRegionKey: reserveParentRegionKey,
            availableLevels: reserveAvailableLevels,
            availableLevelsLocaleIdentifier: reserveAvailableLevelsLocaleIdentifier,
            anchor: reserveAnchor,
            force: false
        )
        generateRouteThumbnail(cityKey: key)
        setPendingUnlockIfNeeded(cityKey: key, existedBefore: existedBefore)

        let event: CityEvent = existedBefore
            ? .updatedCity(cityKey: key)
            : .addedNewCity(cityKey: key, name: canonicalName)

        lastEvent = event
        return event
    }

    // ===================================================
    // MARK: - Temporary helpers
    // ===================================================

    private func temporaryCityKey(for journeyId: String) -> String { "__TMP__|\(journeyId)" }

    private func upsertTemporaryCity(tmpKey: String, anchor: CLLocationCoordinate2D?) {
        if let idx = cachedCities.firstIndex(where: { $0.id == tmpKey }) {
            var c = cachedCities[idx]
            if c.anchor == nil, let a = anchor, a.isValid { c.anchor = LatLon(a) }
            c.isTemporary = true
            cachedCities[idx] = c
        } else {
            let c = CachedCity(
                id: tmpKey,
                name: "Exploring…",
                countryISO2: nil,
                journeyIds: [],
                explorations: 0,
                memories: 0,
                boundary: nil,
                anchor: (anchor?.isValid == true) ? LatLon(anchor!) : nil,
                thumbnailBasePath: nil,
                thumbnailRoutePath: nil,
                isTemporary: true
            )
            cachedCities.append(c)
        }
        saveToDisk()
    }

    private func mergeTemporaryCityIfNeeded(tmpKey: String, canonicalKey: String, canonicalName: String, iso: String) {
        let tmpIdx = cachedCities.firstIndex(where: { $0.id == tmpKey })
        let canonIdx = cachedCities.firstIndex(where: { $0.id == canonicalKey && !($0.isTemporary ?? false) })

        guard let tmpIdx else {
            upsertCanonicalCityCard(cityKey: canonicalKey, cityName: canonicalName, iso2: iso.isEmpty ? nil : iso, anchor: nil)
            return
        }

        var tmp = cachedCities[tmpIdx]

        if let canonIdx {
            var canon = cachedCities[canonIdx]

            if canon.anchor == nil { canon.anchor = tmp.anchor }
            if canon.thumbnailBasePath == nil { canon.thumbnailBasePath = tmp.thumbnailBasePath }
            if canon.thumbnailRoutePath == nil { canon.thumbnailRoutePath = tmp.thumbnailRoutePath }

            canon.journeyIds = Array(Set(canon.journeyIds + tmp.journeyIds))
            canon.isTemporary = false
            cachedCities[canonIdx] = canon

            cachedCities.removeAll { $0.id == tmpKey }
            saveToDisk()
            return
        }

        // rename temp -> canonical (no second card)
        tmp = CachedCity(
            id: canonicalKey,
            name: canonicalName,
            countryISO2: iso.isEmpty ? nil : iso,
            journeyIds: tmp.journeyIds,
            explorations: tmp.explorations,
            memories: tmp.memories,
            boundary: tmp.boundary,
            anchor: tmp.anchor,
            thumbnailBasePath: tmp.thumbnailBasePath,
            thumbnailRoutePath: tmp.thumbnailRoutePath,
            localizedDisplayNameByLocale: tmp.localizedDisplayNameByLocale,
            isTemporary: false
        )

        cachedCities[tmpIdx] = tmp
        saveToDisk()
    }

    // ===================================================
    // MARK: - Canonical upsert / recompute
    // ===================================================

    private func upsertCanonicalCityCard(cityKey: String, cityName: String, iso2: String?, anchor: CLLocationCoordinate2D?) {
        if let idx = cachedCities.firstIndex(where: { $0.id == cityKey && !($0.isTemporary ?? false) }) {
            var c = cachedCities[idx]
            if c.anchor == nil, let a = anchor, a.isValid { c.anchor = LatLon(a) }
            c.isTemporary = false
            cachedCities[idx] = c
        } else {
            let c = CachedCity(
                id: cityKey,
                name: cityName,
                countryISO2: iso2,
                journeyIds: [],
                explorations: 0,
                memories: 0,
                boundary: nil,
                anchor: (anchor?.isValid == true) ? LatLon(anchor!) : nil,
                thumbnailBasePath: nil,
                thumbnailRoutePath: nil,
                isTemporary: false
            )
            cachedCities.append(c)
        }

        cachedCities.sort {
            if $0.explorations != $1.explorations { return $0.explorations > $1.explorations }
            return $0.name < $1.name
        }
        saveToDisk()
    }

    private func refreshCityFromStore(cityKey: String) {
        let journeys = journeyStore.journeys
        // Include ALL journeys starting from this city (including intercity journeys)
        let completedInCity = journeyStore.journeys.filter {
            $0.isCompleted
            && $0.startCityKey == cityKey
        }


        guard let idx = cachedCities.firstIndex(where: { $0.id == cityKey && !($0.isTemporary ?? false) }) else { return }
        var c = cachedCities[idx]

        c.journeyIds = completedInCity.map { $0.id }
        c.explorations = completedInCity.count
        c.memories = completedInCity.reduce(0) { $0 + $1.memoryCount }

        cachedCities[idx] = c

        cachedCities.sort {
            if $0.explorations != $1.explorations { return $0.explorations > $1.explorations }
            return $0.name < $1.name
        }
        saveToDisk()
    }

    // ===================================================
    // MARK: - Snapshot generation
    // ===================================================

    private func generateBaseThumbnailIfNeeded(cityKey: String) {
        guard let idx = cachedCities.firstIndex(where: { $0.id == cityKey }) else { return }

        // Check if thumbnail already exists using the static resolver
        if CityThumbnailCache.thumbnailExists(cachedCities[idx].thumbnailBasePath) { return }

        let baseURL = thumbnails.urlBase(cityKey: cityKey)
        let baseFilename = thumbnails.filenameBase(cityKey: cityKey)

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            let (boundary, anchor) = await MainActor.run { () -> ([CLLocationCoordinate2D]?, CLLocationCoordinate2D?) in
                let c = self.cachedCities.first(where: { $0.id == cityKey })
                return (c?.boundary?.map { $0.cl }, c?.anchor?.cl)
            }

            // MapKit basemap in China uses GCJ-02. Keep our stored coords in WGS84, and adapt only for MapKit rendering.
            let boundaryForMap = boundary.map { MapCoordAdapter.forMapKit($0, cityKey: cityKey) }
            let anchorForMap = anchor.map { MapCoordAdapter.forMapKit($0, cityKey: cityKey) }

            let fallbackWGS: [CLLocationCoordinate2D] = boundary ?? (anchor.map { [$0] } ?? [])
            let fallbackForMap = MapCoordAdapter.forMapKit(fallbackWGS)

            guard let region = regionForCityWhole(boundary: boundaryForMap, bboxOrRouteCoords: fallbackForMap, anchor: anchorForMap) else { return }

            let cacheKey = "base|\(cityKey)|\(region.center.latitude.rounded(to: 3))|\(region.center.longitude.rounded(to: 3))"

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                CitySnapshotService.shared.renderSnapshot(
                    cacheKey: cacheKey,
                    region: region,
                    overlaySegments: [],
                    isFlightLike: false,
                    drawRoute: false
                ) { img in
                    guard let img else { cont.resume(); return }

                    // Store only the filename (relative path), not the full path

                    Task { @MainActor in
                        self.thumbnails.save(img, to: baseURL)
                        guard let idx2 = self.cachedCities.firstIndex(where: { $0.id == cityKey }) else { return }
                        self.cachedCities[idx2].thumbnailBasePath = baseFilename
                        self.notifyCitiesChanged()
                        self.saveToDisk()
                    }
                    cont.resume()
                }
            }
        }
    }

    private func generateRouteThumbnail(cityKey: String) {
        let routeURL = thumbnails.urlRoute(cityKey: cityKey)
        let routeFilename = thumbnails.filenameRoute(cityKey: cityKey)

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            let (boundary, anchor, allRouteCoords) = await MainActor.run { () -> ([CLLocationCoordinate2D]?, CLLocationCoordinate2D?, [CLLocationCoordinate2D]) in
                let c = self.cachedCities.first(where: { $0.id == cityKey })
                let b = c?.boundary?.map { $0.cl }
                let a = c?.anchor?.cl

                // Only include city-local journeys for thumbnail (not intercity journeys)
                let js = self.journeyStore.journeys.filter {
                    $0.isCompleted &&
                    $0.startCityKey == cityKey &&
                    $0.endCityKey == cityKey
                }
                let coords = js.flatMap { $0.allCLCoords }.filter { $0.isValid }
                return (b, a, coords)
            }

            let boundaryForMap = boundary.map { MapCoordAdapter.forMapKit($0, cityKey: cityKey) }
            let anchorForMap = anchor.map { MapCoordAdapter.forMapKit($0, cityKey: cityKey) }
            
            // Build route segments only if we have route data
            let hasRouteData = !allRouteCoords.isEmpty
            let overlaySegments: [RenderRouteSegment]
            let isFlightLike: Bool
            let bboxLike: [CLLocationCoordinate2D]
            
            if hasRouteData {
                let built = RouteRenderingPipeline.buildSegments(
                    .init(coordsWGS84: allRouteCoords, applyGCJForChina: false, gapDistanceMeters: 8_000, cityKey: cityKey),
                    surface: .mapKit
                )
                overlaySegments = built.segments
                isFlightLike = built.isFlightLike
                let overlayForMapFlat = overlaySegments.flatMap { $0.coords }
                bboxLike = bboxPolygon(for: overlayForMapFlat) ?? overlayForMapFlat
            } else {
                // No route data - just show the map based on boundary/anchor
                overlaySegments = []
                isFlightLike = false
                bboxLike = boundaryForMap ?? (anchorForMap.map { [$0] } ?? [])
            }

            guard let region = regionForCityWhole(boundary: boundaryForMap, bboxOrRouteCoords: bboxLike, anchor: anchorForMap) else { return }

            let cacheKey = "route|\(cityKey)|\(hasRouteData ? overlaySegments.flatMap { $0.coords }.count : 0)|\(region.center.latitude.rounded(to: 3))|\(region.center.longitude.rounded(to: 3))"

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                CitySnapshotService.shared.renderSnapshot(
                    cacheKey: cacheKey,
                    region: region,
                    overlaySegments: overlaySegments,
                    isFlightLike: isFlightLike,
                    drawRoute: hasRouteData
                ) { img in
                    guard let img else { cont.resume(); return }

                    // Store only the filename (relative path), not the full path

                    Task { @MainActor in
                        self.thumbnails.save(img, to: routeURL)
                        guard let idx2 = self.cachedCities.firstIndex(where: { $0.id == cityKey }) else { return }
                        self.cachedCities[idx2].thumbnailRoutePath = routeFilename
                        self.notifyCitiesChanged()
                        self.saveToDisk()
                    }
                    cont.resume()
                }
            }
        }
    }

    // ===================================================
    // MARK: - Reverse geocode (fixed locale + cancel)
    // ===================================================

    private func reverseGeocodeCity(
        _ location: CLLocation,
        completion: @escaping (ReverseGeocodeService.CanonicalResult?) -> Void
    ) {
        // ✅ cancel stale callbacks (but do NOT spam system geocoder)
        geocodeTask?.cancel()

        geocodeTask = Task {
            let result = await ReverseGeocodeService.shared.canonical(for: location)
            if Task.isCancelled { return }

            await MainActor.run {
                completion(result)
            }
        }
    }


    // ===================================================
    // MARK: - Unlock logic
    // ===================================================

    private func setPendingUnlockIfNeeded(cityKey: String, existedBefore: Bool) {
        guard !existedBefore else { return }
        guard let c = cachedCities.first(where: { $0.id == cityKey && !($0.isTemporary ?? false) }) else { return }
        guard c.explorations == 1 else { return }

        pendingUnlock = UnlockedPayload(
            id: c.id,
            kind: .city,
            title: CityPlacemarkResolver.displayTitle(
                cityKey: c.id,
                iso2: c.countryISO2,
                fallbackTitle: c.name,
                availableLevelNamesRaw: c.availableLevelNames,
                storedAvailableLevelNamesLocaleID: c.availableLevelNamesLocaleID,
                parentRegionKey: c.parentScopeKey,
                preferredLevel: c.selectedDisplayLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
                localizedDisplayNameByLocale: c.localizedDisplayNameByLocale,
                locale: LanguagePreference.shared.displayLocale
            ),
            subtitle: c.countryISO2,
            baseThumbPath: nil,
            routeThumbPath: nil
        )
    }
}

// MARK: - small helper
private extension Double {
    func rounded(to places: Int) -> Double {
        guard places >= 0 else { return self }
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }}
