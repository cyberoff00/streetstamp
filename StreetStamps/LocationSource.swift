//
//  LocationSource.swift
//  StreetStamps
//
//  Created by Claire Yang on 14/01/2026.
//
import Foundation
import CoreLocation
import Combine

protocol LocationSource: AnyObject {
    var locationPublisher: AnyPublisher<CLLocation, Never> { get }
    var headingPublisher: AnyPublisher<Double, Never> { get }
    var authorizationStatus: CLAuthorizationStatus { get }

    func requestPermissionIfNeeded()
    func requestSingleLocation()
    func start()
    func stop()
}
