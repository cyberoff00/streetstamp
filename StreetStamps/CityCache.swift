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
        displayRouteCoordinates.map { $0.cl }.filter { $0.isValid }
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
// Locale-independent identity model. All fields are en_US or locale-free.
// Display name translation happens at render time via CityNameTranslationCache.
struct CachedCity: Identifiable, Codable {
    let id: String                 // identity key; canonical: "name|ISO2" or temp: "__TMP__|journeyId"
    let cityKey: String
    let name: String               // en_US fallback display name
    let canonicalNameEN: String    // en_US canonical name
    let countryISO2: String?

    var journeyIds: [String]
    var explorations: Int
    var memories: Int

    var boundary: [LatLon]?
    var anchor: LatLon?

    var thumbnailBasePath: String?
    var thumbnailRoutePath: String?

    var parentScopeKey: String? = nil
    /// The level at which this city was created (e.g. "locality", "subAdmin", "admin").
    /// Written once at city creation time by resolveCanonical. Never inferred.
    var identityLevelRaw: String? = nil
    /// en_US level names from canonical geocode. Keys are CardLevel.rawValue.
    var availableLevelNamesEN: [String: String]? = nil

    var isTemporary: Bool? = false
    var isPhotoDiscovered: Bool? = nil
    var photoCount: Int? = nil
    var photoDateRange: String? = nil

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
        parentScopeKey: String? = nil,
        identityLevelRaw: String? = nil,
        availableLevelNamesEN: [String: String]? = nil,
        isTemporary: Bool? = false,
        isPhotoDiscovered: Bool? = nil,
        photoCount: Int? = nil,
        photoDateRange: String? = nil
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
        self.parentScopeKey = parentScopeKey
        self.identityLevelRaw = identityLevelRaw
        self.availableLevelNamesEN = availableLevelNamesEN
        self.isTemporary = isTemporary
        self.isPhotoDiscovered = isPhotoDiscovered
        self.photoCount = photoCount
        self.photoDateRange = photoDateRange
    }

    /// The en_US display name extracted from cityKey — the only reliable source.
    var englishName: String {
        let fromKey = cityKey.components(separatedBy: "|").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fromKey.isEmpty ? name : fromKey
    }

    /// The display name for UI. Checks translation cache first, falls back to en_US.
    var displayTitle: String {
        let localeID = LanguagePreference.shared.effectiveLocaleIdentifier
        if localeID.hasPrefix("en") { return englishName }
        if let translated = CityNameTranslationCache.shared.cachedName(cityKey: cityKey, localeID: localeID) {
            return translated
        }
        return englishName
    }

    /// The identity level stored at city creation time.
    var identityLevel: CityPlacemarkResolver.CardLevel {
        identityLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) } ?? .locality
    }

    // MARK: - Codable (backwards-compatible decode, clean encode)

    enum CodingKeys: String, CodingKey {
        case id, cityKey, name, canonicalNameEN, countryISO2
        case journeyIds, explorations, memories
        case boundary, anchor
        case thumbnailBasePath, thumbnailRoutePath
        case parentScopeKey, identityLevelRaw
        case availableLevelNamesEN
        case isTemporary, isPhotoDiscovered, photoCount, photoDateRange
        // Legacy keys — read during decode for migration, never written
        case selectedDisplayLevelRaw
        case availableLevelNames, availableLevelNamesLocaleID
        case localizedDisplayNameByLocale
        case resolvedDisplayName, resolvedDisplayNameLocaleID
        case reservedLevelRaw, reservedParentRegionKey
        case reservedAvailableLevelNames, reservedAvailableLevelNamesLocaleID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)

        // Only read canonical keys. All legacy/locale-dependent fields
        // (availableLevelNames, reservedParentRegionKey, localizedDisplayNameByLocale, etc.)
        // are NOT trusted — repairAllCityIdentityData() re-geocodes with en_US and fills
        // the correct values for parentScopeKey, identityLevelRaw, availableLevelNamesEN.

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
            parentScopeKey: try container.decodeIfPresent(String.self, forKey: .parentScopeKey),
            identityLevelRaw: try container.decodeIfPresent(String.self, forKey: .identityLevelRaw),
            availableLevelNamesEN: try container.decodeIfPresent([String: String].self, forKey: .availableLevelNamesEN),
            isTemporary: try container.decodeIfPresent(Bool.self, forKey: .isTemporary),
            isPhotoDiscovered: try container.decodeIfPresent(Bool.self, forKey: .isPhotoDiscovered),
            photoCount: try container.decodeIfPresent(Int.self, forKey: .photoCount),
            photoDateRange: try container.decodeIfPresent(String.self, forKey: .photoDateRange)
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
        try container.encodeIfPresent(parentScopeKey, forKey: .parentScopeKey)
        try container.encodeIfPresent(identityLevelRaw, forKey: .identityLevelRaw)
        try container.encodeIfPresent(availableLevelNamesEN, forKey: .availableLevelNamesEN)
        try container.encodeIfPresent(isTemporary, forKey: .isTemporary)
        try container.encodeIfPresent(isPhotoDiscovered, forKey: .isPhotoDiscovered)
        try container.encodeIfPresent(photoCount, forKey: .photoCount)
        try container.encodeIfPresent(photoDateRange, forKey: .photoDateRange)
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
        let currentStyle = MapLayerStyle.current
        options.region = safeRegion
        options.size = Tokens.size
        options.scale = Tokens.scale
        options.mapType = currentStyle.mapKitType
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: currentStyle.mapKitInterfaceStyle),
            UITraitCollection(displayScale: Tokens.scale),
            UITraitCollection(activeAppearance: .active),
            UITraitCollection(userInterfaceLevel: .base)
        ])
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
                            let isDark = currentStyle.isDarkStyle
                            RouteSnapshotDrawer.draw(
                                segments: overlaySegments,
                                isFlightLike: isFlightLike,
                                snapshot: snapshot,
                                ctx: renderer.cgContext,
                                coreColor: currentStyle.routeBaseColor.withAlphaComponent(isDark ? 0.78 : 1.0),
                                stroke: .init(coreWidth: 3.5),
                                glowColor: currentStyle.routeGlowColor,
                                isDarkMap: isDark
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

    // MARK: - Photo discovery

    enum PhotoDiscoveryProgress: Equatable {
        case idle
        case scanning(done: Int, total: Int)
        case completed(newCities: [String])
        case noNewCities
    }

    @Published var photoDiscoveryProgress: PhotoDiscoveryProgress = .idle

    @Published private(set) var cachedCities: [CachedCity] = []
    @Published private(set) var lastEvent: CityEvent? = nil
    @Published private(set) var pendingUnlock: UnlockedPayload? = nil

    /// Keyed lookup excluding temporary cities. Lazily rebuilt when `cachedCities` changes.
    var cachedCitiesByKey: [String: CachedCity] {
        if let cached = _cachedCitiesByKey { return cached }
        let dict: [String: CachedCity] = cachedCities
            .filter { !($0.isTemporary ?? false) }
            .reduce(into: [:]) { acc, city in acc[city.id] = city }
        _cachedCitiesByKey = dict
        return dict
    }
    private var _cachedCitiesByKey: [String: CachedCity]?

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
    private var migrationMarkerV6URL: URL
    private var migrationMarkerV7URL: URL
    private var paths: StoragePath
    private var membershipIndex = CityMembershipIndex()
    private var cancellables: Set<AnyCancellable> = []
    private var hasRebuiltForCurrentLoadedState = false
    private let diskQueue = DispatchQueue(label: "CityCache.disk", qos: .utility)
    private var savePending = false
    private var saveScheduled = false

    init(paths: StoragePath, journeyStore: JourneyStore) {
        self.fileURL = paths.cityCacheURL
        self.membershipIndexURL = paths.cityMembershipIndexURL
        self.journeyStore = journeyStore
        self.thumbnails = CityThumbnailCache(dir: paths.thumbnailsDir)
        self.migrationMarkerV2URL = paths.migrationMarkerV2_thumbnailPaths
        self.migrationMarkerV3URL = paths.migrationMarkerV3_intercityToStartingCity
        self.migrationMarkerV4URL = paths.migrationMarkerV4_removeLegacyThumbnails
        self.migrationMarkerV6URL = paths.migrationMarkerV6_autoLevelRekey
        self.migrationMarkerV7URL = paths.migrationMarkerV7_strategyV2Rekey
        self.paths = paths
        // Disk I/O deferred to loadInitialData() to avoid blocking app launch.

        $cachedCities
            .sink { [weak self] _ in
                self?._cachedCitiesByKey = nil
            }
            .store(in: &cancellables)

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

    /// Load cached cities, membership index, and run any pending migrations.
    /// Called during the async startup phase (while splash is visible) so that
    /// init() stays lightweight and does not block the first frame.
    func loadInitialData() {
        loadFromDisk()
        loadMembershipIndexFromDisk()
        migrateThumbnailPathsIfNeeded()
        migrateInterCityRoutesToStartingCitiesIfNeeded()
        removeLegacyDiskThumbnailsIfNeeded()
        handleJourneyStoreLoadedState(journeyStore.hasLoaded)
        loadPhotoDiscoveredFromDisk()
    }

    /// Async variant that moves JSON decode off the main thread.
    /// Safe to use in startup .task because cachedCities is first consumed
    /// after `await journeyLoad` completes (StreetStampsApp Phase 2).
    func loadInitialDataAsync() async {
        let cityURL = fileURL
        let membershipURL = membershipIndexURL

        // Heavy JSON decode on background queue
        let (cities, membership) = await withCheckedContinuation { (cont: CheckedContinuation<([CachedCity], CityMembershipIndex), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var decodedCities: [CachedCity] = []
                if let data = try? Data(contentsOf: cityURL) {
                    decodedCities = (try? JSONDecoder().decode([CachedCity].self, from: data)) ?? []
                }
                // Deduplicate by city ID
                var seen = Set<String>()
                decodedCities = decodedCities.filter { seen.insert($0.id).inserted }

                var decodedIndex = CityMembershipIndex()
                if let data = try? Data(contentsOf: membershipURL) {
                    decodedIndex = (try? JSONDecoder().decode(CityMembershipIndex.self, from: data)) ?? CityMembershipIndex()
                }

                cont.resume(returning: (decodedCities, decodedIndex))
            }
        }

        // Guard: if the task was cancelled (profile switched again), don't overwrite
        // current store with data from the old profile's files.
        guard !Task.isCancelled, self.fileURL == cityURL else { return }

        // Apply on main thread (lightweight: property assignment + string iteration)
        self.cachedCities = cities
        self.membershipIndex = membership
        invalidateThumbnailsIfStyleChanged()
        migrateThumbnailPathsIfNeeded()
        migrateInterCityRoutesToStartingCitiesIfNeeded()
        removeLegacyDiskThumbnailsIfNeeded()
        handleJourneyStoreLoadedState(journeyStore.hasLoaded)
        loadPhotoDiscoveredFromDisk()
    }

    func rebind(paths: StoragePath) {
        self.paths = paths
        self.fileURL = paths.cityCacheURL
        self.membershipIndexURL = paths.cityMembershipIndexURL
        self.thumbnails = CityThumbnailCache(dir: paths.thumbnailsDir)
        self.migrationMarkerV2URL = paths.migrationMarkerV2_thumbnailPaths
        self.migrationMarkerV3URL = paths.migrationMarkerV3_intercityToStartingCity
        self.migrationMarkerV4URL = paths.migrationMarkerV4_removeLegacyThumbnails
        self.migrationMarkerV6URL = paths.migrationMarkerV6_autoLevelRekey
        self.migrationMarkerV7URL = paths.migrationMarkerV7_strategyV2Rekey

        loadFromDisk()
        loadMembershipIndexFromDisk()
        migrateThumbnailPathsIfNeeded()
        migrateInterCityRoutesToStartingCitiesIfNeeded()
        removeLegacyDiskThumbnailsIfNeeded()
        handleJourneyStoreLoadedState(journeyStore.hasLoaded)
        loadPhotoDiscoveredFromDisk()
    }

    /// Async rebind that moves JSON decode off the main thread.
    func rebindAsync(paths: StoragePath) async {
        self.paths = paths
        self.fileURL = paths.cityCacheURL
        self.membershipIndexURL = paths.cityMembershipIndexURL
        self.thumbnails = CityThumbnailCache(dir: paths.thumbnailsDir)
        self.migrationMarkerV2URL = paths.migrationMarkerV2_thumbnailPaths
        self.migrationMarkerV3URL = paths.migrationMarkerV3_intercityToStartingCity
        self.migrationMarkerV4URL = paths.migrationMarkerV4_removeLegacyThumbnails
        self.migrationMarkerV6URL = paths.migrationMarkerV6_autoLevelRekey
        self.migrationMarkerV7URL = paths.migrationMarkerV7_strategyV2Rekey

        let cityURL = fileURL
        let membershipURL = membershipIndexURL
        let (cities, membership) = await withCheckedContinuation { (cont: CheckedContinuation<([CachedCity], CityMembershipIndex), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var decodedCities: [CachedCity] = []
                if let data = try? Data(contentsOf: cityURL) {
                    decodedCities = (try? JSONDecoder().decode([CachedCity].self, from: data)) ?? []
                }
                var seen = Set<String>()
                decodedCities = decodedCities.filter { seen.insert($0.id).inserted }

                var decodedIndex = CityMembershipIndex()
                if let data = try? Data(contentsOf: membershipURL) {
                    decodedIndex = (try? JSONDecoder().decode(CityMembershipIndex.self, from: data)) ?? CityMembershipIndex()
                }
                cont.resume(returning: (decodedCities, decodedIndex))
            }
        }

        // Guard: if the task was cancelled or another rebind changed the paths,
        // discard stale data to avoid overwriting the current profile.
        guard !Task.isCancelled, self.fileURL == cityURL else { return }

        self.cachedCities = cities
        self.membershipIndex = membership
        invalidateThumbnailsIfStyleChanged()
        migrateThumbnailPathsIfNeeded()
        migrateInterCityRoutesToStartingCitiesIfNeeded()
        removeLegacyDiskThumbnailsIfNeeded()
        handleJourneyStoreLoadedState(journeyStore.hasLoaded)
        loadPhotoDiscoveredFromDisk()
    }

    private func handleJourneyStoreLoadedState(_ loaded: Bool) {
        if !loaded {
            hasRebuiltForCurrentLoadedState = false
            return
        }
        guard membershipIndex.entries.isEmpty || !hasRebuiltForCurrentLoadedState else { return }
        hasRebuiltForCurrentLoadedState = true
        rebuildFromJourneyStore()
        let v6Done = FileManager.default.fileExists(atPath: migrationMarkerV6URL.path)
        if v6Done {
            // Most users: V6 already done, only run V7 for changed countries
            migrateJourneyKeysToStrategyV2IfNeeded(fullRekey: false)
        } else {
            // Old users: skip V6, let V7 re-geocode ALL journeys (covers V6 + V7)
            migrateJourneyKeysToStrategyV2IfNeeded(fullRekey: true)
        }
    }
    
    // MARK: - Photo city discovery

    func loadPhotoDiscoveredFromDisk() {
        let url = paths.photoDiscoveredCitiesURL
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CachedCity].self, from: data) else { return }

        let existingKeys = Set(cachedCities.map { $0.id })
        let photoOnly = decoded.filter { !existingKeys.contains($0.id) }
        guard !photoOnly.isEmpty else { return }
        cachedCities.append(contentsOf: photoOnly)
    }

    func loadPreviousPhotoScanResult() -> PhotoScanResult? {
        let url = paths.photoScanResultURL
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(PhotoScanResult.self, from: data) else { return nil }
        // Version mismatch: geocode logic changed, old results are stale.
        // Clear them so the scan button reappears and user can re-scan.
        if result.version != PhotoScanResult.currentVersion {
            cachedCities.removeAll { $0.isPhotoDiscovered == true }
            try? fm.removeItem(at: url)
            try? fm.removeItem(at: paths.photoDiscoveredCitiesURL)
            saveToDisk()
            notifyCitiesChanged()
            return nil
        }
        return result
    }

    func applyPhotoDiscoveredCities(_ discovered: [PhotoDiscoveredCity], scanResult: PhotoScanResult) {
        let df = DateFormatter()
        df.dateFormat = "yyyy.MM"

        let photoCities = discovered.map { d -> CachedCity in
            var dateRange: String?
            if let earliest = d.earliestDate, let latest = d.latestDate {
                let e = df.string(from: earliest)
                let l = df.string(from: latest)
                dateRange = e == l ? e : "\(e) - \(l)"
            }
            // Convert availableLevelNames keys if present (already String:String from PhotoDiscoveredCity)
            let levelNamesEN: [String: String]? = d.availableLevelNames
            return CachedCity(
                id: d.cityKey,
                cityKey: d.cityKey,
                name: d.cityName,
                canonicalNameEN: d.cityName,
                countryISO2: d.countryISO2,
                journeyIds: [],
                explorations: 0,
                memories: 0,
                boundary: nil,
                anchor: d.anchor,
                thumbnailBasePath: nil,
                thumbnailRoutePath: nil,
                parentScopeKey: d.parentScopeKey,
                identityLevelRaw: d.identityLevelRaw,
                availableLevelNamesEN: levelNamesEN,
                isTemporary: false,
                isPhotoDiscovered: true,
                photoCount: d.photoCount,
                photoDateRange: dateRange
            )
        }

        // Persist photo-discovered cities to separate file
        if let data = try? JSONEncoder().encode(photoCities) {
            try? data.write(to: paths.photoDiscoveredCitiesURL, options: .atomic)
        }

        // Persist scan result (for incremental scans)
        if let data = try? JSONEncoder().encode(scanResult) {
            try? data.write(to: paths.photoScanResultURL, options: .atomic)
        }

        // Merge into cachedCities: upsert photo-discovered in place, never touching journey cities.
        let journeyKeys = Set(cachedCities
            .filter { !($0.isTemporary ?? false) && $0.isPhotoDiscovered != true }
            .map { $0.id })
        let incoming = photoCities.filter { !journeyKeys.contains($0.id) }
        let incomingKeys = Set(incoming.map { $0.id })

        // Remove stale photo cities that are no longer in the scan result
        cachedCities.removeAll { $0.isPhotoDiscovered == true && !incomingKeys.contains($0.id) }

        // Upsert: update existing in place, append new
        for city in incoming {
            if let idx = cachedCities.firstIndex(where: { $0.id == city.id && $0.isPhotoDiscovered == true }) {
                cachedCities[idx] = city
            } else {
                cachedCities.append(city)
            }
        }
        saveToDisk()
        notifyCitiesChanged()
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

    /// V6 migration: re-geocode all completed journeys and re-key them using
    /// automatic `decideLevel` rules (no user preference). Runs once in background.
    private func migrateJourneyKeysToAutoLevelIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: migrationMarkerV6URL.path) else { return }

        let journeys = journeyStore.journeys.filter { $0.isCompleted }
        guard !journeys.isEmpty else {
            try? Data("ok".utf8).write(to: migrationMarkerV6URL, options: .atomic)
            return
        }

        let markerURL = migrationMarkerV6URL
        let fixedLocale = Locale(identifier: "en_US")

        Task.detached(priority: .utility) { [weak self] in
            var updatedJourneys: [(id: String, newKey: String, newName: String, iso2: String?)] = []

            // Process journeys sequentially with rate limiting to avoid geocoder throttle
            for journey in journeys {
                guard let startCoord = journey.coordinates.first?.cl,
                      CLLocationCoordinate2DIsValid(startCoord) else { continue }

                let currentKey = journey.stableCityKey ?? ""
                guard !currentKey.isEmpty else { continue }

                let location = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
                let result: (key: String, name: String, iso2: String?)? = await withCheckedContinuation { cont in
                    CLGeocoder().reverseGeocodeLocation(location, preferredLocale: fixedLocale) { placemarks, error in
                        guard let pm = placemarks?.first, error == nil else {
                            cont.resume(returning: nil)
                            return
                        }
                        let canonical = CityPlacemarkResolver.resolveCanonical(from: pm)
                        cont.resume(returning: (canonical.cityKey, canonical.city, canonical.iso2))
                    }
                }

                guard let result else {
                    // Geocode failed — skip this journey, will retry next launch
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }

                let newKey = result.key.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newKey.isEmpty, newKey != currentKey {
                    updatedJourneys.append((id: journey.id, newKey: newKey, newName: result.name, iso2: result.iso2))
                }

                // Rate limit: 1.5s between geocode requests
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }

            await MainActor.run {
                guard let self else { return }

                if !updatedJourneys.isEmpty {
                    for update in updatedJourneys {
                        guard var journey = self.journeyStore.journeys.first(where: { $0.id == update.id }) else { continue }
                        journey.startCityKey = update.newKey
                        journey.cityKey = update.newKey
                        journey.canonicalCity = CityPlacemarkResolver.stableCityName(from: update.newKey, fallback: update.newName)
                        if let iso2 = update.iso2 {
                            journey.countryISO2 = iso2
                        }
                        self.journeyStore.upsertSnapshotThrottled(journey, coordCount: journey.coordinates.count)
                    }
                    self.journeyStore.flushPersist()
                    self.rebuildFromJourneyStore()
                }

                try? Data("ok".utf8).write(to: markerURL, options: .atomic)
            }
        }
    }

    /// V7 migration: strategy v2 rekey — JP/TH now use admin (not locality),
    /// expanded country/subAdmin lists. Re-geocodes journeys whose city key
    /// level doesn't match the new strategy.
    /// When `fullRekey` is true (V6 not yet done), re-geocodes ALL journeys
    /// to also cover V6's work in a single pass.
    private func migrateJourneyKeysToStrategyV2IfNeeded(fullRekey: Bool) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: migrationMarkerV7URL.path) else { return }

        let journeys = journeyStore.journeys.filter { $0.isCompleted }
        guard !journeys.isEmpty else {
            try? Data("ok".utf8).write(to: migrationMarkerV7URL, options: .atomic)
            if fullRekey { try? Data("ok".utf8).write(to: migrationMarkerV6URL, options: .atomic) }
            return
        }

        let needsRekey: [JourneyRoute]
        if fullRekey {
            // Full rekey: re-geocode all completed journeys (covers V6 + V7)
            needsRekey = journeys
        } else {
            // Incremental: only re-geocode journeys in countries whose strategy changed
            let changedISOs: Set<String> = [
                "JP", "TH",
                "AI", "AS", "AW", "BL", "BM", "BQ", "BS", "CK", "CW", "CX",
                "DM", "FK", "FM", "GD", "GG", "GI", "GP", "GQ", "GU",
                "IM", "JE", "KI", "KM", "KN", "KY", "LC",
                "MF", "MH", "MP", "MQ", "MS", "NR", "NU",
                "PF", "PM", "PW", "RE", "SH", "SX", "ST",
                "TC", "TK", "TO", "TV", "VG", "VI", "VU", "WF", "WS", "YT",
                "AF", "BD", "GE", "MN", "PG", "TM",
                "DE", "GR", "PL", "PT", "FI", "IE", "HR", "SK", "RS", "BA", "LT",
            ]
            needsRekey = journeys.filter { j in
                guard let iso2 = j.countryISO2?.uppercased(), changedISOs.contains(iso2) else { return false }
                return true
            }
        }

        guard !needsRekey.isEmpty else {
            try? Data("ok".utf8).write(to: migrationMarkerV7URL, options: .atomic)
            if fullRekey { try? Data("ok".utf8).write(to: migrationMarkerV6URL, options: .atomic) }
            return
        }

        let markerV7URL = migrationMarkerV7URL
        let markerV6URL = fullRekey ? migrationMarkerV6URL : nil
        let fixedLocale = Locale(identifier: "en_US")

        Task.detached(priority: .utility) { [weak self] in
            var updatedJourneys: [(id: String, newKey: String, newName: String, iso2: String?)] = []

            for journey in needsRekey {
                guard let startCoord = journey.coordinates.first?.cl,
                      CLLocationCoordinate2DIsValid(startCoord) else { continue }

                let currentKey = journey.stableCityKey ?? ""
                guard !currentKey.isEmpty else { continue }

                // Wait for network + throttle
                if !ReverseGeocodeService.shared.isNetworkAvailable {
                    let recovered = await ReverseGeocodeService.shared.waitForNetwork(timeout: 30)
                    if !recovered { break } // No network — stop, will retry next launch
                }

                let location = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
                let result: (key: String, name: String, iso2: String?)? = await withCheckedContinuation { cont in
                    CLGeocoder().reverseGeocodeLocation(location, preferredLocale: fixedLocale) { placemarks, error in
                        guard let pm = placemarks?.first, error == nil else {
                            cont.resume(returning: nil)
                            return
                        }
                        let canonical = CityPlacemarkResolver.resolveCanonical(from: pm)
                        cont.resume(returning: (canonical.cityKey, canonical.city, canonical.iso2))
                    }
                }

                guard let result else {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }

                let newKey = result.key.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newKey.isEmpty, newKey != currentKey {
                    updatedJourneys.append((id: journey.id, newKey: newKey, newName: result.name, iso2: result.iso2))
                }

                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }

            await MainActor.run {
                guard let self else { return }

                if !updatedJourneys.isEmpty {
                    for update in updatedJourneys {
                        guard var journey = self.journeyStore.journeys.first(where: { $0.id == update.id }) else { continue }
                        journey.startCityKey = update.newKey
                        journey.cityKey = update.newKey
                        journey.canonicalCity = CityPlacemarkResolver.stableCityName(from: update.newKey, fallback: update.newName)
                        if let iso2 = update.iso2 {
                            journey.countryISO2 = iso2
                        }
                        self.journeyStore.upsertSnapshotThrottled(journey, coordCount: journey.coordinates.count)
                    }
                    self.journeyStore.flushPersist()
                    self.rebuildFromJourneyStore()
                }

                try? Data("ok".utf8).write(to: markerV7URL, options: .atomic)
                if let v6URL = markerV6URL {
                    try? Data("ok".utf8).write(to: v6URL, options: .atomic)
                }
            }
        }
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
    private static let thumbnailStyleVersion = 3
    private static let thumbnailStyleVersionKey = "streetstamps.thumbnailStyleVersion"

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
        invalidateThumbnailsIfStyleChanged()
    }

    private func invalidateThumbnailsIfStyleChanged() {
        let stored = UserDefaults.standard.integer(forKey: Self.thumbnailStyleVersionKey)
        guard stored < Self.thumbnailStyleVersion else { return }
        for i in cachedCities.indices {
            cachedCities[i].thumbnailRoutePath = nil
        }
        saveToDisk()
        UserDefaults.standard.set(Self.thumbnailStyleVersion, forKey: Self.thumbnailStyleVersionKey)
    }

    private func loadMembershipIndexFromDisk() {
        do {
            let data = try Data(contentsOf: membershipIndexURL)
            membershipIndex = try JSONDecoder().decode(CityMembershipIndex.self, from: data)
        } catch {
            membershipIndex = CityMembershipIndex()
        }
    }

    /// Schedules a coalesced background save. Multiple rapid calls collapse
    /// into one encode+write cycle, keeping the main thread free.
    fileprivate func saveToDisk() {
        savePending = true
        guard !saveScheduled else { return }
        saveScheduled = true

        // Snapshot on next run-loop tick so back-to-back mutations coalesce.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.savePending else {
                self?.saveScheduled = false
                return
            }
            self.savePending = false
            self.saveScheduled = false

            let snapshot = self.cachedCities
            let url = self.fileURL
            self.diskQueue.async {
                do {
                    let data = try JSONEncoder().encode(snapshot)
                    try data.write(to: url, options: [.atomic])
                } catch {
                    print("❌ city cache save failed:", error)
                }
            }
        }
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
        let isPhoto = cachedCities[idx].isPhotoDiscovered == true
        let journeyIDs = cachedCities[idx].journeyIds

        if !journeyIDs.isEmpty {
            journeyStore.discardJourneys(ids: journeyIDs)
            rebuildFromJourneyStore()
            // Photo-discovered city that also has journeys — still purge from
            // the separate photo file so it won't resurrect on next load.
            if isPhoto { removeFromPhotoDiscoveredFile(id: id) }
            return
        }

        cachedCities.remove(at: idx)
        saveToDisk()
        notifyCitiesChanged()
        if isPhoto { removeFromPhotoDiscoveredFile(id: id) }
    }

    /// Remove a single city from the persisted photo-discovered cities file
    /// and the scan result, so it does not reappear on next
    /// `loadPhotoDiscoveredFromDisk()` or after a subsequent photo scan.
    private func removeFromPhotoDiscoveredFile(id: String) {
        // 1. Remove from the photo-discovered cities list
        let citiesURL = paths.photoDiscoveredCitiesURL
        if fm.fileExists(atPath: citiesURL.path),
           let data = try? Data(contentsOf: citiesURL),
           var decoded = try? JSONDecoder().decode([CachedCity].self, from: data) {
            let before = decoded.count
            decoded.removeAll { $0.id == id }
            if decoded.count != before {
                if decoded.isEmpty {
                    try? fm.removeItem(at: citiesURL)
                } else if let updated = try? JSONEncoder().encode(decoded) {
                    try? updated.write(to: citiesURL, options: .atomic)
                }
            }
        }

        // 2. Remove from the scan result so a future scan won't carry it forward
        let scanURL = paths.photoScanResultURL
        if fm.fileExists(atPath: scanURL.path),
           let data = try? Data(contentsOf: scanURL),
           var result = try? JSONDecoder().decode(PhotoScanResult.self, from: data) {
            let before = result.cities.count
            result.cities.removeAll { $0.cityKey == id }
            if result.cities.count != before,
               let updated = try? JSONEncoder().encode(result) {
                try? updated.write(to: scanURL, options: .atomic)
            }
        }
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
        let movedMemoriesByID = Dictionary(movedJourneys.map { ($0.id, $0.memories.count) }, uniquingKeysWith: { _, latest in latest })

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
                parentScopeKey: cachedCities[targetIdx].parentScopeKey,
                availableLevelNamesEN: cachedCities[targetIdx].availableLevelNamesEN,
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
        anchor: CLLocationCoordinate2D?
    ) {
        guard let idx = cachedCities.firstIndex(where: { $0.id == cityKey }) else { return }

        if let parentRegionKey, !parentRegionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cachedCities[idx].parentScopeKey = parentRegionKey
        }
        if let level {
            cachedCities[idx].identityLevelRaw = level.rawValue
        }
        if let availableLevels {
            let mapped = Dictionary(availableLevels.map { ($0.key.rawValue, $0.value) }, uniquingKeysWith: { _, latest in latest })
            cachedCities[idx].availableLevelNamesEN = mapped
        }
        if let anchor, anchor.isValid, cachedCities[idx].anchor == nil {
            cachedCities[idx].anchor = LatLon(anchor)
        }

        saveToDisk()
        notifyCitiesChanged()
    }

    func rebuildFromJourneyStore() {
        guard journeyStore.hasLoaded else { return }
        let journeysSnapshot = journeyStore.journeys
        let membershipURL = membershipIndexURL
        // Capture revision before background work. If it changes while we're
        // computing, a newer mutation has occurred and our result is stale.
        let revisionAtStart = journeyStore.trackTileRevision

        Task.detached(priority: .userInitiated) { [weak self] in
            let index = CityCache.buildMembershipIndex(from: journeysSnapshot)
            let indexData = try? JSONEncoder().encode(index)

            await MainActor.run {
                guard let self else { return }
                // Guard: if journeyStore changed since we started, discard stale result.
                // The newer mutation will have already triggered its own rebuild or
                // applyJourneyMutation path.
                guard self.journeyStore.trackTileRevision == revisionAtStart else { return }
                self.membershipIndex = index
                if let indexData {
                    try? indexData.write(to: membershipURL, options: [.atomic])
                }
                self.replaceCachedCitiesFromMembershipIndex()
            }
        }
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

    private nonisolated static func buildMembershipIndex(from journeys: [JourneyRoute]) -> CityMembershipIndex {
        var index = CityMembershipIndex()
        for journey in journeys where journey.isCompleted {
            index.applyJourneyMutation(oldJourney: nil, newJourney: journey)
        }
        return index
    }

    private func replaceCachedCitiesFromMembershipIndex() {
        let stableExistingByKey: [String: CachedCity] = cachedCities
            .filter { !($0.isTemporary ?? false) && $0.isPhotoDiscovered != true }
            .reduce(into: [:]) { acc, city in acc[city.id] = city }

        let rebuilt = membershipIndex.entries.values.map { entry in
            makeCachedCity(from: entry, previous: stableExistingByKey[entry.cityKey], preferredAnchorJourney: nil)
        }

        let temps = cachedCities.filter { $0.isTemporary ?? false }
        let sortedStable = sortStableCities(rebuilt)

        // Preserve photo-discovered cities that don't overlap with journey-derived
        let journeyKeys = Set(sortedStable.map { $0.id })
        let photoOnly = cachedCities.filter { $0.isPhotoDiscovered == true && !journeyKeys.contains($0.id) }

        cachedCities = sortedStable + photoOnly + temps
        saveToDisk()
        notifyCitiesChanged()
    }

    private func refreshCachedCities(for cityKeys: Set<String>, preferredAnchorJourney: JourneyRoute?) {
        guard !cityKeys.isEmpty else { return }

        var stableCities = cachedCities.filter { !($0.isTemporary ?? false) && $0.isPhotoDiscovered != true }
        let existingByKey = Dictionary(stableCities.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

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

        // Preserve photo-discovered cities that don't overlap with journey-derived
        let journeyKeys = Set(stableCities.map { $0.id })
        let photoOnly = cachedCities.filter { $0.isPhotoDiscovered == true && !journeyKeys.contains($0.id) }

        cachedCities = sortStableCities(stableCities) + photoOnly + temps
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
            parentScopeKey: previous?.parentScopeKey,
            identityLevelRaw: previous?.identityLevelRaw,
            availableLevelNamesEN: previous?.availableLevelNamesEN,
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
                let fallbackName = CityDisplayResolver.title(
                    for: fallbackKey,
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
        let fallbackName = CityDisplayResolver.title(
            for: fallbackKey,
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
            title: c.displayTitle,
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
            anchor: reserveAnchor
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
    // MARK: - Province-to-city redirect
    // ===================================================

    /// When geocode returns a province-level key (e.g. "Jiangsu|CN" because locality
    /// was nil), check if we already have a city card whose parentScopeKey matches.
    /// If so, redirect the journey to that existing city.
    /// When multiple cities share the same parent (Suzhou & Nanjing both in Jiangsu),
    /// pick the one whose anchor is closest to the journey's start coordinate.
    private func resolveProvinceToCityRedirect(
        key: String,
        journeyAnchor: CLLocationCoordinate2D?
    ) -> (key: String, name: String)? {
        // Only redirect if the key doesn't already exist as a real city card.
        // If "Jiangsu|CN" already has its own card with journeys, don't redirect.
        if cachedCities.contains(where: { $0.id == key && !($0.isTemporary ?? false) }) {
            return nil
        }

        let candidates = cachedCities.filter {
            !($0.isTemporary ?? false)
            && $0.parentScopeKey == key
        }
        guard !candidates.isEmpty else { return nil }

        // Single candidate — no ambiguity
        if candidates.count == 1, let c = candidates.first {
            return (key: c.id, name: c.englishName)
        }

        // Multiple candidates — pick closest to journey anchor
        guard let anchor = journeyAnchor, CLLocationCoordinate2DIsValid(anchor) else {
            // No anchor to compare; pick the one with most journeys
            let best = candidates.max(by: { $0.journeyIds.count < $1.journeyIds.count })!
            return (key: best.id, name: best.englishName)
        }

        let anchorLoc = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        let closest = candidates.min(by: { a, b in
            let aDist = a.anchor.map { CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: anchorLoc) } ?? .greatestFiniteMagnitude
            let bDist = b.anchor.map { CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: anchorLoc) } ?? .greatestFiniteMagnitude
            return aDist < bDist
        })!
        return (key: closest.id, name: closest.englishName)
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

            let (boundary, anchor, journeyCoords) = await MainActor.run { () -> ([CLLocationCoordinate2D]?, CLLocationCoordinate2D?, [[CLLocationCoordinate2D]]) in
                let c = self.cachedCities.first(where: { $0.id == cityKey })
                let b = c?.boundary?.map { $0.cl }
                let a = c?.anchor?.cl

                // Only include city-local journeys for thumbnail (not intercity journeys).
                // Coords are kept per-journey so different journeys are never connected
                // by polyline gap-fill — each journey renders as its own independent segments.
                let js = self.journeyStore.journeys.filter {
                    $0.isCompleted &&
                    $0.startCityKey == cityKey &&
                    $0.endCityKey == cityKey
                }
                let perJourney: [[CLLocationCoordinate2D]] = js
                    .map { $0.allCLCoords.filter { $0.isValid } }
                    .filter { !$0.isEmpty }
                return (b, a, perJourney)
            }

            let boundaryForMap = boundary.map { MapCoordAdapter.forMapKit($0, cityKey: cityKey) }
            let anchorForMap = anchor.map { MapCoordAdapter.forMapKit($0, cityKey: cityKey) }

            // Build route segments only if we have route data
            let hasRouteData = !journeyCoords.isEmpty
            let overlaySegments: [RenderRouteSegment]
            let isFlightLike: Bool
            let bboxLike: [CLLocationCoordinate2D]

            if hasRouteData {
                var aggregated: [RenderRouteSegment] = []
                var anyFlightLike = false
                for coords in journeyCoords {
                    let built = RouteRenderingPipeline.buildSegments(
                        .init(coordsWGS84: coords, applyGCJForChina: false, gapDistanceMeters: 2_200, cityKey: cityKey),
                        surface: .mapKit
                    )
                    aggregated.append(contentsOf: built.segments)
                    if built.isFlightLike { anyFlightLike = true }
                }
                overlaySegments = aggregated
                isFlightLike = anyFlightLike
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
            title: c.displayTitle,
            subtitle: c.countryISO2,
            baseThumbPath: nil,
            routeThumbPath: nil
        )
    }

    // MARK: - Identity data repair (one-time migration)

    private static let identityRepairKey = "cityCache.identityRepairV10.done"

    /// Re-geocode ALL non-temporary cities with en_US to ensure identity fields are correct.
    /// Runs once per device. Fixes: wrong canonicalNameEN, missing identityLevelRaw,
    /// missing availableLevelNamesEN, missing parentScopeKey.
    func repairAllCityIdentityData() {
        let alreadyDone = UserDefaults.standard.bool(forKey: Self.identityRepairKey)
        #if DEBUG
        print("🔧 [Repair] called. alreadyDone=\(alreadyDone) cities=\(cachedCities.count) journeys=\(journeyStore.journeys.count) hasLoaded=\(journeyStore.hasLoaded)")
        #endif
        guard !alreadyDone else { return }
        // Don't run until journeys are loaded — we need journey coordinates as fallback for cities without anchor
        guard journeyStore.hasLoaded else { return }

        // Collect coordinate for each city: prefer anchor, fallback to first journey start coord
        let journeysById = Dictionary(
            journeyStore.journeys.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        // Collect by cityKey (not index) to avoid stale-index bugs during async repair
        var citiesToRepair: [(String, LatLon)] = []
        var skippedNoCoord = 0
        for city in cachedCities {
            guard !(city.isTemporary ?? false), !(city.isPhotoDiscovered ?? false) else { continue }
            if let anchor = city.anchor {
                citiesToRepair.append((city.cityKey, anchor))
                continue
            }
            var found = false
            for jid in city.journeyIds {
                if let j = journeysById[jid], let first = j.coordinates.first {
                    citiesToRepair.append((city.cityKey, LatLon(CLLocationCoordinate2D(latitude: first.lat, longitude: first.lon))))
                    found = true
                    break
                }
            }
            if !found { skippedNoCoord += 1 }
        }

        #if DEBUG
        print("🔧 [Repair] citiesToRepair=\(citiesToRepair.count) skippedNoCoord=\(skippedNoCoord) (from \(cachedCities.filter { !($0.isTemporary ?? false) && !($0.isPhotoDiscovered ?? false) }.count) non-temp cities)")
        #endif

        guard !citiesToRepair.isEmpty else {
            // Only mark done if nothing was skipped — skipped cities need retry next launch
            if skippedNoCoord == 0 {
                UserDefaults.standard.set(true, forKey: Self.identityRepairKey)
            }
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            var geocodeFailedCount = 0
            var reKeyedCityKeys = Set<String>()  // old keys that changed during repair
            for (cityKey, anchor) in citiesToRepair {
                let location = CLLocation(latitude: anchor.lat, longitude: anchor.lon)
                var result: ReverseGeocodeService.CanonicalResult?
                for _ in 0..<3 {
                    result = await ReverseGeocodeService.shared.canonicalWithRetry(for: location, maxAttempts: 2)
                    if result != nil { break }
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                }

                guard let r = result else {
                    geocodeFailedCount += 1
                    continue
                }

                await MainActor.run {
                    guard let self else { return }
                    // Find by cityKey at write time — array may have shifted
                    guard let idx = self.cachedCities.firstIndex(where: { $0.cityKey == cityKey }) else { return }
                    let city = self.cachedCities[idx]

                    let newKey = r.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    let oldKey = city.cityKey
                    #if DEBUG
                    print("🔧 [Repair] old=\(oldKey) new=\(newKey) level=\(r.level.rawValue)")
                    #endif

                    let mapped = Dictionary(
                        r.availableLevels.map { ($0.key.rawValue, $0.value) },
                        uniquingKeysWith: { _, latest in latest }
                    )
                    let cityName = newKey.components(separatedBy: "|").first?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? r.cityName

                    // Re-key: use geocode's canonical key as the new id/cityKey
                    self.cachedCities[idx] = CachedCity(
                        id: newKey,
                        cityKey: newKey,
                        name: cityName,
                        canonicalNameEN: cityName,
                        countryISO2: r.iso2 ?? city.countryISO2,
                        journeyIds: city.journeyIds,
                        explorations: city.explorations,
                        memories: city.memories,
                        boundary: city.boundary,
                        anchor: city.anchor,
                        thumbnailBasePath: city.thumbnailBasePath,
                        thumbnailRoutePath: city.thumbnailRoutePath,
                        parentScopeKey: r.parentRegionKey ?? city.parentScopeKey,
                        identityLevelRaw: r.level.rawValue,
                        availableLevelNamesEN: mapped,
                        isTemporary: city.isTemporary,
                        isPhotoDiscovered: city.isPhotoDiscovered,
                        photoCount: city.photoCount,
                        photoDateRange: city.photoDateRange
                    )

                    // Update journeys that reference the old key
                    if oldKey != newKey {
                        reKeyedCityKeys.insert(oldKey)
                        reKeyedCityKeys.insert(newKey)
                        for j in self.journeyStore.journeys {
                            if j.startCityKey == oldKey || j.cityKey == oldKey {
                                var updated = j
                                if updated.startCityKey == oldKey { updated.startCityKey = newKey }
                                if updated.cityKey == oldKey { updated.cityKey = newKey }
                                self.journeyStore.upsertSnapshotThrottled(updated, coordCount: updated.coordinates.count)
                            }
                        }
                    }
                }
            }

            await MainActor.run { [skippedNoCoord, geocodeFailedCount] in
                guard let self else { return }
                // Merge duplicates: re-keying may map multiple old cities to the same canonical key.
                // Instead of discarding, merge journeyIds/explorations/memories and keep best metadata.
                var merged: [String: CachedCity] = [:]
                for city in self.cachedCities {
                    if var existing = merged[city.id] {
                        let combinedJourneyIds = Array(Set(existing.journeyIds + city.journeyIds))
                        existing = CachedCity(
                            id: existing.id,
                            cityKey: existing.cityKey,
                            name: existing.name,
                            canonicalNameEN: existing.canonicalNameEN,
                            countryISO2: existing.countryISO2 ?? city.countryISO2,
                            journeyIds: combinedJourneyIds,
                            explorations: existing.explorations + city.explorations,
                            memories: existing.memories + city.memories,
                            boundary: existing.boundary ?? city.boundary,
                            anchor: existing.anchor ?? city.anchor,
                            thumbnailBasePath: existing.thumbnailBasePath ?? city.thumbnailBasePath,
                            thumbnailRoutePath: existing.thumbnailRoutePath ?? city.thumbnailRoutePath,
                            parentScopeKey: existing.parentScopeKey ?? city.parentScopeKey,
                            identityLevelRaw: existing.identityLevelRaw ?? city.identityLevelRaw,
                            availableLevelNamesEN: existing.availableLevelNamesEN ?? city.availableLevelNamesEN,
                            isTemporary: existing.isTemporary,
                            isPhotoDiscovered: existing.isPhotoDiscovered,
                            photoCount: existing.photoCount,
                            photoDateRange: existing.photoDateRange
                        )
                        merged[city.id] = existing
                    } else {
                        merged[city.id] = city
                    }
                }
                self.cachedCities = self.cachedCities.compactMap { merged.removeValue(forKey: $0.id) }

                // Only flush translations for cities whose keys actually changed.
                // Preserves valid cached translations for unchanged cities, avoiding
                // a full re-geocode that can fail under VPN/throttle conditions.
                if reKeyedCityKeys.isEmpty {
                    // No re-keying happened — translations are all still valid
                } else {
                    CityNameTranslationCache.shared.clearKeys(reKeyedCityKeys)
                }
                self.saveToDisk()
                self.notifyCitiesChanged()
                // Only mark done if ALL cities were successfully repaired
                if skippedNoCoord == 0 && geocodeFailedCount == 0 {
                    UserDefaults.standard.set(true, forKey: Self.identityRepairKey)
                }
                #if DEBUG
                print("✅ [CityCache] Identity repair completed for \(citiesToRepair.count) cities, skippedNoCoord=\(skippedNoCoord), geocodeFailed=\(geocodeFailedCount)")
                #endif
            }
        }
    }
}

// MARK: - small helper
private extension Double {
    func rounded(to places: Int) -> Double {
        guard places >= 0 else { return self }
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }}
