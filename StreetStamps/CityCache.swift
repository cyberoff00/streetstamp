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
    let id: String                 // canonical: "name|ISO2" or temp: "__TMP__|journeyId"
    let name: String
    let countryISO2: String?

    var journeyIds: [String]
    var explorations: Int
    var memories: Int

    var boundary: [LatLon]?
    var anchor: LatLon?

    var thumbnailBasePath: String?
    var thumbnailRoutePath: String?

    // Reserved from the city's first journey start (for city-level picker display stability).
    var reservedLevelRaw: String? = nil
    var reservedParentRegionKey: String? = nil
    var reservedAvailableLevelNames: [String: String]? = nil

    var isTemporary: Bool? = false
}


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
    private unowned let journeyStore: JourneyStore
    private var thumbnails: CityThumbnailCache
    private var migrationMarkerV2URL: URL
    private var migrationMarkerV3URL: URL
    private var migrationMarkerV4URL: URL
    private var paths: StoragePath
    private var cancellables: Set<AnyCancellable> = []

    init(paths: StoragePath, journeyStore: JourneyStore) {
        self.fileURL = paths.cityCacheURL
        self.journeyStore = journeyStore
        self.thumbnails = CityThumbnailCache(dir: paths.thumbnailsDir)
        self.migrationMarkerV2URL = paths.migrationMarkerV2_thumbnailPaths
        self.migrationMarkerV3URL = paths.migrationMarkerV3_intercityToStartingCity
        self.migrationMarkerV4URL = paths.migrationMarkerV4_removeLegacyThumbnails
        self.paths = paths
        loadFromDisk()

        // Migrate thumbnail paths from absolute to relative (V2 migration)
        migrateThumbnailPathsIfNeeded()

        // Migrate intercity routes to starting cities (V3 migration)
        migrateInterCityRoutesToStartingCitiesIfNeeded()
        removeLegacyDiskThumbnailsIfNeeded()
        rebuildFromJourneyStore()

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
        self.thumbnails = CityThumbnailCache(dir: paths.thumbnailsDir)
        self.migrationMarkerV2URL = paths.migrationMarkerV2_thumbnailPaths
        self.migrationMarkerV3URL = paths.migrationMarkerV3_intercityToStartingCity
        self.migrationMarkerV4URL = paths.migrationMarkerV4_removeLegacyThumbnails

        loadFromDisk()
        migrateThumbnailPathsIfNeeded()
        migrateInterCityRoutesToStartingCitiesIfNeeded()
        removeLegacyDiskThumbnailsIfNeeded()
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

    // MARK: disk
    func loadFromDisk() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([CachedCity].self, from: data)
            self.cachedCities = decoded
        } catch {
            self.cachedCities = []
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
                name: targetCityName,
                countryISO2: normalizedISO ?? cachedCities[targetIdx].countryISO2,
                journeyIds: cachedCities[targetIdx].journeyIds,
                explorations: cachedCities[targetIdx].explorations,
                memories: cachedCities[targetIdx].memories,
                boundary: cachedCities[targetIdx].boundary,
                anchor: cachedCities[targetIdx].anchor ?? anchor.map(LatLon.init) ?? sourceAnchor,
                thumbnailBasePath: cachedCities[targetIdx].thumbnailBasePath,
                thumbnailRoutePath: cachedCities[targetIdx].thumbnailRoutePath,
                reservedLevelRaw: cachedCities[targetIdx].reservedLevelRaw,
                reservedParentRegionKey: cachedCities[targetIdx].reservedParentRegionKey,
                reservedAvailableLevelNames: cachedCities[targetIdx].reservedAvailableLevelNames,
                isTemporary: cachedCities[targetIdx].isTemporary
            )
        } else {
            let created = CachedCity(
                id: targetCityKey,
                name: targetCityName,
                countryISO2: normalizedISO,
                journeyIds: movedIDs,
                explorations: movedIDs.count,
                memories: movedJourneys.reduce(0) { $0 + $1.memories.count },
                boundary: sourceBoundary,
                anchor: anchor.map(LatLon.init) ?? sourceAnchor,
                thumbnailBasePath: nil,
                thumbnailRoutePath: nil,
                reservedLevelRaw: nil,
                reservedParentRegionKey: nil,
                reservedAvailableLevelNames: nil,
                isTemporary: false
            )
            cachedCities.append(created)
        }

        saveToDisk()
        notifyCitiesChanged()
    }

    @MainActor
    func updateCityLevelReserveProfile(
        cityKey: String,
        level: CityPlacemarkResolver.CardLevel?,
        parentRegionKey: String?,
        availableLevels: [CityPlacemarkResolver.CardLevel: String]?,
        anchor: CLLocationCoordinate2D?,
        force: Bool
    ) {
        guard let idx = cachedCities.firstIndex(where: { $0.id == cityKey }) else { return }
        if !force, cachedCities[idx].reservedLevelRaw != nil { return }

        if let level, cachedCities[idx].reservedLevelRaw == nil {
            cachedCities[idx].reservedLevelRaw = level.rawValue
        }
        if let parentRegionKey, !parentRegionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cachedCities[idx].reservedParentRegionKey = parentRegionKey
        }
        if let availableLevels {
            let mapped = Dictionary(uniqueKeysWithValues: availableLevels.map { ($0.key.rawValue, $0.value) })
            cachedCities[idx].reservedAvailableLevelNames = mapped
        }
        if let anchor, anchor.isValid, cachedCities[idx].anchor == nil {
            cachedCities[idx].anchor = LatLon(anchor)
        }

        saveToDisk()
        notifyCitiesChanged()
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

        let completed = journeyStore.journeys.filter { $0.isCompleted }
        let existingByKey = Dictionary(uniqueKeysWithValues: cachedCities.map { ($0.id, $0) })

        var grouped: [String: [JourneyRoute]] = [:]
        for j in completed {
            let keyRaw = (j.startCityKey ?? j.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = keyRaw.isEmpty ? j.canonicalCityKeyFallback : keyRaw
            grouped[key, default: []].append(j)
        }

        var rebuilt: [CachedCity] = []
        rebuilt.reserveCapacity(grouped.count)

        for (key, js) in grouped {
            let sortedByStart = js.sorted {
                ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture)
            }
            let old = existingByKey[key]
            let first = sortedByStart.first
            let nameCandidate = (first?.canonicalCity ?? first?.cityName ?? first?.displayCityName ?? old?.name ?? L10n.t("unknown"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = nameCandidate.isEmpty ? (old?.name ?? L10n.t("unknown")) : nameCandidate

            let isoCandidate = (first?.countryISO2 ?? old?.countryISO2 ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let iso = isoCandidate.isEmpty ? nil : isoCandidate

            let anchorCoord = first?.startCoordinate?.isValid == true ? first?.startCoordinate : old?.anchor?.cl
            let anchor = anchorCoord.map(LatLon.init)

            rebuilt.append(
                CachedCity(
                    id: key,
                    name: name,
                    countryISO2: iso,
                    journeyIds: sortedByStart.map(\.id),
                    explorations: sortedByStart.count,
                    memories: sortedByStart.reduce(0) { $0 + $1.memoryCount },
                    boundary: old?.boundary,
                    anchor: anchor,
                    thumbnailBasePath: old?.thumbnailBasePath,
                    thumbnailRoutePath: old?.thumbnailRoutePath,
                    reservedLevelRaw: old?.reservedLevelRaw,
                    reservedParentRegionKey: old?.reservedParentRegionKey,
                    reservedAvailableLevelNames: old?.reservedAvailableLevelNames,
                    isTemporary: false
                )
            )
        }

        let temps = cachedCities.filter { $0.isTemporary ?? false }
        rebuilt.sort {
            if $0.explorations != $1.explorations { return $0.explorations > $1.explorations }
            return $0.name < $1.name
        }

        cachedCities = rebuilt + temps
        saveToDisk()
        notifyCitiesChanged()
    }

    // ===================================================
    // MARK: - Public APIs
    // ===================================================

    /// 完成旅程：TEMP -> canonical + route thumb
    ///
    /// ✅ canonicalKey is derived from FIXED-locale reverse-geocode using journey START coordinate
    /// ✅ All journeys belong to their starting city (intercity concept removed)
    /// ✅ if geocode fails, fallback to Journey fields
    @discardableResult
    func onJourneyCompleted(_ journey: JourneyRoute) -> CityEvent? {
        guard journey.isCompleted else { return nil }

        // Use START coordinate to determine city card (all journeys belong to starting city)
        if let start = journey.allCLCoords.first {
            let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)

            reverseGeocodeCity(startLoc) { [weak self] result in
                guard let self else { return }

                if let r = result {
                    _ = self.finishCompleteWithCanonical(
                        journey: journey,
                        canonicalKey: r.cityKey,
                        canonicalName: r.cityName,
                        iso: (r.iso2 ?? ""),
                        reserveLevel: r.level,
                        reserveParentRegionKey: r.parentRegionKey,
                        reserveAvailableLevels: r.availableLevels,
                        reserveAnchor: journey.startCoordinate
                    )
                    return
                }

                // fallback (rare) - use startCityKey if available
                let fallbackKey = journey.startCityKey ?? journey.canonicalCityKeyFallback
                let fallbackName = journey.displayCityName
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
        let fallbackKey = journey.startCityKey ?? journey.canonicalCityKeyFallback
        let fallbackName = journey.displayCityName
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
            title: c.name,
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
        reserveAnchor: CLLocationCoordinate2D?
    ) -> CityEvent? {

        let tmpKey = temporaryCityKey(for: journey.id)
        let existedBefore = cachedCities.contains(where: { $0.id == canonicalKey && !($0.isTemporary ?? false) })

        mergeTemporaryCityIfNeeded(
            tmpKey: tmpKey,
            canonicalKey: canonicalKey,
            canonicalName: canonicalName,
            iso: iso
        )

        refreshCityFromStore(cityKey: canonicalKey)
        updateCityLevelReserveProfile(
            cityKey: canonicalKey,
            level: reserveLevel,
            parentRegionKey: reserveParentRegionKey,
            availableLevels: reserveAvailableLevels,
            anchor: reserveAnchor,
            force: false
        )
        generateRouteThumbnail(cityKey: canonicalKey)
        setPendingUnlockIfNeeded(cityKey: canonicalKey)

        let event: CityEvent = existedBefore
            ? .updatedCity(cityKey: canonicalKey)
            : .addedNewCity(cityKey: canonicalKey, name: canonicalName)

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

    private struct GeocodeResult {
        let cityName: String
        let iso2: String?
        let cityKey: String
        let level: CityPlacemarkResolver.CardLevel
        let parentRegionKey: String?
        let availableLevels: [CityPlacemarkResolver.CardLevel: String]
    }



    private func reverseGeocodeCity(_ location: CLLocation, completion: @escaping (GeocodeResult?) -> Void) {
        // ✅ cancel stale callbacks (but do NOT spam system geocoder)
        geocodeTask?.cancel()

        geocodeTask = Task {
            let result = await ReverseGeocodeService.shared.canonical(for: location)
            if Task.isCancelled { return }

            await MainActor.run {
                guard let result else { completion(nil); return }
                completion(.init(
                    cityName: result.cityName,
                    iso2: result.iso2,
                    cityKey: result.cityKey,
                    level: result.level,
                    parentRegionKey: result.parentRegionKey,
                    availableLevels: result.availableLevels
                ))
            }
        }
    }


    // ===================================================
    // MARK: - Unlock logic
    // ===================================================

    private func setPendingUnlockIfNeeded(cityKey: String) {
        guard let c = cachedCities.first(where: { $0.id == cityKey && !($0.isTemporary ?? false) }) else { return }
        guard c.explorations == 1 else { return }

        pendingUnlock = UnlockedPayload(
            id: c.id,
            kind: .city,
            title: c.name,
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
