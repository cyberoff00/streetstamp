import Foundation
import CoreLocation

// MARK: - Weather Condition

enum WeatherCondition: Equatable {
    case clear
    case cloudy
    case drizzle          // WMO 51,53,55
    case rain             // WMO 61,63,65
    case heavyRain        // WMO 65,67,82
    case thunderstorm     // WMO 95,96,99
    case snow             // WMO 71,73,75,77,85,86
    case fog              // WMO 45,48

    var isRaining: Bool {
        switch self {
        case .drizzle, .rain, .heavyRain, .thunderstorm: return true
        default: return false
        }
    }

    var isSnowing: Bool { self == .snow }
    var isFoggy: Bool { self == .fog }

    var sfSymbol: String {
        switch self {
        case .clear:        return "sun.max.fill"
        case .cloudy:       return "cloud.fill"
        case .drizzle:      return "cloud.drizzle.fill"
        case .rain:         return "cloud.rain.fill"
        case .heavyRain:    return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .snow:         return "cloud.snow.fill"
        case .fog:          return "cloud.fog.fill"
        }
    }

    var displayLabel: String {
        switch self {
        case .clear:        return "Clear"
        case .cloudy:       return "Cloudy"
        case .drizzle:      return "Drizzle"
        case .rain:         return "Rain"
        case .heavyRain:    return "Heavy Rain"
        case .thunderstorm: return "Thunderstorm"
        case .snow:         return "Snow"
        case .fog:          return "Fog"
        }
    }

    static var allCases: [WeatherCondition] {
        [.clear, .cloudy, .fog, .drizzle, .rain, .heavyRain, .thunderstorm, .snow]
    }

    /// Rain intensity 0...1
    var rainIntensity: Double {
        switch self {
        case .drizzle:      return 0.25
        case .rain:         return 0.55
        case .heavyRain:    return 0.85
        case .thunderstorm: return 1.0
        default:            return 0.0
        }
    }

    static func from(wmoCode: Int) -> WeatherCondition {
        switch wmoCode {
        case 0, 1:           return .clear
        case 2, 3:           return .cloudy
        case 45, 48:         return .fog
        case 51, 53, 55, 56, 57: return .drizzle
        case 61, 63:         return .rain
        case 65, 66, 67:     return .heavyRain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 80, 81:         return .rain
        case 82:             return .heavyRain
        case 95, 96, 99:     return .thunderstorm
        default:             return .clear
        }
    }
}

// MARK: - Weather Data

struct WeatherData: Equatable {
    let condition: WeatherCondition
    let temperature: Double      // Celsius
    let windSpeed: Double        // km/h
    let windDirection: Double    // degrees
    let humidity: Int            // %
    let timestamp: Date
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: WeatherData, rhs: WeatherData) -> Bool {
        lhs.condition == rhs.condition &&
        lhs.temperature == rhs.temperature &&
        lhs.windSpeed == rhs.windSpeed
    }
}

// MARK: - Weather Service

@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published private(set) var current: WeatherData?
    @Published private(set) var isLoading = false
    @Published var debugOverride: WeatherCondition? = nil

    /// The effective condition shown in UI (debug override takes priority)
    var effectiveCondition: WeatherCondition {
        debugOverride ?? current?.condition ?? .clear
    }

    /// Synthetic WeatherData using debug override or real data
    var effectiveWeather: WeatherData? {
        if let override = debugOverride {
            return WeatherData(
                condition: override,
                temperature: current?.temperature ?? 20,
                windSpeed: current?.windSpeed ?? 15,
                windDirection: current?.windDirection ?? 180,
                humidity: current?.humidity ?? 70,
                timestamp: Date(),
                coordinate: current?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            )
        }
        return current
    }

    private var lastFetchCoordinate: CLLocationCoordinate2D?
    private var lastFetchTime: Date?
    private let minimumFetchInterval: TimeInterval = 600 // 10 min
    private let minimumDistanceMeters: Double = 3000     // 3 km

    private init() {}

    func fetchIfNeeded(for location: CLLocation) {
        let now = Date()

        if let lastTime = lastFetchTime, let lastCoord = lastFetchCoordinate {
            let elapsed = now.timeIntervalSince(lastTime)
            let distance = location.distance(from: CLLocation(
                latitude: lastCoord.latitude,
                longitude: lastCoord.longitude
            ))
            if elapsed < minimumFetchInterval && distance < minimumDistanceMeters {
                return
            }
        }

        lastFetchCoordinate = location.coordinate
        lastFetchTime = now

        Task { await fetch(coordinate: location.coordinate) }
    }

    private func fetch(coordinate: CLLocationCoordinate2D) async {
        isLoading = true
        defer { isLoading = false }

        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=weather_code,temperature_2m,wind_speed_10m,wind_direction_10m,relative_humidity_2m&timezone=auto"

        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let currentData = json["current"] as? [String: Any],
                  let wmoCode = currentData["weather_code"] as? Int,
                  let temp = currentData["temperature_2m"] as? Double,
                  let windSpeed = currentData["wind_speed_10m"] as? Double,
                  let windDir = currentData["wind_direction_10m"] as? Double,
                  let humidity = currentData["relative_humidity_2m"] as? Int
            else { return }

            current = WeatherData(
                condition: .from(wmoCode: wmoCode),
                temperature: temp,
                windSpeed: windSpeed,
                windDirection: windDir,
                humidity: humidity,
                timestamp: Date(),
                coordinate: coordinate
            )
        } catch {
            // Silently fail — weather is decorative, not critical
        }
    }
}
