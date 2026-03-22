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

    private enum PassiveState {
        case none
        case highPrecisionActive
        case highPrecisionCalmed
        case lowPrecisionActive
        case lowPrecisionCalmed
    }
    private var passiveState: PassiveState = .none
    private var passiveAnchorLocation: CLLocation?
    private var passiveAnchorTimestamp: Date = .distantPast
    private var pendingSingleLocationRequest = false
    private var passiveMode: LifelogBackgroundMode?
    
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
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        // ✅ 停止时关闭后台更新
        manager.allowsBackgroundLocationUpdates = false
        passiveState = .none
        passiveMode = nil
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
        
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        
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

    /// Passive high precision mode for Lifelog when app has no active journey.
    /// Keeps continuity close to foreground while capping battery by calming down when stationary.
    func startPassiveHighPrecision() {
        stop()

        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
        passiveMode = .highPrecision

        passiveState = .highPrecisionCalmed
        passiveAnchorLocation = nil
        passiveAnchorTimestamp = .distantPast

        applyPassiveProfile(for: .stationary)
        manager.startUpdatingLocation()
        requestImmediateLocationRefresh()
    }

    /// Passive low precision mode for Lifelog with battery priority.
    func startPassiveLowPrecision() {
        stop()

        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = false
        passiveMode = .lowPrecision

        passiveState = .lowPrecisionCalmed
        passiveAnchorLocation = nil
        passiveAnchorTimestamp = .distantPast

        applyPassiveProfile(for: .stationary)
        manager.startUpdatingLocation()
        requestImmediateLocationRefresh()
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
    
    /// ✅ 后台省电模式（日常模式进入后台）
    func startBackgroundPowerSaving() {
        stop()
        
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true  // 允许系统暂停
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .otherNavigation
        
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 50  // 50米才更新
        
        manager.startUpdatingLocation()
        requestImmediateLocationRefresh()
    }

    private func applyPassiveProfile(for state: PassiveLocationState) {
        guard let passiveMode else { return }
        let profile = PassiveLocationProfile.profile(for: passiveMode, state: state)
        manager.activityType = profile.activityType
        manager.desiredAccuracy = profile.desiredAccuracy
        manager.distanceFilter = profile.distanceFilter
    }

    private func adaptPassiveHighPrecisionIfNeeded(for loc: CLLocation) {
        guard passiveState != .none else { return }
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

        switch passiveState {
        case .highPrecisionCalmed:
            if moved >= 30 || speed >= 1.2 {
                passiveState = .highPrecisionActive
                applyPassiveProfile(for: .moving)
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            } else if dt >= 10 * 60 {
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            }
        case .highPrecisionActive:
            if dt >= 2 * 60, moved < 25, speed < 0.8 {
                passiveState = .highPrecisionCalmed
                applyPassiveProfile(for: .stationary)
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            } else if dt >= 6 * 60 {
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            }
        case .lowPrecisionCalmed:
            if moved >= 60 || speed >= 1.6 {
                passiveState = .lowPrecisionActive
                applyPassiveProfile(for: .moving)
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            } else if dt >= 12 * 60 {
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            }
        case .lowPrecisionActive:
            if dt >= 3 * 60, moved < 35, speed < 0.8 {
                passiveState = .lowPrecisionCalmed
                applyPassiveProfile(for: .stationary)
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            } else if dt >= 8 * 60 {
                passiveAnchorLocation = loc
                passiveAnchorTimestamp = loc.timestamp
            }
        case .none:
            break
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            adaptPassiveHighPrecisionIfNeeded(for: loc)
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

        let synthesized = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: max(visit.horizontalAccuracy, 120),
            verticalAccuracy: -1,
            timestamp: timestamp
        )
        subject.send(synthesized)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("SystemLocationSource error: \(error)")
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
