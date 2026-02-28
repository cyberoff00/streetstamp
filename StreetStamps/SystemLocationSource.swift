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
    private let headingSubject = CurrentValueSubject<Double, Never>(0)
    private let authSubject = CurrentValueSubject<CLAuthorizationStatus, Never>(.notDetermined)
    
    var locationPublisher: AnyPublisher<CLLocation, Never> { subject.eraseToAnyPublisher() }
    var headingPublisher: AnyPublisher<Double, Never> { headingSubject.eraseToAnyPublisher() }
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
        manager.stopUpdatingHeading()
        manager.stopMonitoringSignificantLocationChanges()
        // ✅ 停止时关闭后台更新
        manager.allowsBackgroundLocationUpdates = false
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
        startHeadingUpdatesIfPossible()
        requestImmediateLocationRefresh()
    }
    
    /// ✅ 高功耗前台追踪（日常模式专用，稍低精度）
    func startHighPowerDaily() {
        stop()
        
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        
        manager.desiredAccuracy = kCLLocationAccuracyBest  // 比Navigation稍低
        manager.distanceFilter = 5  // 5米才更新
        
        manager.startUpdatingLocation()
        startHeadingUpdatesIfPossible()
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
        startHeadingUpdatesIfPossible()
        requestImmediateLocationRefresh()
    }
    
    /// Idle低功耗模式
    func startLowPower() {
        stop()

        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = false

        #if targetEnvironment(simulator)
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200
        manager.startUpdatingLocation()
        startHeadingUpdatesIfPossible()
        requestImmediateLocationRefresh()
        return
        #endif

        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 50
            manager.startUpdatingLocation()
            startHeadingUpdatesIfPossible()
            requestImmediateLocationRefresh()
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
        startHeadingUpdatesIfPossible()
        requestImmediateLocationRefresh()
    }
    
    /// ✅ 后台高保真模式（确保后台追踪不中断）
    func startBackgroundHighFidelity() {
        stop()
        
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .fitness
        
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        
        manager.startUpdatingLocation()
        startHeadingUpdatesIfPossible()
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
        manager.distanceFilter = 30  // 30米才更新
        
        manager.startUpdatingLocation()
        startHeadingUpdatesIfPossible()
        requestImmediateLocationRefresh()
    }

    private func startHeadingUpdatesIfPossible() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.headingFilter = 2
        manager.startUpdatingHeading()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            subject.send(loc)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("SystemLocationSource error: \(error)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authSubject.send(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let raw = (newHeading.trueHeading >= 0) ? newHeading.trueHeading : newHeading.magneticHeading
        let h = raw.truncatingRemainder(dividingBy: 360)
        headingSubject.send(h >= 0 ? h : (h + 360))
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }
}
