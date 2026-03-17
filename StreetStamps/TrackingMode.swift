//
//  TrackingMode.swift
//  StreetStamps
//
//  运动模式 vs 日常模式 配置
//

import Foundation
import CoreLocation
import SwiftUI

struct MapTrackingModePillPresentation: Equatable {
    let symbolName: String
    let iconFontSize: CGFloat
    let foregroundOpacity: Double
}

/// 追踪模式：运动 vs 日常
enum TrackingMode: String, Codable, CaseIterable {
    case sport   // 运动模式：高精度，适合跑步/骑行
    case daily   // 日常模式：省电，适合8小时daytrip
    
    var displayName: String {
        switch self {
        case .sport: return L10n.t("tracking_mode_sport")
        case .daily: return L10n.t("tracking_mode_daily")
        }
    }
    
    var icon: String {
        switch self {
        case .sport: return "figure.run"
        case .daily: return "figure.walk.motion"
        }
    }

    var mapPillPresentation: MapTrackingModePillPresentation {
        switch self {
        case .sport:
            return MapTrackingModePillPresentation(
                symbolName: "figure.run",
                iconFontSize: 12,
                foregroundOpacity: 0.82
            )
        case .daily:
            return MapTrackingModePillPresentation(
                symbolName: "figure.walk.motion",
                iconFontSize: 12,
                foregroundOpacity: 0.82
            )
        }
    }
}

/// 追踪模式配置参数
struct TrackingModeConfig {
    // MARK: - 采点参数
    let foregroundMinDistance: Double      // 前台最小采点距离
    let backgroundMinDistance: Double      // 后台最小采点距离
    let maxAcceptableAccuracy: Double      // 最大可接受精度
    let lockAccuracy: Double               // GPS锁定精度阈值
    
    // MARK: - 平滑参数
    let enableOneEuroFilter: Bool          // 是否启用OneEuro滤波
    let oneEuroMinCutoff: Double           // OneEuro最小截止频率
    let oneEuroBeta: Double                // OneEuro beta参数
    
    // MARK: - 转弯检测
    let turnKeepAngle: Double              // 转弯保留角度阈值
    
    // MARK: - Gap检测
    let gapSecondsThreshold: TimeInterval  // 时间间隙阈值
    let gapDistanceThreshold: Double       // 距离间隙阈值
    
    // MARK: - 静止检测
    let stationaryMinMoveMeters: Double    // 静止状态最小移动距离
    let stationarySpeedThreshold: Double   // 静止速度阈值
    let stationaryHoldSeconds: TimeInterval // 静止保持时间后切换省电模式
    
    // MARK: - 存盘策略
    let deltaPersistInterval: TimeInterval // Delta持久化间隔
    let enableStorageDownsample: Bool      // 是否启用存盘时抽稀
    let storageMaxPointsPerHour: Int       // 存盘时每小时最大点数
    
    // MARK: - 渲染
    let renderDebounceInterval: TimeInterval // 渲染防抖间隔
    
    // MARK: - 预设配置
    
    /// 运动模式：高精度，适合跑步/骑行（类似Nike Run/Keep）
    static let sport = TrackingModeConfig(
        foregroundMinDistance: 3,           // 3米采一次（高密度）
        backgroundMinDistance: 5,
        maxAcceptableAccuracy: 30,          // 要求精度更高
        lockAccuracy: 15,
        
        enableOneEuroFilter: true,          // 启用平滑
        oneEuroMinCutoff: 1.0,
        oneEuroBeta: 0.05,
        
        turnKeepAngle: 15,                  // 更敏感的转弯检测
        
        gapSecondsThreshold: 30,
        gapDistanceThreshold: 500,
        
        stationaryMinMoveMeters: 3,
        stationarySpeedThreshold: 0.3,
        stationaryHoldSeconds: 30,          // 运动模式下静止30秒才切省电
        
        deltaPersistInterval: 60,           // 1分钟存一次（更频繁）
        enableStorageDownsample: false,     // 不抽稀，保留完整轨迹
        storageMaxPointsPerHour: 99999,
        
        renderDebounceInterval: 0.16        // 约6Hz渲染，保留实时感同时降低前台重绘
    )
    
    /// 日常模式：省电，适合8小时daytrip
    static let daily = TrackingModeConfig(
        foregroundMinDistance: 12,          // 12米采一次（低密度）
        backgroundMinDistance: 25,
        maxAcceptableAccuracy: 80,          // 允许更低精度
        lockAccuracy: 35,
        
        enableOneEuroFilter: false,         // 日常不需要高精度平滑
        oneEuroMinCutoff: 1.2,
        oneEuroBeta: 0.08,
        
        turnKeepAngle: 25,                  // 更宽松的转弯检测
        
        gapSecondsThreshold: 60,            // 1分钟才算gap
        gapDistanceThreshold: 1500,
        
        stationaryMinMoveMeters: 15,        // 15米内算静止
        stationarySpeedThreshold: 0.8,
        stationaryHoldSeconds: 10,          // 10秒静止就切省电
        
        deltaPersistInterval: 180,          // 3分钟存一次
        enableStorageDownsample: true,      // 启用存盘抽稀
        storageMaxPointsPerHour: 200,       // 每小时最多200点
        
        renderDebounceInterval: 0.5         // 2Hz渲染，更适合日常长时记录
    )
    
