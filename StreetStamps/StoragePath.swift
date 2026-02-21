//
//  StoragePath.swift
//  StreetStamps
//
//  Created by Claire Yang on 21/01/2026.
//

import Foundation

/// Single source of truth for all on-disk locations.
///
/// Target layout:
/// Application Support/StreetStamps/<userID>/
///   Journeys/
///   Caches/
///     city_cache.json
///     route_cache.json
///   Photos/
///   Thumbnails/
struct StoragePath: Sendable {
    let userID: String
    let fm: FileManager

    init(userID: String, fm: FileManager = .default) {
        self.userID = userID
        self.fm = fm
    }

    // MARK: - Roots

    /// .../Application Support/StreetStamps/<userID>
    var userRoot: URL {
        appSupportRoot
            .appendingPathComponent("StreetStamps", isDirectory: true)
            .appendingPathComponent(userID, isDirectory: true)
    }

    /// .../Application Support
    var appSupportRoot: URL {
        guard let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            preconditionFailure("Cannot resolve applicationSupportDirectory")
        }
        return url
    }

    // MARK: - Directories

    var journeysDir: URL { userRoot.appendingPathComponent("Journeys", isDirectory: true) }
    var cachesDir: URL { userRoot.appendingPathComponent("Caches", isDirectory: true) }
    var photosDir: URL { userRoot.appendingPathComponent("Photos", isDirectory: true) }
    var thumbnailsDir: URL { userRoot.appendingPathComponent("Thumbnails", isDirectory: true) }

    // MARK: - Files

    var cityCacheURL: URL { cachesDir.appendingPathComponent("city_cache.json", isDirectory: false) }
    var lifelogRouteURL: URL { cachesDir.appendingPathComponent("lifelog_route.json", isDirectory: false) }

    /// Legacy route cache file - only used for V3 migration from older versions.
    /// Can be removed in a future version once all users have migrated.
    var routeCacheURL: URL { cachesDir.appendingPathComponent("route_cache.json", isDirectory: false) }

    /// Marker file to ensure one-time migrations.
    var migrationMarkerV1: URL { userRoot.appendingPathComponent(".migrated_v1", isDirectory: false) }
    
    /// Marker file for thumbnail path migration (absolute -> relative).
    var migrationMarkerV2_thumbnailPaths: URL { userRoot.appendingPathComponent(".migrated_v2_thumb_paths", isDirectory: false) }

    /// Marker file for intercity routes to starting city migration.
    var migrationMarkerV3_intercityToStartingCity: URL { userRoot.appendingPathComponent(".migrated_v3_intercity_to_city", isDirectory: false) }
    /// Marker file for removing legacy disk thumbnails.
    var migrationMarkerV4_removeLegacyThumbnails: URL { userRoot.appendingPathComponent(".migrated_v4_remove_legacy_thumbnails", isDirectory: false) }

    // MARK: - Ensure directories exist

    /// Call once during bootstrap (or before first IO).
    func ensureBaseDirectoriesExist() throws {
        try ensureDirectory(appSupportRoot
            .appendingPathComponent("StreetStamps", isDirectory: true))

        try ensureDirectory(userRoot)
        try ensureDirectory(journeysDir)
        try ensureDirectory(cachesDir)
        try ensureDirectory(photosDir)
        try ensureDirectory(thumbnailsDir)
    }

    func ensureDirectory(_ url: URL) throws {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
            // Exists but is a file => replace with directory
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
