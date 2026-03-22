import Foundation

@MainActor
final class StartupWarmupService {
    static let shared = StartupWarmupService()

    private var warmedRenderKeys = Set<String>()

    private init() {}

    private func log(_ message: String) {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let enabled = args.contains("-CityThumbnailDebug")
            || UserDefaults.standard.bool(forKey: "city.thumbnail.debug.enabled")
        guard enabled else { return }
        print("🔥 [CityThumbWarmup] \(message)")
#endif
    }

    func start(cities: [City], appearanceRaw: String, renderCacheStore: CityRenderCacheStore, limit: Int = 24) {
        let selected = Self.selectCities(from: cities, limit: limit)
        guard !selected.isEmpty else { return }

        let citiesToWarm = selected.filter {
            let key = CityThumbnailLoader.renderCacheKey(for: $0, appearanceRaw: appearanceRaw)
            return warmedRenderKeys.insert(key).inserted
        }
        log("start totalCities=\(cities.count) selected=\(selected.count) warming=\(citiesToWarm.count) appearance=\(appearanceRaw)")
        guard !citiesToWarm.isEmpty else { return }

        Task(priority: .utility) {
            for city in citiesToWarm {
                await MainActor.run {
                    self.log("warm city=\(city.id) name=\(city.localizedName)")
                }
                await CityThumbnailLoader.ensurePersistentCache(for: city, appearanceRaw: appearanceRaw, renderCacheStore: renderCacheStore)
            }
        }
    }

    nonisolated static func selectCities(from cities: [City], limit: Int) -> [City] {
        guard limit > 0 else { return [] }

        return cities
            .sorted { lhs, rhs in
                if lhs.explorations != rhs.explorations { return lhs.explorations > rhs.explorations }
                if lhs.memories != rhs.memories { return lhs.memories > rhs.memories }
                return lhs.name < rhs.name
            }
            .prefix(limit)
            .map { $0 }
    }
}
