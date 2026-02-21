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
        source: JourneyFinalizeSource,
        completion: @escaping (JourneyRoute) -> Void
    ) {
        _ = source

        var r = route

        func persistAndReturn(_ updated: JourneyRoute, notify: (() -> Void)?) {
            Task { @MainActor in
                journeyStore.upsertSnapshotThrottled(updated, coordCount: updated.coordinates.count)
                journeyStore.flushPersist()
                notify?()
                completion(updated)
            }
        }
        let coordCount = r.coordinates.count
        // 如果坐标点太少，标记为无效旅程，不入城市库
        guard coordCount >= minimumPointsForCityUnlock,
              let startWgs = r.coordinates.first?.cl,
              let endWgs = r.coordinates.last?.cl
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
            let startKey = startCanon?.cityKey ?? ""

            geocoder.reverseGeocodeLocation(endLoc, preferredLocale: fixedLocale) { endPMs, _ in
                let endCanon = endPMs?.first.map { CityPlacemarkResolver.resolveCanonical(from: $0) }
                let endKey = endCanon?.cityKey ?? ""

                // ✅ 写入城市key
                r.startCityKey = startKey.isEmpty ? nil : startKey
                r.endCityKey   = endKey.isEmpty ? nil : endKey

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
}
