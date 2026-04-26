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
    var trackTilesDir: URL { cachesDir.appendingPathComponent("track_tiles", isDirectory: true) }
    var lifelogDaysDir: URL { cachesDir.appendingPathComponent("lifelog_days", isDirectory: true) }
    var quarantineDir: URL { userRoot.appendingPathComponent("Quarantine", isDirectory: true) }

    // MARK: - Files

    var cityCacheURL: URL { cachesDir.appendingPathComponent("city_cache.json", isDirectory: false) }
    var cityMembershipIndexURL: URL { cachesDir.appendingPathComponent("city_membership_index.json", isDirectory: false) }
    var lifelogLegacyRouteURL: URL { cachesDir.appendingPathComponent("lifelog_route.json", isDirectory: false) }
    var lifelogPassiveRouteURL: URL { cachesDir.appendingPathComponent("lifelog_passive_route.json", isDirectory: false) }
    var lifelogRouteURL: URL { lifelogPassiveRouteURL }
    var lifelogDayShardIndexURL: URL { lifelogDaysDir.appendingPathComponent("index.json", isDirectory: false) }
    var lifelogTodayDeltaURL: URL { lifelogDaysDir.appendingPathComponent("today.delta.jsonl", isDirectory: false) }
    var lifelogCountryCellsURL: URL { cachesDir.appendingPathComponent("lifelog_country_cells.json", isDirectory: false) }
    var lifelogPointCountriesURL: URL { cachesDir.appendingPathComponent("lifelog_point_countries.json", isDirectory: false) }
    var lifelogCountryRunsURL: URL { cachesDir.appendingPathComponent("lifelog_country_runs.json", isDirectory: false) }

    /// Legacy route cache file - only used for V3 migration from older versions.
    /// Can be removed in a future version once all users have migrated.
    var routeCacheURL: URL { cachesDir.appendingPathComponent("route_cache.json", isDirectory: false) }
    var trackTileManifestURL: URL { trackTilesDir.appendingPathComponent("manifest.json", isDirectory: false) }
    var journeyRepairSourcesURL: URL { cachesDir.appendingPathComponent("journey_repair_sources.json", isDirectory: false) }
    var deletedJourneyIDsURL: URL { cachesDir.appendingPathComponent("deleted_journey_ids.json", isDirectory: false) }
    var photoDiscoveredCitiesURL: URL { cachesDir.appendingPathComponent("photo_discovered_cities.json", isDirectory: false) }
    var photoScanResultURL: URL { cachesDir.appendingPathComponent("photo_scan_result.json", isDirectory: false) }
    var renderMaskURL: URL { cachesDir.appendingPathComponent("render_mask.json", isDirectory: false) }

    /// Marker file to ensure one-time migrations.
    var migrationMarkerV1: URL { userRoot.appendingPathComponent(".migrated_v1", isDirectory: false) }
    
    /// Marker file for thumbnail path migration (absolute -> relative).
    var migrationMarkerV2_thumbnailPaths: URL { userRoot.appendingPathComponent(".migrated_v2_thumb_paths", isDirectory: false) }

    /// Marker file for intercity routes to starting city migration.
    var migrationMarkerV3_intercityToStartingCity: URL { userRoot.appendingPathComponent(".migrated_v3_intercity_to_city", isDirectory: false) }
    /// Marker file for removing legacy disk thumbnails.
    var migrationMarkerV4_removeLegacyThumbnails: URL { userRoot.appendingPathComponent(".migrated_v4_remove_legacy_thumbnails", isDirectory: false) }
    /// Marker file for lifelog split migration (legacy -> passive + bak).
    var migrationMarkerV5_lifelogPassiveSplit: URL { userRoot.appendingPathComponent(".migrated_v5_lifelog_passive_split", isDirectory: false) }
    /// Marker file for re-keying journeys to auto-level (removing user level preference).
    /// Bumped to v6b: KR strategy changed from locality to admin, strip list expanded.
    var migrationMarkerV6_autoLevelRekey: URL { userRoot.appendingPathComponent(".migrated_v6b_auto_level_rekey", isDirectory: false) }
    /// Marker file for strategy v2 rekey: JP/TH→admin, expanded country/subAdmin lists.
    var migrationMarkerV7_strategyV2Rekey: URL { userRoot.appendingPathComponent(".migrated_v7_strategy_v2_rekey", isDirectory: false) }

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
        try ensureDirectory(quarantineDir)
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
