//
//  JourneyFinalizer.swift
//  StreetStamps
//
//  修改版：自动判断城市/跨城，移除用户手动选择
//

import Foundation
import CoreLocation

enum JourneyFinalizeSource {
    case userConfirmedFinish
    case resumeDeclined
}

enum JourneyFinalizer {
    private static let driftMinimumDisplacementMeters: CLLocationDistance = 80
    private static let driftLowCoverageDistanceMeters: CLLocationDistance = 220
    private static let driftLongDurationThreshold: TimeInterval = 30 * 60
    private static let driftDetourRatioThreshold: Double = 3.5

    static func resolveCompletedRouteCityFields(
        route: JourneyRoute,
        startCanonical: ReverseGeocodeService.CanonicalResult?,
        endCanonical: ReverseGeocodeService.CanonicalResult?
    ) -> JourneyRoute {
        var updated = route

        let unknownLocalized = L10n.t("unknown")
        let existingDisplayName = (updated.cityName ?? updated.currentCity)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasResolvedDisplayName = !existingDisplayName.isEmpty
            && existingDisplayName.caseInsensitiveCompare("Unknown") != .orderedSame
            && existingDisplayName != unknownLocalized

        if let startCanonical {
            let stableStartKey = startCanonical.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let stableStartName = CityPlacemarkResolver.stableCityName(
                from: stableStartKey,
                fallback: startCanonical.cityName
            )

            updated.startCityKey = stableStartKey
            updated.cityKey = stableStartKey
            updated.canonicalCity = stableStartName
            updated.countryISO2 = startCanonical.iso2 ?? updated.countryISO2

            if !hasResolvedDisplayName {
                updated.cityName = stableStartName
                updated.currentCity = stableStartName
            }
        }

        if let endCanonical {
            updated.endCityKey = endCanonical.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.countryISO2 = endCanonical.iso2 ?? updated.countryISO2
        }

        return updated
    }

