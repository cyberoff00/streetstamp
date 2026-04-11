//
//  PhotoCityDiscoveryService.swift
//  StreetStamps
//
//  Scans Apple Photos library for geotagged images, clusters them by geographic
//  grid cells, reverse-geocodes each cluster centroid via `ReverseGeocodeService`,
//  and produces a list of discovered cities.  Designed for silent background
//  execution — all heavy work runs off the main thread.
//

import Foundation
import Photos
import CoreLocation

// MARK: - Data types

struct PhotoDiscoveredCity: Codable, Sendable {
    let cityKey: String
    let cityName: String
    let countryISO2: String?
    let anchor: LatLon
    var photoCount: Int
    var earliestDate: Date?
    var latestDate: Date?
    let identityLevelRaw: String?
    let parentScopeKey: String?
    let availableLevelNames: [String: String]?
}

struct PhotoScanResult: Codable, Sendable {
    /// Bump this when geocode logic changes to force a full re-scan.
    /// v3: KR strategy changed to admin, strip suffix list expanded.
    /// v4: Reject fallback levels for photo scan; clear all old photo-discovered cities.
    /// v5: fittedRegion fix (single-anchor cities used 0.01° span → blank tiles); force full re-scan.
    static let currentVersion = 5

    var version: Int = PhotoScanResult.currentVersion
    var cities: [PhotoDiscoveredCity]
    var processedGridCells: Set<String>
    let scanDate: Date
    let photosScanned: Int
}

// MARK: - Service

