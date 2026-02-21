//
//  DataMigrator.swift
//  StreetStamps
//
//  Created by Claire Yang on 21/01/2026.
//

import Foundation

// MARK: - Legacy InterCity Route Model (for migration only)

/// Legacy model for intercity routes that were stored separately.
/// This is only used during V3 migration to read old data from users upgrading from older versions.
/// Once all users have migrated, this struct can be safely removed in a future version.
/// The migration is controlled by a marker file (migrationMarkerV3URL) that prevents re-running.
struct CachedInterCityRoute: Codable {
    let id: String
    let name: String
    let fromName: String
    let toName: String
    var fromCoordinate: CoordinateCodable?
    var toCoordinate: CoordinateCodable?
    var previewCoordinates: [CoordinateCodable]?
    var previewMemories: [JourneyMemory]?
    var journeyId: String
    var distance: Double
    var memories: Int
    var thumbnailRoutePath: String?
    var thumbnailBasePath: String?
}

enum DataMigrator {
    /// Migrate legacy data from Documents into Application Support/StreetStamps/<userID>/...
    /// Runs only once per user (marker file).
    static func migrateLegacyIfNeeded(paths: StoragePath) throws {
        try paths.ensureBaseDirectoriesExist()

        // already migrated
        if FileManager.default.fileExists(atPath: paths.migrationMarkerV1.path) {
            return
        }

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

        // 1) Journeys
        // legacy: Documents/Journeys/<userID>/...
        // new:    AppSupport/StreetStamps/<userID>/Journeys/...
        let legacyJourneysRoot = docs
            .appendingPathComponent("Journeys", isDirectory: true)
            .appendingPathComponent(paths.userID, isDirectory: true)

        // Important: new journeysDir is .../<userID>/Journeys/
        // We want contents of legacy user journeys root -> new journeysDir
        try moveContentsIfExists(from: legacyJourneysRoot, to: paths.journeysDir, fm: fm)

        // 2) City cache json
        let legacyCityCache = docs.appendingPathComponent("city_cache.json", isDirectory: false)
        try moveFileIfExists(from: legacyCityCache, to: paths.cityCacheURL, fm: fm)

        // 3) Route cache json
        let legacyRouteCache = docs.appendingPathComponent("route_cache.json", isDirectory: false)
        try moveFileIfExists(from: legacyRouteCache, to: paths.routeCacheURL, fm: fm)

        // 4) Photos folder
        // legacy: Documents/StreetStampsPhotos
        // new:    AppSupport/.../<userID>/Photos
        let legacyPhotosDir = docs.appendingPathComponent("StreetStampsPhotos", isDirectory: true)
        try moveContentsIfExists(from: legacyPhotosDir, to: paths.photosDir, fm: fm)

        // Write marker (atomic-ish)
        let markerData = Data("migrated_v1".utf8)
        fm.createFile(atPath: paths.migrationMarkerV1.path, contents: markerData)
    }
    
    // MARK: - Intercity Routes to Starting City Migration (V3)

    /// Migrate intercity routes to belong to their starting city's journeyIds array.
    /// This removes the separate intercity route storage and consolidates all journeys
    /// under their starting city.
    ///
    /// Call this after CityCache loads data from disk.
    static func migrateInterCityRoutesToStartingCities(
        routes: [CachedInterCityRoute],
        cities: inout [CachedCity],
        journeys: [JourneyRoute],
        markerURL: URL
    ) -> Bool {
        let fm = FileManager.default

        // Check if already migrated
        if fm.fileExists(atPath: markerURL.path) {
            return false
        }

        guard !routes.isEmpty else {
            // No routes to migrate, but still create marker
            let markerData = Data("migrated_intercity_routes_v3".utf8)
            fm.createFile(atPath: markerURL.path, contents: markerData)
            return false
        }

        var modified = false

        for route in routes {
            // Find the journey by ID
            guard let journey = journeys.first(where: { $0.id == route.journeyId }) else {
                print("⚠️ Migration: Journey not found for route \(route.id)")
                continue
            }

            // Get starting city key
            guard let startCityKey = journey.startCityKey else {
                print("⚠️ Migration: No startCityKey for journey \(journey.id)")
                continue
            }

            // Find or create the starting city
            if let cityIdx = cities.firstIndex(where: { $0.id == startCityKey }) {
                var city = cities[cityIdx]

                // Add journey ID if not already present
                if !city.journeyIds.contains(journey.id) {
                    city.journeyIds.append(journey.id)
                    city.explorations += 1
                    city.memories += journey.memoryCount
                    cities[cityIdx] = city
                    modified = true
                    print("✅ Migration: Added journey \(journey.id) to city \(startCityKey)")
                }
            } else {
                print("⚠️ Migration: Starting city \(startCityKey) not found for journey \(journey.id)")
            }
        }

        // Write marker file to prevent re-running migration
        let markerData = Data("migrated_intercity_routes_v3".utf8)
        fm.createFile(atPath: markerURL.path, contents: markerData)

        return modified
    }

