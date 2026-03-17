//
//  MockLocationSource.swift
//  StreetStamps
//
//  Created by Claire Yang on 14/01/2026.
//

import Foundation
import CoreLocation
import Combine

#if DEBUG
final class MockLocationSource: LocationSource {
    private let subject = PassthroughSubject<CLLocation, Never>()
    private let headingSubject = CurrentValueSubject<Double, Never>(0)
    var locationPublisher: AnyPublisher<CLLocation, Never> { subject.eraseToAnyPublisher() }
    var headingPublisher: AnyPublisher<Double, Never> { headingSubject.eraseToAnyPublisher() }

    var authorizationStatus: CLAuthorizationStatus { .authorizedAlways }

    private let player = MockRoutePlayer()

    func requestPermissionIfNeeded() {}
    func requestSingleLocation() {}

    func start() {
        // mock 不需要 start 系统定位
    }

    func stop() {
        player.stop()
    }

    /// 播放一段轨迹
    func playPath(
        points: [CLLocationCoordinate2D],
        pointsPerSecond: Double = 2.0,
        fixedSpeed: CLLocationSpeed? = 230,
        accuracy: CLLocationAccuracy = 80,
        altitude: CLLocationDistance = 9000
    ) {
        player.pointsPerSecond = pointsPerSecond
        player.accuracy = accuracy
        player.altitude = altitude
        player.fixedSpeed = fixedSpeed
        player.load(points: points)
        player.start { [weak self] loc in
            self?.subject.send(loc)
            self?.headingSubject.send(0)
        }
    }
}
#endif

#if DEBUG
import Foundation
import CoreLocation
import UIKit

/// Debug-only: 用 Timer 播放一段坐标序列，喂出 CLLocation
final class MockRoutePlayer {
    private var timer: Timer?
    private var idx = 0
    private var points: [CLLocationCoordinate2D] = []

    var pointsPerSecond: Double = 2.0
    var altitude: CLLocationDistance = 9000
    var accuracy: CLLocationAccuracy = 80
    var fixedSpeed: CLLocationSpeed? = nil

    func load(points: [CLLocationCoordinate2D]) {
        self.points = points
        self.idx = 0
    }

    func start(push: @escaping (CLLocation) -> Void) {
        stop()
        guard !points.isEmpty else { return }

        let interval = max(0.05, 1.0 / max(0.1, pointsPerSecond))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.idx < self.points.count else { self.stop(); return }

            let c = self.points[self.idx]
            self.idx += 1

            let loc = CLLocation(
                coordinate: c,
                altitude: self.altitude,
                horizontalAccuracy: self.accuracy,
                verticalAccuracy: 50,
                course: -1,
                speed: self.fixedSpeed ?? -1,
                timestamp: Date()
            )
            push(loc)
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