actor PhotoCityDiscoveryService {

    static let shared = PhotoCityDiscoveryService()

    // MARK: - Grid clustering

    /// 0.5-degree grid cell (~50 km at mid-latitudes).
    private struct GridCell: Hashable {
        let latBucket: Int
        let lonBucket: Int
        var key: String { "\(latBucket),\(lonBucket)" }
    }

    private struct PhotoPoint {
        let coordinate: CLLocationCoordinate2D
        let date: Date?
    }

    // MARK: - Public API

    /// Run a scan.  Pass the previous `PhotoScanResult` for incremental mode (only
    /// new grid cells are geocoded).  The `onProgress` closure fires on each completed
    /// geocode call with `(done, total)` — caller is responsible for dispatching to main.
    func scan(
        previousResult: PhotoScanResult?,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> PhotoScanResult? {

        // 0. Version check — force full re-scan if geocode logic changed
        let previous = (previousResult?.version == PhotoScanResult.currentVersion) ? previousResult : nil

        // 1. Authorisation --------------------------------------------------
        guard await requestPhotoAccess() else { return nil }

        // 2. Fetch all geotagged photo coordinates (sync Photos API, but we
        //    are already on a non-main executor because this is an actor method
        //    called from Task.detached).
        let photos = fetchGeotaggedPhotos()
        guard !photos.isEmpty else {
            return PhotoScanResult(cities: previous?.cities ?? [],
                                   processedGridCells: previous?.processedGridCells ?? [],
                                   scanDate: Date(),
                                   photosScanned: 0)
        }

        // 3. Cluster by grid ------------------------------------------------
        let clusters = clusterByGrid(photos)

        // 4. Determine which cells are new, with minimum photo threshold ------
        let minPhotosPerCell = 10
        let knownCells = previous?.processedGridCells ?? []
        let newCells = clusters.filter { !knownCells.contains($0.key.key) && $0.value.count >= minPhotosPerCell }
        // 5. Geocode new cells ----------------------------------------------
        let total = newCells.count
        var newDiscovered: [PhotoDiscoveredCity] = []
        var allProcessedCells = knownCells

        for (index, (cell, points)) in newCells.enumerated() {
            guard !Task.isCancelled else { return nil }
            let centroid = computeCentroid(points)
            let location = CLLocation(latitude: centroid.latitude, longitude: centroid.longitude)

            // Wait for network + throttle before attempting geocode
            if !ReverseGeocodeService.shared.isNetworkAvailable {
                let recovered = await ReverseGeocodeService.shared.waitForNetwork(timeout: 60)
                if !recovered {
                    // No network for 60s — stop burning cells, let next scan retry
                    onProgress?(index + 1, total)
                    continue
                }
            }
            let throttleWait = await ReverseGeocodeService.shared.throttleRemainingSeconds()
            if throttleWait > 0 {
                try? await Task.sleep(nanoseconds: UInt64((throttleWait + 1.0) * 1_000_000_000))
            }

            var result: ReverseGeocodeService.CanonicalResult?
            for attempt in 0..<5 {
                // Check network before each retry
                if !ReverseGeocodeService.shared.isNetworkAvailable {
                    let recovered = await ReverseGeocodeService.shared.waitForNetwork(timeout: 30)
                    if !recovered { break }
                }
                result = await ReverseGeocodeService.shared.canonicalWithRetry(for: location, maxAttempts: 2)
                if result != nil { break }
                // Wait for throttle if that's why we failed; otherwise fixed back-off
                let remaining = await ReverseGeocodeService.shared.throttleRemainingSeconds()
                let delay = remaining > 0 ? remaining + 1.0 : 3.0 * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard let r = result else {
                // Geocode failed — do NOT mark cell as processed so next scan retries it
                onProgress?(index + 1, total)
                continue
            }

            // Photo coordinates are imprecise — reject results that don't match
            // the expected strategy level. Retry with a real photo coordinate first;
            // if still wrong, skip entirely (don't create a junk card).
            var best = r
            if isBroadForStrategy(r) {
                var retried = false
                if let retryPoint = points.first {
                    let retryLoc = CLLocation(latitude: retryPoint.coordinate.latitude, longitude: retryPoint.coordinate.longitude)
                    if let finer = await ReverseGeocodeService.shared.canonicalWithRetry(for: retryLoc, maxAttempts: 2),
                       !isBroadForStrategy(finer) {
                        best = finer
                        retried = true
                    }
                }
                if !retried {
                    // Still wrong level after retry — skip, don't mark as processed
                    onProgress?(index + 1, total)
                    continue
                }
            }

            allProcessedCells.insert(cell.key)

            let (earliest, latest) = dateRange(points)
            let city = PhotoDiscoveredCity(
                cityKey: best.cityKey,
                cityName: best.cityName,
                countryISO2: best.iso2,
                anchor: LatLon(.init(latitude: centroid.latitude, longitude: centroid.longitude)),
                photoCount: points.count,
                earliestDate: earliest,
                latestDate: latest,
                identityLevelRaw: best.level.rawValue,
                parentScopeKey: best.parentRegionKey,
                availableLevelNames: best.availableLevels.reduce(into: [String: String]()) { dict, pair in
                    dict[pair.key.rawValue] = pair.value
                }
            )
            newDiscovered.append(city)

            onProgress?(index + 1, total)
        }

        // 6. Merge: carry forward old cities, add new ones on top
        var byCityKey: [String: PhotoDiscoveredCity] = [:]
        for city in (previous?.cities ?? []) {
            byCityKey[city.cityKey] = city
        }
        for city in newDiscovered {
            if var existing = byCityKey[city.cityKey] {
                existing.photoCount += city.photoCount
                existing.earliestDate = minDate(existing.earliestDate, city.earliestDate)
                existing.latestDate = maxDate(existing.latestDate, city.latestDate)
                byCityKey[city.cityKey] = existing
            } else {
                byCityKey[city.cityKey] = city
            }
        }

        let cities = Array(byCityKey.values).sorted { $0.photoCount > $1.photoCount }

        return PhotoScanResult(
            cities: cities,
            processedGridCells: allProcessedCells,
            scanDate: Date(),
            photosScanned: photos.count
        )
    }

    // MARK: - Private helpers

    /// Returns true if the result level doesn't match the expected strategy level.
    /// Photo scan is strict — only the exact expected level is accepted.
    private func isBroadForStrategy(_ r: ReverseGeocodeService.CanonicalResult) -> Bool {
        guard let iso2 = r.iso2 else { return false }
        let expected = CityPlacemarkResolver.inferIdentityLevel(cityKey: r.cityKey, iso2: iso2)
        return r.level != expected
    }

    private func requestPhotoAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return granted == .authorized || granted == .limited
        default:
            return false
        }
    }

    private nonisolated func fetchGeotaggedPhotos() -> [PhotoPoint] {
        let options = PHFetchOptions()
        // PHAsset doesn't support "location != nil" predicate — fetch all images
        // and filter in memory. This is still fast (metadata only, no image loading).
        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var points: [PhotoPoint] = []
        points.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            guard let loc = asset.location else { return }
            let coord = loc.coordinate
            guard CLLocationCoordinate2DIsValid(coord) else { return }
            points.append(PhotoPoint(coordinate: coord, date: asset.creationDate))
        }
        return points
    }

    private func clusterByGrid(_ photos: [PhotoPoint]) -> [GridCell: [PhotoPoint]] {
        var clusters: [GridCell: [PhotoPoint]] = [:]
        for photo in photos {
            let cell = GridCell(
                latBucket: Int(round(photo.coordinate.latitude * 2)),
                lonBucket: Int(round(photo.coordinate.longitude * 2))
            )
            clusters[cell, default: []].append(photo)
        }
        return clusters
    }

    private func computeCentroid(_ points: [PhotoPoint]) -> (latitude: Double, longitude: Double) {
        guard !points.isEmpty else { return (0, 0) }
        let sumLat = points.reduce(0.0) { $0 + $1.coordinate.latitude }
        let sumLon = points.reduce(0.0) { $0 + $1.coordinate.longitude }
        let n = Double(points.count)
        return (sumLat / n, sumLon / n)
    }

    private func dateRange(_ points: [PhotoPoint]) -> (earliest: Date?, latest: Date?) {
        let dates = points.compactMap(\.date)
        return (dates.min(), dates.max())
    }

    private func minDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case (.some(let a), .some(let b)): return min(a, b)
        case (.some, .none): return a
        case (.none, .some): return b
        case (.none, .none): return nil
        }
    }

    private func maxDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case (.some(let a), .some(let b)): return max(a, b)
        case (.some, .none): return a
        case (.none, .some): return b
        case (.none, .none): return nil
        }
    }
}