    // MARK: - Thumbnail Path Migration (V2)

    /// Migrate thumbnail paths from absolute paths to relative paths (filenames only).
    /// This fixes the issue where thumbnails don't load after app rebuild because
    /// the Application Support directory path changes.
    ///
    /// Call this after CityCache loads data from disk.
    static func migrateThumbnailPathsToRelative(
        cities: inout [CachedCity],
        routes: inout [CachedInterCityRoute],
        markerURL: URL
    ) -> Bool {
        let fm = FileManager.default
        
        // Check if already migrated
        if fm.fileExists(atPath: markerURL.path) {
            return false
        }
        
        var modified = false
        
        // Migrate city thumbnail paths
        for i in cities.indices {
            if let basePath = cities[i].thumbnailBasePath, basePath.hasPrefix("/") {
                let filename = (basePath as NSString).lastPathComponent
                cities[i].thumbnailBasePath = filename
                modified = true
            }
            if let routePath = cities[i].thumbnailRoutePath, routePath.hasPrefix("/") {
                let filename = (routePath as NSString).lastPathComponent
                cities[i].thumbnailRoutePath = filename
                modified = true
            }
        }
        
        // Migrate route thumbnail paths
        for i in routes.indices {
            if let basePath = routes[i].thumbnailBasePath, basePath.hasPrefix("/") {
                let filename = (basePath as NSString).lastPathComponent
                routes[i].thumbnailBasePath = filename
                modified = true
            }
            if let routePath = routes[i].thumbnailRoutePath, routePath.hasPrefix("/") {
                let filename = (routePath as NSString).lastPathComponent
                routes[i].thumbnailRoutePath = filename
                modified = true
            }
        }
        
        // Write marker file to prevent re-running migration
        if modified {
            let markerData = Data("migrated_thumbnail_paths_v2".utf8)
            fm.createFile(atPath: markerURL.path, contents: markerData)
        }
        
        return modified
    }

    // MARK: - Helpers

    private static func moveFileIfExists(from legacy: URL, to new: URL, fm: FileManager) throws {
        guard fm.fileExists(atPath: legacy.path) else { return }
        // If target already exists, we keep the new one and do not overwrite.
        guard !fm.fileExists(atPath: new.path) else { return }

        try ensureParentDir(of: new, fm: fm)

        do {
            try fm.moveItem(at: legacy, to: new)
        } catch {
            // fallback: copy
            try fm.copyItem(at: legacy, to: new)
        }
    }

    /// Moves children of legacyDir into newDir.
    /// If newDir already has a file with the same name, we skip that child.
    private static func moveContentsIfExists(from legacyDir: URL, to newDir: URL, fm: FileManager) throws {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: legacyDir.path, isDirectory: &isDir), isDir.boolValue else { return }

        try ensureDir(newDir, fm: fm)

        let children = try fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil)
        for child in children {
            let dest = newDir.appendingPathComponent(child.lastPathComponent, isDirectory: false)
            if fm.fileExists(atPath: dest.path) {
                continue
            }
            do {
                try fm.moveItem(at: child, to: dest)
            } catch {
                try fm.copyItem(at: child, to: dest)
            }
        }
    }

    private static func ensureParentDir(of fileURL: URL, fm: FileManager) throws {
        try ensureDir(fileURL.deletingLastPathComponent(), fm: fm)
    }

    private static func ensureDir(_ dir: URL, fm: FileManager) throws {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dir.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
            try fm.removeItem(at: dir)
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