    /// 根据模式获取配置
    static func config(for mode: TrackingMode) -> TrackingModeConfig {
        switch mode {
        case .sport: return .sport
        case .daily: return .daily
        }
    }
}

// MARK: - 根据TravelMode动态调整参数（用于日常模式下多交通方式）

extension TrackingModeConfig {
    /// 日常模式下，根据检测到的交通方式动态调整参数
    func adjusted(for travelMode: TravelMode) -> TrackingModeConfig {
        // 运动模式不做动态调整
        guard self.enableStorageDownsample else { return self }
        
        switch travelMode {
        case .walk:
            return TrackingModeConfig(
                foregroundMinDistance: 8,
                backgroundMinDistance: 15,
                maxAcceptableAccuracy: 60,
                lockAccuracy: 30,
                enableOneEuroFilter: false,
                oneEuroMinCutoff: oneEuroMinCutoff,
                oneEuroBeta: oneEuroBeta,
                turnKeepAngle: 22,
                gapSecondsThreshold: 45,
                gapDistanceThreshold: 800,
                stationaryMinMoveMeters: 10,
                stationarySpeedThreshold: 0.6,
                stationaryHoldSeconds: 8,
                deltaPersistInterval: deltaPersistInterval,
                enableStorageDownsample: true,
                storageMaxPointsPerHour: 300,
                renderDebounceInterval: 0.2
            )
            
        case .run:
            // 跑步时即使在日常模式也提高精度
            return TrackingModeConfig(
                foregroundMinDistance: 5,
                backgroundMinDistance: 8,
                maxAcceptableAccuracy: 45,
                lockAccuracy: 25,
                enableOneEuroFilter: true,  // 跑步时启用平滑
                oneEuroMinCutoff: 1.1,
                oneEuroBeta: 0.06,
                turnKeepAngle: 18,
                gapSecondsThreshold: 30,
                gapDistanceThreshold: 500,
                stationaryMinMoveMeters: 5,
                stationarySpeedThreshold: 0.4,
                stationaryHoldSeconds: 15,
                deltaPersistInterval: 90,
                enableStorageDownsample: false,
                storageMaxPointsPerHour: 800,
                renderDebounceInterval: 0.1
            )
            
        case .transit:
            return TrackingModeConfig(
                foregroundMinDistance: 15,
                backgroundMinDistance: 30,
                maxAcceptableAccuracy: 80,
                lockAccuracy: 40,
                enableOneEuroFilter: false,
                oneEuroMinCutoff: oneEuroMinCutoff,
                oneEuroBeta: oneEuroBeta,
                turnKeepAngle: 20,
                gapSecondsThreshold: 60,
                gapDistanceThreshold: 1200,
                stationaryMinMoveMeters: 20,
                stationarySpeedThreshold: 1.0,
                stationaryHoldSeconds: 8,
                deltaPersistInterval: deltaPersistInterval,
                enableStorageDownsample: true,
                storageMaxPointsPerHour: 180,
                renderDebounceInterval: 0.25
            )

        case .bike:
            return TrackingModeConfig(
                foregroundMinDistance: 9,
                backgroundMinDistance: 16,
                maxAcceptableAccuracy: 65,
                lockAccuracy: 30,
                enableOneEuroFilter: true,
                oneEuroMinCutoff: 1.05,
                oneEuroBeta: 0.05,
                turnKeepAngle: 18,
                gapSecondsThreshold: 45,
                gapDistanceThreshold: 900,
                stationaryMinMoveMeters: 12,
                stationarySpeedThreshold: 0.9,
                stationaryHoldSeconds: 12,
                deltaPersistInterval: 120,
                enableStorageDownsample: false,
                storageMaxPointsPerHour: 500,
                renderDebounceInterval: 0.12
            )
            
        case .drive, .motorcycle:
            return TrackingModeConfig(
                foregroundMinDistance: 25,
                backgroundMinDistance: 50,
                maxAcceptableAccuracy: 100,
                lockAccuracy: 50,
                enableOneEuroFilter: false,
                oneEuroMinCutoff: oneEuroMinCutoff,
                oneEuroBeta: oneEuroBeta,
                turnKeepAngle: 18,
                gapSecondsThreshold: 90,
                gapDistanceThreshold: 2000,
                stationaryMinMoveMeters: 30,
                stationarySpeedThreshold: 1.5,
                stationaryHoldSeconds: 5,
                deltaPersistInterval: deltaPersistInterval,
                enableStorageDownsample: true,
                storageMaxPointsPerHour: 120,
                renderDebounceInterval: 0.3
            )
            
        case .flight:
            return TrackingModeConfig(
                foregroundMinDistance: 500,
                backgroundMinDistance: 1000,
                maxAcceptableAccuracy: 300,
                lockAccuracy: 150,
                enableOneEuroFilter: false,
                oneEuroMinCutoff: oneEuroMinCutoff,
                oneEuroBeta: oneEuroBeta,
                turnKeepAngle: 45,
                gapSecondsThreshold: 180,
                gapDistanceThreshold: 10000,
                stationaryMinMoveMeters: 100,
                stationarySpeedThreshold: 5.0,
                stationaryHoldSeconds: 60,
                deltaPersistInterval: 300,
                enableStorageDownsample: true,
                storageMaxPointsPerHour: 30,
                renderDebounceInterval: 0.5
            )
            
        case .unknown:
            return self
        }
    }
}
