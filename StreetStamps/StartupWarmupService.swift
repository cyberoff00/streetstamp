import Foundation
import UIKit

@MainActor
final class StartupWarmupService {
    static let shared = StartupWarmupService()

    private var hasStarted = false

    private init() {}

    func start(cityCache: CityCache, limit: Int = 24) {
        guard !hasStarted else { return }
        hasStarted = true

        let selected = Self.selectThumbnailPaths(from: cityCache.cachedCities, limit: limit)
        guard !selected.isEmpty else { return }

        Task.detached(priority: .utility) {
            for relativePath in selected {
                guard let fullPath = CityThumbnailCache.resolveFullPath(relativePath),
                      FileManager.default.fileExists(atPath: fullPath),
                      let image = UIImage(contentsOfFile: fullPath) else {
                    continue
                }

                CityImageMemoryCache.shared.set(image, forKey: relativePath)
            }
        }
    }

    nonisolated static func selectThumbnailPaths(from cities: [CachedCity], limit: Int) -> [String] {
        guard limit > 0 else { return [] }

        let prioritized = cities
            .filter { !($0.isTemporary ?? false) }
            .sorted { lhs, rhs in
                if lhs.explorations != rhs.explorations { return lhs.explorations > rhs.explorations }
                if lhs.memories != rhs.memories { return lhs.memories > rhs.memories }
                return lhs.name < rhs.name
            }

        var result: [String] = []
        var seen = Set<String>()

        for city in prioritized {
            let candidates = [city.thumbnailRoutePath, city.thumbnailBasePath]
            for item in candidates {
                guard let item, !item.isEmpty else { continue }
                guard seen.insert(item).inserted else { continue }
                result.append(item)
                if result.count >= limit {
                    return result
                }
            }
        }

        return result
    }
}
