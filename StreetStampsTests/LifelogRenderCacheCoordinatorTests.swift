import XCTest
@testable import StreetStamps

final class LifelogRenderCacheCoordinatorTests: XCTestCase {
    func test_placeholderSnapshotWhileSwitchingDay_prefersExistingSnapshotOverEmptyState() {
        let currentDay = Calendar.current.startOfDay(for: Date())
        let targetDay = Calendar.current.date(byAdding: .day, value: -1, to: currentDay) ?? currentDay
        let existing = LifelogRenderSnapshot(
            selectedDay: currentDay,
            cachedPathCoordsWGS84: [CoordinateCodable(lat: 37.7749, lon: -122.4194)],
            farRouteSegments: [],
            footprintRuns: [[CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)]],
            selectedDayCenterCoordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            isHighQuality: true
        )

        let placeholder = LifelogRenderRefreshPolicy.placeholderSnapshot(
            currentSnapshot: existing,
            targetDay: targetDay,
            cachedSnapshot: nil
        )

        XCTAssertEqual(placeholder.selectedDay, currentDay)
        XCTAssertEqual(placeholder.cachedPathCoordsWGS84.count, 1)
        XCTAssertEqual(placeholder.footprintRuns.count, 1)
        XCTAssertTrue(placeholder.isHighQuality)
    }

    @MainActor
    func test_noteCountryAttributionRefresh_invalidatesTodayOnlyAndUpdatesWarmupCountry() {
        let coordinator = LifelogRenderCacheCoordinator()
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today

        let todayKey = LifelogDaySnapshotKey(day: today, countryISO2: "US", journeyRevision: 1, lifelogRevision: 1)
        let yesterdayKey = LifelogDaySnapshotKey(day: yesterday, countryISO2: "US", journeyRevision: 1, lifelogRevision: 1)

        coordinator.seedDaySnapshotForTesting(
            LifelogRenderSnapshotBuilder.buildDaySnapshot(
                key: todayKey,
                segments: [
                    TrackTileSegment(
                        sourceType: .passive,
                        coordinates: [
                            CoordinateCodable(lat: 37.7749, lon: -122.4194),
                            CoordinateCodable(lat: 37.7752, lon: -122.4190)
                        ],
                        startTimestamp: today,
                        endTimestamp: today.addingTimeInterval(60)
                    )
                ]
            )
        )
        coordinator.seedDaySnapshotForTesting(
            LifelogRenderSnapshotBuilder.buildDaySnapshot(
                key: yesterdayKey,
                segments: [
                    TrackTileSegment(
                        sourceType: .passive,
                        coordinates: [
                            CoordinateCodable(lat: 48.8566, lon: 2.3522),
                            CoordinateCodable(lat: 48.8569, lon: 2.3529)
                        ],
                        startTimestamp: yesterday,
                        endTimestamp: yesterday.addingTimeInterval(60)
                    )
                ]
            )
        )
        coordinator.scheduleWarmupRecentDays(anchorDay: today, countryISO2: "US")

        coordinator.noteCountryAttributionRefresh(countryISO2: "CN")

        XCTAssertFalse(coordinator.hasCachedDaySnapshotForTesting(todayKey))
        XCTAssertTrue(coordinator.hasCachedDaySnapshotForTesting(yesterdayKey))
        XCTAssertEqual(coordinator.pendingWarmupRequestForTesting?.countryISO2, "CN")
        XCTAssertEqual(coordinator.todayDirtyCountryISO2ForTesting, "CN")
        XCTAssertTrue(coordinator.hasDirtyTodayForTesting)
    }

    func test_countryAttributionCoordinator_buildsRunsFromResolvedAndUnknownPoints() async throws {
        let userID = "lifelog-country-runs-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let coordinator = LifelogCountryAttributionCoordinator(
            paths: paths,
            resolveCanonical: { location in
                if location.coordinate.longitude > 100 {
                    return ReverseGeocodeService.CanonicalResult(
                        cityName: "Beijing",
                        iso2: "CN",
                        cityKey: "Beijing|CN",
                        level: .locality,
                        parentRegionKey: "Beijing Municipality|CN",
                        availableLevels: [.locality: "Beijing"]
                    )
                }
                if location.coordinate.longitude < 0 {
                    return ReverseGeocodeService.CanonicalResult(
                        cityName: "San Francisco",
                        iso2: "US",
                        cityKey: "San Francisco|US",
                        level: .locality,
                        parentRegionKey: "California|US",
                        availableLevels: [.locality: "San Francisco"]
                    )
                }
                return nil
            }
        )

        await coordinator.enqueue(points: [
            LifelogCountryAttributionPointInput(
                pointID: "point-1",
                cellID: "cn-cell",
                coordinate: CoordinateCodable(lat: 39.9042, lon: 116.4074)
            ),
            LifelogCountryAttributionPointInput(
                pointID: "point-2",
                cellID: "cn-cell",
                coordinate: CoordinateCodable(lat: 39.90425, lon: 116.40745)
            ),
            LifelogCountryAttributionPointInput(
                pointID: "point-3",
                cellID: "unknown-cell",
                coordinate: CoordinateCodable(lat: 0.0, lon: 0.0)
            ),
            LifelogCountryAttributionPointInput(
                pointID: "point-4",
                cellID: "us-cell",
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            ),
            LifelogCountryAttributionPointInput(
                pointID: "point-5",
                cellID: "us-cell",
                coordinate: CoordinateCodable(lat: 37.7750, lon: -122.4193)
            )
        ])

        let snapshot = try await waitForAttributionSnapshot(at: paths, timeout: 1.5) {
            $0.points.count == 5 && $0.cells.count == 2 && $0.runs.count == 3
        }

        XCTAssertEqual(
            snapshot.runs,
            [
                LifelogCountryRunRecord(startPointID: "point-1", endPointID: "point-2", iso2: "CN"),
                LifelogCountryRunRecord(startPointID: "point-3", endPointID: "point-3", iso2: nil),
                LifelogCountryRunRecord(startPointID: "point-4", endPointID: "point-5", iso2: "US")
            ]
        )
    }

    func test_countryAttributionCoordinator_incrementallyExtendsTailRuns() async throws {
        let userID = "lifelog-country-runs-tail-\(UUID().uuidString)"
        let paths = StoragePath(userID: userID)
        try? FileManager.default.removeItem(at: paths.userRoot)
        try paths.ensureBaseDirectoriesExist()

        let coordinator = LifelogCountryAttributionCoordinator(
            paths: paths,
            resolveCanonical: { location in
                if location.coordinate.longitude > 100 {
                    return ReverseGeocodeService.CanonicalResult(
                        cityName: "Beijing",
                        iso2: "CN",
                        cityKey: "Beijing|CN",
                        level: .locality,
                        parentRegionKey: "Beijing Municipality|CN",
                        availableLevels: [.locality: "Beijing"]
                    )
                }
                return ReverseGeocodeService.CanonicalResult(
                    cityName: "San Francisco",
                    iso2: "US",
                    cityKey: "San Francisco|US",
                    level: .locality,
                    parentRegionKey: "California|US",
                    availableLevels: [.locality: "San Francisco"]
                )
            }
        )

        await coordinator.enqueue(points: [
            LifelogCountryAttributionPointInput(
                pointID: "point-1",
                cellID: "cn-cell",
                coordinate: CoordinateCodable(lat: 39.9042, lon: 116.4074)
            ),
            LifelogCountryAttributionPointInput(
                pointID: "point-2",
                cellID: "cn-cell",
                coordinate: CoordinateCodable(lat: 39.90425, lon: 116.40745)
            )
        ])

        _ = try await waitForAttributionSnapshot(at: paths, timeout: 1.0) {
            $0.runs == [LifelogCountryRunRecord(startPointID: "point-1", endPointID: "point-2", iso2: "CN")]
        }

        await coordinator.enqueue(points: [
            LifelogCountryAttributionPointInput(
                pointID: "point-3",
                cellID: "cn-cell",
                coordinate: CoordinateCodable(lat: 39.9043, lon: 116.4075)
            ),
            LifelogCountryAttributionPointInput(
                pointID: "point-4",
                cellID: "us-cell",
                coordinate: CoordinateCodable(lat: 37.7749, lon: -122.4194)
            )
        ])

        let snapshot = try await waitForAttributionSnapshot(at: paths, timeout: 1.5) {
            $0.runs == [
                LifelogCountryRunRecord(startPointID: "point-1", endPointID: "point-3", iso2: "CN"),
                LifelogCountryRunRecord(startPointID: "point-4", endPointID: "point-4", iso2: "US")
            ]
        }

        XCTAssertEqual(
            snapshot.runs,
            [
                LifelogCountryRunRecord(startPointID: "point-1", endPointID: "point-3", iso2: "CN"),
                LifelogCountryRunRecord(startPointID: "point-4", endPointID: "point-4", iso2: "US")
            ]
        )
    }

    func test_countryRunBuilder_rebuildRuns_preservesUnaffectedPrefixRuns() {
        let points = [
            LifelogPointCountryRecord(pointID: "point-1", cellID: "gb", iso2: "GB"),
            LifelogPointCountryRecord(pointID: "point-2", cellID: "gb", iso2: "GB"),
            LifelogPointCountryRecord(pointID: "point-3", cellID: "cn", iso2: "CN"),
            LifelogPointCountryRecord(pointID: "point-4", cellID: "cn", iso2: "CN"),
            LifelogPointCountryRecord(pointID: "point-5", cellID: "us", iso2: "US")
        ]
        let existingRuns = [
            LifelogCountryRunRecord(startPointID: "point-1", endPointID: "point-2", iso2: "GB"),
            LifelogCountryRunRecord(startPointID: "point-3", endPointID: "point-3", iso2: nil),
            LifelogCountryRunRecord(startPointID: "point-4", endPointID: "point-5", iso2: "US")
        ]

        let rebuilt = LifelogCountryRunBuilder.rebuildRuns(
            existingRuns: existingRuns,
            points: points,
            fromPointIndex: 3
        )

        XCTAssertEqual(
            rebuilt,
            [
                LifelogCountryRunRecord(startPointID: "point-1", endPointID: "point-2", iso2: "GB"),
                LifelogCountryRunRecord(startPointID: "point-3", endPointID: "point-4", iso2: "CN"),
                LifelogCountryRunRecord(startPointID: "point-5", endPointID: "point-5", iso2: "US")
            ]
        )
    }

    func test_recentWarmupDays_returnsTodayThenPreviousSixDays() {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let days = LifelogRenderWarmupPlanner.recentDays(anchorDay: anchor, count: 7)

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, Calendar.current.startOfDay(for: anchor))
        XCTAssertEqual(
            days.last,
            Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: anchor))
        )
    }

    func test_viewportBucket_roundsNearbyRegionsToSameBucket() {
        let a = TrackTileViewport(minLat: 37.70, maxLat: 37.80, minLon: -122.50, maxLon: -122.30)
        let b = TrackTileViewport(minLat: 37.70002, maxLat: 37.80002, minLon: -122.50002, maxLon: -122.30002)

        XCTAssertEqual(
            LifelogViewportBucket.bucket(for: a),
            LifelogViewportBucket.bucket(for: b)
        )
    }

    private func waitForAttributionSnapshot(
        at paths: StoragePath,
        timeout: TimeInterval,
        until check: @escaping (LifelogCountryAttributionSnapshot) -> Bool
    ) async throws -> LifelogCountryAttributionSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        let store = LifelogCountryAttributionStore(paths: paths)
        while Date() < deadline {
            if let snapshot = try? store.load(), check(snapshot) {
                return snapshot
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let snapshot = try store.load()
        XCTAssertTrue(check(snapshot), "Timed out waiting for attribution snapshot to match expectation.")
        return snapshot
    }
}
