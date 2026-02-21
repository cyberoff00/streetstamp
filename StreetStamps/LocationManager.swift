import Foundation
import CoreLocation
import Combine

@MainActor
final class CityLocationManager: ObservableObject {

    /// ✅ UI 展示用（跟随系统语言）
    @Published private(set) var displayName: String = "Unknown"

    /// ✅ 后端 canonical（英文，稳定）
    @Published private(set) var canonicalCity: String = "Unknown"
    @Published private(set) var countryISO2: String? = nil
    @Published private(set) var canonicalCityKey: String = "Unknown|"

    private var cancellable: AnyCancellable?

    /// ✅ 进一步减少 geocode：移动超过一定距离才尝试
    private var lastGeocodedLocation: CLLocation?
    private let minDistanceForGeocode: CLLocationDistance = 250

    /// ✅ 防止旧请求回写
    private var canonicalTask: Task<Void, Never>?
    private var displayTask: Task<Void, Never>?

    func bind(to hub: LocationHub) {
        cancellable?.cancel()

        cancellable = hub.locationStream
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] loc in
                guard let self else { return }
                self.reverseGeocodeIfNeeded(loc)
            }
    }

    private func reverseGeocodeIfNeeded(_ loc: CLLocation) {
        // 1) 距离门控（避免疯狂 geocode）
        if let last = lastGeocodedLocation, loc.distance(from: last) < minDistanceForGeocode {
            return
        }
        lastGeocodedLocation = loc

        // 2) cancel stale callbacks (do NOT spam system geocoder)
        canonicalTask?.cancel()
        displayTask?.cancel()

        // A) canonical (stable key) — globally rate-limited + cached
        canonicalTask = Task { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }

            guard let canon = await ReverseGeocodeService.shared.canonical(for: loc) else { return }
            if Task.isCancelled { return }

            // Best-effort localized title: cached only (no new request here)
            let cachedTitle = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: canon.cityKey)

            // Update canonical fields + ensure display updates immediately when cityKey changes
            await MainActor.run {
                let cityChanged = canon.cityKey != self.canonicalCityKey

                if canon.cityName != self.canonicalCity || canon.iso2 != self.countryISO2 || canon.cityKey != self.canonicalCityKey {
                    self.canonicalCity = canon.cityName
                    self.countryISO2 = canon.iso2
                    self.canonicalCityKey = canon.cityKey
                }

                // If we moved to a new city, never keep the old label.
                if cityChanged {
                    self.displayName = cachedTitle ?? canon.cityName
                } else if let cachedTitle {
                    // Same city, but we might have learned a localized title later.
                    self.displayName = cachedTitle
                } else if self.displayName == "Unknown" {
                    self.displayName = canon.cityName
                }
            }

            // B) display localization: only once per cityKey (de-dupe in service)
            if cachedTitle != nil {
                return
            }

            displayTask = Task { [weak self] in
                guard let self else { return }
                if Task.isCancelled { return }
                let title = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: canon.cityKey)
                if Task.isCancelled { return }
                guard let title else { return }
                await MainActor.run { self.displayName = title }
            }
        }
    }

    // MARK: - Backward compatibility (如果你其他地方还在用 cityName)
    var cityName: String { canonicalCity }

    /// ✅ 给 CityCache / Journey 用：稳定 key（英文稳定）
    var canonicalKey: String { canonicalCityKey }
}
