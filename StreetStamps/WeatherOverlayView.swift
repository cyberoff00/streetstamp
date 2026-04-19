import SwiftUI
import CoreLocation

// MARK: - Weather Overlay

/// Composites weather effects (rain, fog, lightning) based on real-time weather data.
/// Designed to be layered on top of a map in a ZStack.
struct WeatherOverlayView: View {
    @ObservedObject var weatherService: WeatherService
    let location: CLLocation?
    var lightBackground: Bool = false  // true = light map, particles should be dark

    @State private var didAppear = false

    var body: some View {
        let weather = weatherService.effectiveWeather
        let condition = weatherService.effectiveCondition

        ZStack {
            // Atmospheric tint — heavier on light maps for contrast
            if condition.isRaining || condition.isSnowing {
                Color.black
                    .opacity(atmosphericDarkening(for: condition))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Rain layer
            if condition.isRaining {
                RainEffectView(
                    intensity: condition.rainIntensity,
                    windAngle: windAngleDegrees(from: weather),
                    lightBackground: lightBackground
                )
            }

            // Snow layer
            if condition.isSnowing {
                SnowEffectView(
                    intensity: 0.7,
                    windAngle: windAngleDegrees(from: weather),
                    lightBackground: lightBackground
                )
            }

            // Lightning (thunderstorm only)
            if condition == .thunderstorm {
                LightningFlashView(active: true)
            }
        }
        .animation(.easeInOut(duration: 2.0), value: condition)
        .onAppear {
            didAppear = true
            fetchWeather()
        }
        .onChange(of: location?.coordinate.latitude) { _, _ in
            fetchWeather()
        }
    }

    private func fetchWeather() {
        guard let loc = location else { return }
        weatherService.fetchIfNeeded(for: loc)
    }

    private func atmosphericDarkening(for condition: WeatherCondition) -> Double {
        // Light maps need heavier darkening so particles stand out
        let boost: Double = lightBackground ? 0.06 : 0.0
        switch condition {
        case .drizzle:      return 0.06 + boost
        case .rain:         return 0.10 + boost
        case .heavyRain:    return 0.15 + boost
        case .thunderstorm: return 0.20 + boost
        case .snow:         return 0.05 + boost
        default:            return 0.0
        }
    }

    private func windAngleDegrees(from weather: WeatherData?) -> CGFloat {
        guard let weather, weather.windSpeed > 5 else {
            return CGFloat.random(in: 5...15) // subtle default wind
        }
        // Convert meteorological wind direction to visual tilt
        // Wind from west (270) should tilt rain to the right
        let normalized = weather.windDirection.truncatingRemainder(dividingBy: 360)
        let tilt = sin(normalized * .pi / 180) * min(weather.windSpeed / 40.0, 1.0) * 25
        return CGFloat(tilt)
    }
}

// MARK: - Convenience modifier

extension View {
    func weatherOverlay(service: WeatherService, location: CLLocation?, lightBackground: Bool = false) -> some View {
        self.overlay {
            WeatherOverlayView(weatherService: service, location: location, lightBackground: lightBackground)
        }
    }
}
