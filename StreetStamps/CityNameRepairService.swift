import Foundation

enum CityNameRepairService {
    /// 重建 CityCache，确保包含所有旅程的城市
    static func rebuildCityCache(
        journeys: [JourneyRoute],
        paths: StoragePath
    ) throws {
        var cityMap: [String: CachedCity] = [:]

        for journey in journeys {
            guard let cityKey = journey.stableCityKey else { continue }

            if var city = cityMap[cityKey] {
                if !city.journeyIds.contains(journey.id) {
                    city.journeyIds.append(journey.id)
                    city.explorations += 1
                    city.memories += journey.memories.count
                    cityMap[cityKey] = city
                }
            } else {
                // 从旅程中提取城市信息
                let cityName = journey.cityName ?? journey.canonicalCity
                cityMap[cityKey] = CachedCity(
                    id: cityKey,
                    name: cityName,
                    countryISO2: journey.countryISO2,
                    journeyIds: [journey.id],
                    explorations: 1,
                    memories: journey.memories.count,
                    boundary: nil,
                    anchor: nil,
                    thumbnailBasePath: nil,
                    thumbnailRoutePath: nil
                )
            }
        }

        let cities = Array(cityMap.values)
        let data = try JSONEncoder().encode(cities)
        try data.write(to: paths.cityCacheURL, options: .atomic)

        print("✅ 重建 CityCache: \(cities.count) 个城市")
    }
}
