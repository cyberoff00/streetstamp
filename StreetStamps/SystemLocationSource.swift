//
//  SystemLocationSource.swift
//  StreetStamps
//
//  修改版：支持后台追踪权限
//

import Foundation
import CoreLocation
import Combine
import UIKit

final class SystemLocationSource: NSObject, LocationSource, CLLocationManagerDelegate {
    
    private let manager = CLLocationManager()
    private let subject = PassthroughSubject<CLLocation, Never>()
    private let authSubject = CurrentValueSubject<CLAuthorizationStatus, Never>(.notDetermined)

    private var pendingSingleLocationRequest = false
    private var passiveActive = false
    private var passiveAnchorLocation: CLLocation?
    private var passiveAnchorTimestamp: Date = .distantPast
    private var passivePauseCount = 0
    private var passiveResumeCount = 0
    private var passiveSignificantChangeCount = 0
    private var passiveVisitCount = 0
    private var lastPauseDate: Date?

    var locationPublisher: AnyPublisher<CLLocation, Never> { subject.eraseToAnyPublisher() }
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }
    var authorizationPublisher: AnyPublisher<CLAuthorizationStatus, Never> { authSubject.eraseToAnyPublisher() }
    
    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        
        authSubject.send(manager.authorizationStatus)
        
        // 默认（Idle）：不做后台持续定位
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
    }
    
    // MARK: - Permission
    
    func requestPermissionIfNeeded() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func requestSingleLocation() {
        pendingSingleLocationRequest = true
        stop()

        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = false

        let status = manager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            pendingSingleLocationRequest = false
        }
    }
    
    /// ✅ 新增：显式请求Always权限（用于开始Journey时）
    func requestAlwaysAuthorizationIfNeeded() {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        } else if status == .notDetermined {
            // 先请求WhenInUse
            manager.requestWhenInUseAuthorization()
        }
    }
    
    func start() { startHighPower() }
    
    func stop() {
        #if DEBUG
        if passiveActive {
            print("📍 [Passive] stopping — stats: pauses=\(passivePauseCount) resumes=\(passiveResumeCount) sigChanges=\(passiveSignificantChangeCount) visits=\(passiveVisitCount)")
        }
        #endif
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        manager.allowsBackgroundLocationUpdates = false
        passiveActive = false
        passiveAnchorLocation = nil
        passiveAnchorTimestamp = .distantPast
    }

    /// Ask CoreLocation for one immediate sample after switching mode.
    private func requestImmediateLocationRefresh() {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        manager.requestLocation()
    }
    
    // MARK: - Power Modes
    
    /// ✅ 高功耗前台追踪（运动模式专用）
    func startHighPower() {
        stop()
        
        // ✅ 关键修改：前台追踪时也允许后台更新，这样进入后台不会中断
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true  // ✅ 显示蓝条提示用户
        
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        
        manager.startUpdatingLocation()
        requestImmediateLocationRefresh()
    }
    
    /// ✅ 高功耗前台追踪（日常模式专用，稍低精度）
    func startHighPowerDaily() {
        stop()
        
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
        
        manager.startUpdatingLocation()
        requestImmediateLocationRefresh()
    }
    
    /// 前台静止/低功耗模式
    func startForegroundStationary() {
        stop()

        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = false
        manager.activityType = .fitness

        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20

        manager.startUpdatingLocation()
        requestImmediateLocationRefresh()
    }
    
    /// Idle低功耗模式
    func startLowPower() {
        stop()
    }

    /// Passive lifelog mode with dynamic moving/stationary adaptation.
    /// Starts in stationary profile; upgrades precision when movement is detected,
    /// then calms back down when the user stops. `pausesLocationUpdatesAutomatically`
    /// stays true so iOS can fully pause GPS during extended stillness.
    /// Significant location changes + visit monitoring act as fallback wakeups
    /// when iOS pauses regular updates.
    func startPassiveLifelog() {
        stop()

        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = false

        passiveActive = true
        passiveAnchorLocation = nil
        passiveAnchorTimestamp = .distantPast
        passivePauseCount = 0
        passiveResumeCount = 0
        passiveSignificantChangeCount = 0
        passiveVisitCount = 0
        lastPauseDate = nil

        applyPassiveProfile(for: .stationary)
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
        requestImmediateLocationRefresh()
        #if DEBUG
        print("📍 [Passive] started: updatingLocation + significantChange + visits")
        #endif
    }

    private func applyPassiveProfile(for state: PassiveLocationState) {
        let profile = PassiveLocationProfile.profile(for: state)
        manager.activityType = profile.activityType
        manager.desiredAccuracy = profile.desiredAccuracy
        manager.distanceFilter = profile.distanceFilter
    }

    /// Evaluate each incoming location and switch between moving/stationary profiles.
    private func adaptPassiveIfNeeded(for loc: CLLocation) {
        guard passiveActive else { return }
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 150 else { return }

        if passiveAnchorLocation == nil {
            passiveAnchorLocation = loc
            passiveAnchorTimestamp = loc.timestamp
            return
        }

        guard let anchor = passiveAnchorLocation else { return }
        let dt = loc.timestamp.timeIntervalSince(passiveAnchorTimestamp)
        let moved = loc.distance(from: anchor)
        let speed = max(loc.speed, 0)

        let isCurrentlyMoving = manager.desiredAccuracy < kCLLocationAccuracyHundredMeters

        if isCurrentlyMoving {
            // Active → calm down when stationary for 2.5 min
            if dt >= 150, moved < 30, speed < 0.8 {
                applyPassiveProfile(for: .stationary)
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            } else if dt >= 6 * 60 {
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            }
        } else {
            // Calmed → activate when significant movement detected
            if moved >= 50 || speed >= 1.2 {
                applyPassiveProfile(for: .moving)
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            } else if dt >= 10 * 60 {
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            }
        }
    }
    
    /// ✅ 后台平衡模式（运动模式进入后台）
    func startBackgroundBalanced() {
        stop()
        
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .fitness
        
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        
        manager.startUpdatingLocation()
        requestImmediateLocationRefresh()
    }
    
    /// ✅ 后台高保真模式（确保后台追踪不中断）
    func startBackgroundHighFidelity() {
        stop()
        
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .fitness
        
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        
        manager.startUpdatingLocation()
        requestImmediateLocationRefresh()
    }
    
    /// Daily high-precision background: better route quality, GPS stays active.
    func startBackgroundDailyHighPrecision() {
        stop()

        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .fitness

        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15

        manager.startUpdatingLocation()
        requestImmediateLocationRefresh()
    }

    /// ✅ 后台省电模式（日常低精度进入后台）
    func startBackgroundPowerSaving() {
        stop()

        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .otherNavigation

        manager.desiredAccuracy = 30
        manager.distanceFilter = 50

        manager.startUpdatingLocation()
        requestImmediateLocationRefresh()
    }

    /// In-place transition to power-saving parameters WITHOUT calling stop().
    /// This preserves the existing background location session under WhenInUse
    /// authorization, avoiding the iOS session revocation that stop() causes.
    func transitionToBackgroundPowerSaving() {
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .otherNavigation
        manager.desiredAccuracy = 30
        manager.distanceFilter = 50
    }

    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            if passiveActive, let pauseDate = lastPauseDate {
                // This update arrived after a pause — likely from significant-change fallback.
                passiveSignificantChangeCount += 1
                lastPauseDate = nil
                #if DEBUG
                let gap = loc.timestamp.timeIntervalSince(pauseDate)
                print("📍 [Passive] post-pause didUpdateLocations: gap=\(String(format: "%.0f", gap))s acc=\(String(format: "%.0f", loc.horizontalAccuracy))m sigCount=\(passiveSignificantChangeCount)")
                #endif
            }
            adaptPassiveIfNeeded(for: loc)
            subject.send(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let coordinate = visit.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }

        let timestamp: Date
        if visit.departureDate != Date.distantFuture {
            timestamp = visit.departureDate
        } else if visit.arrivalDate != Date.distantPast {
            timestamp = visit.arrivalDate
        } else {
            timestamp = Date()
        }

        if passiveActive {
            passiveVisitCount += 1
            #if DEBUG
            let kind = visit.departureDate != Date.distantFuture ? "departure" : "arrival"
            print("📍 [Passive] didVisit #\(passiveVisitCount): \(kind) acc=\(String(format: "%.0f", visit.horizontalAccuracy))m coord=(\(String(format: "%.4f", coordinate.latitude)),\(String(format: "%.4f", coordinate.longitude)))")
            #endif
        }

        let synthesized = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: max(visit.horizontalAccuracy, 120),
            verticalAccuracy: -1,
            timestamp: timestamp
        )
        subject.send(synthesized)
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        passivePauseCount += 1
        lastPauseDate = Date()
        #if DEBUG
        print("📍 [Passive] ⚠️ iOS PAUSED location updates (pause #\(passivePauseCount)). Restarting...")
        #endif
        guard passiveActive else { return }
        manager.startUpdatingLocation()
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        passiveResumeCount += 1
        #if DEBUG
        let pauseGap: String
        if let pd = lastPauseDate {
            pauseGap = String(format: "%.0f", Date().timeIntervalSince(pd)) + "s"
        } else {
            pauseGap = "n/a"
        }
        print("📍 [Passive] ✅ iOS RESUMED location updates (resume #\(passiveResumeCount), pauseGap=\(pauseGap))")
        #endif
        lastPauseDate = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("📍 [Passive] error: \(error)")
        #endif
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authSubject.send(manager.authorizationStatus)
        if pendingSingleLocationRequest {
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                pendingSingleLocationRequest = false
                self.manager.requestLocation()
            case .denied, .restricted:
                pendingSingleLocationRequest = false
            default:
                break
            }
        }
    }

}
