import SwiftUI
import CoreLocation

// MARK: - Weather Overlay

/// Composites weather effects (rain, fog, lightning) based on real-time weather data.
/// Designed to be layered on top of a map in a ZStack.
struct WeatherOverlayView: View {
    @ObservedObject var weatherService: WeatherService
    let location: CLLocation?

    @State private var didAppear = false

    var body: some View {
        let weather = weatherService.effectiveWeather
        let condition = weatherService.effectiveCondition

        ZStack {
            // Atmospheric tint
            if condition.isRaining {
                Color.black
                    .opacity(atmosphericDarkening(for: condition))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Fog layer (behind rain)
            if condition == .fog || condition.isRaining {
                FogOverlayView(
                    opacity: condition == .fog ? 0.8 : condition.rainIntensity * 0.4
                )
            }

            // Rain layer
            if condition.isRaining {
                RainEffectView(
                    intensity: condition.rainIntensity,
                    windAngle: windAngleDegrees(from: weather)
                )
            }

            // Lightning (thunderstorm only)
            if condition == .thunderstorm {
                LightningFlashView(active: true)
            }

            // Snow (future — placeholder for extensibility)
            // if condition.isSnowing { SnowEffectView(...) }
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
        switch condition {
        case .drizzle:      return 0.06
        case .rain:         return 0.10
        case .heavyRain:    return 0.15
        case .thunderstorm: return 0.20
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
    func weatherOverlay(service: WeatherService, location: CLLocation?) -> some View {
        self.overlay {
            WeatherOverlayView(weatherService: service, location: location)
        }
    }
}
