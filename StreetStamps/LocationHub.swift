//
//  LocationHub.swift
//  StreetStamps
//
//  Created by Claire Yang on 14/01/2026.
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationHub: ObservableObject {

    // MARK: - Persisted last known location (fast UI fallback)

    private struct PersistedLocation: Codable {
        let lat: Double
        let lon: Double
        let altitude: Double
        let hAcc: Double
        let vAcc: Double
        let speed: Double
        let course: Double
        let timestamp: Date
    }

    private enum PersistKeys {
        static let lastKnownLocation = "LocationHub.lastKnownLocation.v1"
    }

    /// Last known location restored from disk (if any). Useful for fast UI while waiting for first GPS fix.
    var lastKnownLocation: CLLocation? {
        guard let data = UserDefaults.standard.data(forKey: PersistKeys.lastKnownLocation) else { return nil }
        guard let p = try? JSONDecoder().decode(PersistedLocation.self, from: data) else { return nil }
        let coord = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        return CLLocation(
            coordinate: coord,
            altitude: p.altitude,
            horizontalAccuracy: p.hAcc,
            verticalAccuracy: p.vAcc,
            course: p.course,
            speed: p.speed,
            timestamp: p.timestamp
        )
    }

    private func persistLastKnown(_ loc: CLLocation) {
        let p = PersistedLocation(
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            altitude: loc.altitude,
            hAcc: loc.horizontalAccuracy,
            vAcc: loc.verticalAccuracy,
            speed: loc.speed,
            course: loc.course,
            timestamp: loc.timestamp
        )
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: PersistKeys.lastKnownLocation)
        }
    }

    enum Mode {
        case system
        #if DEBUG
        case mock
        #endif
    }

    static let shared = LocationHub()

    // 当前模式（system / mock）
    @Published private(set) var mode: Mode = .system

    // 给全 App 用的“当前定位”
    @Published private(set) var currentLocation: CLLocation?

    /// ✅ ISO2 country code for China GCJ gating.
    /// - "CN" => apply WGS->GCJ for Map rendering
    /// - nil/others => no offset
    @Published private(set) var countryISO2: String? = nil

    /// Expose auth + fix state for UI.
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var headingDegrees: Double = 0
    @Published private(set) var lastLocationAccuracy: CLLocationAccuracy?
    @Published private(set) var lastLocationUpdateTime: Date?
    @Published private(set) var isFirstFixReady: Bool = false

    // 方便外部判断：是否在用 mock
    var isUsingMock: Bool {
        #if DEBUG
        return mode == .mock
        #else
        return false
        #endif
    }

    // Sources
    private let systemSource = SystemLocationSource()

    #if DEBUG
    private let mockSource = MockLocationSource()
    #endif

    private var current: LocationSource
    private var cancellables: Set<AnyCancellable> = []

    // 全 App 统一输出流（可选）
    let locationStream = PassthroughSubject<CLLocation, Never>()

    // MARK: - Country resolve (extreme: fast bbox + low-frequency geocode)

    private let geocoder = CLGeocoder()
    private var geocodeInFlight: Bool = false
    private var lastGeocodeAt: Date = .distantPast
    private var lastGeocodedRegionKey: String = ""

    /// Low frequency; avoid hammering geocoder.
    private let geocodeMinInterval: TimeInterval = 30 * 60 // 30 min

    private init() {
        self.current = systemSource
        bindCurrentSource()
    }

    private func bindCurrentSource() {
        cancellables.removeAll()

        // auth status (system only)
        if current === systemSource {
            authorizationStatus = systemSource.authorizationStatus
            systemSource.authorizationPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    self?.authorizationStatus = status
                }
                .store(in: &cancellables)
        } else {
            authorizationStatus = .authorizedAlways
        }

        current.locationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                guard let self else { return }

                self.currentLocation = loc
                self.lastLocationAccuracy = loc.horizontalAccuracy
                self.lastLocationUpdateTime = loc.timestamp
                if !self.isFirstFixReady { self.isFirstFixReady = true }
                self.persistLastKnown(loc)
                self.locationStream.send(loc)

                // ✅ (1) fast gating immediately
                let fast = self.fastCountryISO2Guess(for: loc.coordinate)
                if fast != self.countryISO2 {
                    self.countryISO2 = fast
                }

                // ✅ (2) low-frequency authoritative correction
                self.maybeReverseGeocodeCountry(for: loc)
            }
            .store(in: &cancellables)

        current.headingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] heading in
                guard let self else { return }
                let h = heading.truncatingRemainder(dividingBy: 360)
                headingDegrees = h >= 0 ? h : (h + 360)
            }
            .store(in: &cancellables)
    }

    // MARK: - Fast CN bbox guess (cheap)

    private func fastCountryISO2Guess(for coord: CLLocationCoordinate2D) -> String? {
        // Mainland China rough bbox (good enough for fast gating; geocode later corrects)
        let lat = coord.latitude
        let lon = coord.longitude
        let inCN = (lat >= 18.0 && lat <= 54.0 && lon >= 73.0 && lon <= 135.0)
        return inCN ? "CN" : nil
    }

    private func geocodeRegionKey(for coord: CLLocationCoordinate2D) -> String {
        let latB = Int(coord.latitude.rounded(.towardZero))
        let lonB = Int(coord.longitude.rounded(.towardZero))
        return "\(latB)_\(lonB)"
    }

    private func maybeReverseGeocodeCountry(for loc: CLLocation) {
        // Don't geocode too early / too noisy
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 150 else { return }
        if isUsingMock { return }

        let now = Date()
        guard now.timeIntervalSince(lastGeocodeAt) >= geocodeMinInterval else { return }

        let key = geocodeRegionKey(for: loc.coordinate)
        guard key != lastGeocodedRegionKey else { return }

        guard !geocodeInFlight else { return }
        geocodeInFlight = true

        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self else { return }
            self.geocodeInFlight = false

            guard let pm = placemarks?.first else { return }
            guard let iso = pm.isoCountryCode?.uppercased(), !iso.isEmpty else { return }

            self.lastGeocodeAt = now
            self.lastGeocodedRegionKey = key

            if self.countryISO2 != iso {
                self.countryISO2 = iso
            }
        }
    }

    // MARK: - Basic control

    func requestPermissionIfNeeded() {
        current.requestPermissionIfNeeded()
    }

    /// 默认 start：高功耗（前台精细）
    func start() {
        startRealTime()
    }

    /// 停止当前 source（一般你不需要全局 stop，否则 MainTab 会没定位）
    func stop() {
        current.stop()
    }

    /// ✅ 高功耗：前台精细跟踪
    func startRealTime() {
        #if DEBUG
        if mode == .mock { return } // mock 时不要启动系统定位
        #endif

        if current === systemSource {
            systemSource.startHighPower()
        } else {
            current.start()
        }
    }

    /// ✅ 高功耗：前台精细跟踪（日常模式专用，稍低精度）
    func startRealTimeDaily() {
        #if DEBUG
        if mode == .mock { return }
        #endif

        if current === systemSource {
            systemSource.startHighPowerDaily()
        } else {
            // 非系统 source（mock等）保持原行为
            current.start()
        }
    }


    /// ✅ Foreground stationary: reduce wakeups while user is not moving.
    /// TrackingService will switch into/out of this mode automatically.
    func enterForegroundStationary() {
        #if DEBUG
        if mode == .mock { return }
        #endif

        if current === systemSource {
            systemSource.startForegroundStationary()
        } else {
            current.start()
        }
    }

    /// ✅ 低功耗：后台省电
    func enterLowPower() {
        #if DEBUG
        if mode == .mock { return }
        #endif

        if current === systemSource {
            systemSource.startLowPower()
        } else {
            current.stop()
        }
    }

    /// ✅ Background Balanced: keep more turns with moderate battery usage.
    func enterBackgroundBalanced() {
        #if DEBUG
        if mode == .mock { return }
        #endif

        if current === systemSource {
            systemSource.startBackgroundBalanced()
        } else {
            current.start()
        }
    }

    /// ✅ Background High Fidelity: keep turns as close to foreground as possible.
    func enterBackgroundHighFidelity() {
        #if DEBUG
        if mode == .mock { return }
        #endif

        if current === systemSource {
            systemSource.startBackgroundHighFidelity()
        } else {
            current.start()
        }
    }

    // MARK: - Switch source

    func switchToSystem() {
        current.stop()
        mode = .system
        current = systemSource
        bindCurrentSource()
        current.requestPermissionIfNeeded()
        enterLowPower()
    }

    #if DEBUG
    func switchToMock() {
        current.stop()
        mode = .mock
        current = mockSource
        bindCurrentSource()
        current.start()
    }

    func mockPlayPath(
        points: [CLLocationCoordinate2D],
        pointsPerSecond: Double = 2.0,
        fixedSpeed: CLLocationSpeed? = 230,
        accuracy: CLLocationAccuracy = 80,
        altitude: CLLocationDistance = 9000
    ) {
        if mode != .mock { switchToMock() }

        mockSource.playPath(
            points: points,
            pointsPerSecond: pointsPerSecond,
            fixedSpeed: fixedSpeed,
            accuracy: accuracy,
            altitude: altitude
        )
    }

    func stopMockAndBackToSystem() {
        current.stop()
        switchToSystem()
    }
    #endif
}

extension LocationHub {
    func startHighPower() { startRealTime() }
    func startLowPower() { enterLowPower() }
}
