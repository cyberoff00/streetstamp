//
//  TrackingActivityAttributes.swift
//  StreetStamps
//
//  Live Activity 数据结构（与 Widget Extension 共享）
//  注意：此文件需要与 StreetStampsWidgets/TrackingLiveActivity.swift 中的定义保持一致
//

import Foundation
import ActivityKit

struct TrackingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var elapsedSeconds: Int
        var isTracking: Bool
        var isPaused: Bool
        var memoriesCount: Int
    }
    
    // 静态属性（活动开始时设置，不会改变）
    var trackingMode: String // "sport" or "daily"
    var startTime: Date
}