    /// Finalize a journey by:
    /// - ensuring start/end city keys are resolved (best-effort),
    /// - ✅ 自动判断 exploreMode (city vs interCity)
    /// - persisting the snapshot,
    /// - notifying CityCache for unlock logic (best-effort),
    /// then returning the updated journey via `completion`.
    private static let minimumPointsForCityUnlock = 1
    static func finalize(
        route: JourneyRoute,
        journeyStore: JourneyStore,
        cityCache: CityCache,
        lifelogStore: LifelogStore,
        source: JourneyFinalizeSource,
        recordedLocations: [CLLocation] = [],
        lastKnownLocation: CLLocation? = nil,
        completion: @escaping (JourneyRoute) -> Void
    ) {
        _ = source

        var r = route
        r.memories = r.memories.map {
            JourneyMemoryLocationResolver.finalize(
                memory: $0,
                lastKnownLocation: lastKnownLocation,
                recordedLocations: recordedLocations
            )
        }
        r.correctedCoordinates = JourneyPostCorrection.correctedCoordinates(for: r)
        if !r.correctedCoordinates.isEmpty {
            r.preferredRouteSource = .corrected
        }
        r.distance = JourneyPostCorrection.correctedDistance(for: r)
        r.isTooShort = shouldTreatAsStationaryDrift(route: r)

        func persistAndReturn(_ updated: JourneyRoute, notify: (() -> Void)?) {
            Task { @MainActor in
                // upsertSnapshotThrottled already calls flushPersist(force: true)
                // for completed journeys (endTime != nil), so no extra flushPersist needed.
                journeyStore.upsertSnapshotThrottled(updated, coordCount: updated.coordinates.count)
                if updated.endTime != nil {
                    lifelogStore.archiveJourneyPointsIfNeeded(updated)
                }
                notify?()
                completion(updated)
            }
        }
        let coordCount = r.coordinates.count
        // 如果坐标点太少，标记为无效旅程，不入城市库
        guard coordCount >= minimumPointsForCityUnlock,
              r.coordinates.first?.cl != nil,
              r.coordinates.last?.cl != nil
        else {
            // ✅ 标记旅程为 "太短/无效"
            r.isTooShort = true  // 需要在 JourneyRoute 中添加此属性
            
            // ✅ 只保存旅程，不通知 CityCache
            persistAndReturn(r, notify: nil)
            return
        }

        // 如果没有坐标，仍然持久化
        guard
            let startWgs = r.coordinates.first?.cl,
            let endWgs = r.coordinates.last?.cl
        else {
            persistAndReturn(r, notify: {
                Task { @MainActor in
                    cityCache.onJourneyCompleted(r)
                }
            })
            return
        }

        let fixedLocale = Locale(identifier: "en_US")
        let geocoder = CLGeocoder()

        let startLoc = CLLocation(latitude: startWgs.latitude, longitude: startWgs.longitude)
        let endLoc   = CLLocation(latitude: endWgs.latitude,  longitude: endWgs.longitude)

        geocoder.reverseGeocodeLocation(startLoc, preferredLocale: fixedLocale) { startPMs, _ in
            let startCanon = startPMs?.first.map { CityPlacemarkResolver.resolveCanonical(from: $0) }

            geocoder.reverseGeocodeLocation(endLoc, preferredLocale: fixedLocale) { endPMs, _ in
                let endCanon = endPMs?.first.map { CityPlacemarkResolver.resolveCanonical(from: $0) }
                let startCanonical = startCanon.map {
                    ReverseGeocodeService.CanonicalResult(
                        cityName: $0.city,
                        iso2: $0.iso2,
                        cityKey: $0.cityKey,
                        level: $0.level,
                        parentRegionKey: $0.parentRegionKey,
                        availableLevels: $0.availableLevelNames,
                        localeIdentifier: fixedLocale.identifier
                    )
                }
                let endCanonical = endCanon.map {
                    ReverseGeocodeService.CanonicalResult(
                        cityName: $0.city,
                        iso2: $0.iso2,
                        cityKey: $0.cityKey,
                        level: $0.level,
                        parentRegionKey: $0.parentRegionKey,
                        availableLevels: $0.availableLevelNames,
                        localeIdentifier: fixedLocale.identifier
                    )
                }

                r = resolveCompletedRouteCityFields(
                    route: r,
                    startCanonical: startCanonical,
                    endCanonical: endCanonical
                )

                // ✅ Always use city mode (intercity concept removed)
                // All journeys belong to their starting city
                r.exploreMode = .city

                // 通知CityCache - always use onJourneyCompleted
                let notify: () -> Void = {
                    Task { @MainActor in
                        cityCache.onJourneyCompleted(r)
                    }
                }

                persistAndReturn(r, notify: notify)
            }
        }
    }

    /// Minimum path distance that is clearly a real journey (not GPS drift).
    /// Round trips can have tiny displacement but long path — protect them.
    private static let driftPathDistanceSafeMeters: CLLocationDistance = 500

    private static func shouldTreatAsStationaryDrift(route: JourneyRoute) -> Bool {
        let effectiveCoords = (!route.correctedCoordinates.isEmpty ? route.correctedCoordinates : route.coordinates)
            .clCoords
            .filter(CLLocationCoordinate2DIsValid)
        guard effectiveCoords.count >= 2 else { return route.isTooShort }

        let start = CLLocation(latitude: effectiveCoords[0].latitude, longitude: effectiveCoords[0].longitude)
        let end = CLLocation(
            latitude: effectiveCoords[effectiveCoords.count - 1].latitude,
            longitude: effectiveCoords[effectiveCoords.count - 1].longitude
        )
        let displacement = start.distance(from: end)
        guard displacement < driftMinimumDisplacementMeters else { return route.isTooShort }

        let pathDistance = max(0, route.distance)
        if pathDistance <= driftLowCoverageDistanceMeters {
            return true
        }

        // A long enough path is a real journey even if start ≈ end (round trip).
        if pathDistance >= driftPathDistanceSafeMeters {
            return false
        }

        guard
            let startTime = route.startTime,
            let endTime = route.endTime
        else {
            return route.isTooShort
        }

        let duration = abs(endTime.timeIntervalSince(startTime))
        guard duration >= driftLongDurationThreshold else { return route.isTooShort }

        let safeDisplacement = max(displacement, 1)
        return (pathDistance / safeDisplacement) >= driftDetourRatioThreshold
    }
}
