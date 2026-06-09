//
//  JourneyTrackingPreset.swift
//  StreetStamps
//
//  表现层：把"追踪模式选择"统一成 3 档预设。
//  每档映射到已有的 (TrackingMode, DailyTrackingPrecision) 组合，
//  不引入新的追踪行为，也不改动 journey 的持久化格式。
//
//  - sport         → .sport            （高精度运动，~2h）
//  - daily         → .daily + 高精度    （平衡，~4h）
//  - dailySaving   → .daily + 低精度    （省电，12h+，即原"省电记录"开关）
//

import Foundation

enum JourneyTrackingPreset: String, CaseIterable, Identifiable {
    case sport
    case daily
    case dailySaving

    var id: String { rawValue }

    /// 该预设对应的底层追踪模式（写入 journey.trackingMode）。
    var trackingMode: TrackingMode {
        switch self {
        case .sport: return .sport
        case .daily, .dailySaving: return .daily
        }
    }

    /// 该预设对应的后台精度（写入全局 AppSettings.dailyTrackingPrecision）。
    /// 注意：sport 模式忽略该值（TrackingService 内 early-return），
    /// 因此选择 sport 时不应覆盖用户的省电偏好 —— 见 `precisionToWrite`。
    var dailyPrecision: DailyTrackingPrecision {
        switch self {
        case .sport, .daily: return .highPrecision
        case .dailySaving: return .lowPrecision
        }
    }

    /// 应用该预设时需要写入的 precision。
    /// sport 不写（保留用户原有省电偏好），daily/dailySaving 显式写入。
    var precisionToWrite: DailyTrackingPrecision? {
        switch self {
        case .sport: return nil
        case .daily: return .highPrecision
        case .dailySaving: return .lowPrecision
        }
    }

    /// 从 journey 的 mode + 全局 precision 反解出当前激活的预设。
    static func resolve(mode: TrackingMode, precision: DailyTrackingPrecision) -> JourneyTrackingPreset {
        switch mode {
        case .sport:
            return .sport
        case .daily:
            return precision == .lowPrecision ? .dailySaving : .daily
        }
    }

    // MARK: - Presentation

    var icon: String {
        switch self {
        case .sport: return "bolt.fill"
        case .daily: return "figure.walk"
        case .dailySaving: return "leaf.fill"
        }
    }

    var titleKey: String {
        switch self {
        case .sport: return "lockscreen_sport_mode"
        case .daily: return "lockscreen_daily_mode"
        case .dailySaving: return "tracking_preset_saving_title"
        }
    }

    var descKey: String {
        switch self {
        case .sport: return "sport_mode_desc"
        case .daily: return "daily_mode_desc"
        case .dailySaving: return "tracking_preset_saving_desc"
        }
    }
}
