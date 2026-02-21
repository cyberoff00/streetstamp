//
//  TrackingLiveActivity.swift
//  StreetStampsWidgets
//
//  Live Activity 锁屏/通知栏追踪卡片
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Live Activity Attributes

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

// MARK: - Live Activity Widget

struct TrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingActivityAttributes.self) { context in
            // 锁屏/通知栏 UI
            LockScreenView(
                mode: context.attributes.trackingMode,
                state: context.state
            )
            .activityBackgroundTint(WidgetTheme.cardBg)
            .activitySystemActionForegroundColor(.white)
            
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开状态 - Leading
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.isPaused ? WidgetTheme.mutedText : WidgetTheme.activeGreen)
                            .frame(width: 8, height: 8)
                        
                        Text(context.attributes.trackingMode == "sport" ? "运动" : "日常")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // 展开状态 - Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    if context.attributes.trackingMode == "sport" {
                        HStack(spacing: 8) {
                            // 距离
                            Text(formatDistance(context.state.distanceMeters))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("km")
                                .font(.system(size: 10))
                                .foregroundColor(WidgetTheme.offWhite)
                        }
                    }
                }
                
                // 展开状态 - Center
                DynamicIslandExpandedRegion(.center) {
                    Text(formatDuration(context.state.elapsedSeconds))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // 展开状态 - Bottom
                DynamicIslandExpandedRegion(.bottom) {
                    if context.attributes.trackingMode == "daily" {
                        Button(intent: AddMemoryIntent()) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                Text("添加记忆")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(WidgetTheme.activeGreen)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
            } compactLeading: {
                // 紧凑模式 - 左侧
                Circle()
                    .fill(context.state.isPaused ? WidgetTheme.mutedText : WidgetTheme.activeGreen)
                    .frame(width: 10, height: 10)
                
            } compactTrailing: {
                // 紧凑模式 - 右侧
                if context.attributes.trackingMode == "sport" {
                    Text(formatDistance(context.state.distanceMeters))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text(formatDuration(context.state.elapsedSeconds))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
            } minimal: {
                // 最小模式（当有多个 Live Activity 时）
                Circle()
                    .fill(context.state.isPaused ? WidgetTheme.mutedText : WidgetTheme.activeGreen)
                    .frame(width: 10, height: 10)
            }
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.2f", km)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let mode: String
    let state: TrackingActivityAttributes.ContentState
    
    var body: some View {
        if mode == "sport" {
            SportModeLockScreen(state: state)
        } else {
            DailyModeLockScreen(state: state)
        }
    }
}

// MARK: - Sport Mode Lock Screen

struct SportModeLockScreen: View {
    let state: TrackingActivityAttributes.ContentState
    
    private var formattedDistance: String {
        let km = state.distanceMeters / 1000.0
        return String(format: "%.2f", km)
    }
    
    private var formattedDuration: String {
        let hours = state.elapsedSeconds / 3600
        let minutes = (state.elapsedSeconds % 3600) / 60
        let seconds = state.elapsedSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack(spacing: 8) {
                // Tracking indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.isPaused ? WidgetTheme.mutedText : WidgetTheme.activeGreen)
                        .frame(width: 12, height: 12)
                    
                    Text(state.isPaused ? "已暂停" : "追踪中")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Mode indicator
                Text("运动模式")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(WidgetTheme.offWhite)
            }
            
            // Stats row
            HStack(alignment: .top, spacing: 24) {
                // Distance
                VStack(alignment: .leading, spacing: 4) {
                    Text("距离")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(0.6)
                        .foregroundColor(WidgetTheme.offWhite)
                    
                    Text(formattedDistance)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("公里")
                        .font(.system(size: 12))
                        .foregroundColor(WidgetTheme.offWhite)
                }
                
                // Duration
                VStack(alignment: .leading, spacing: 4) {
                    Text("时长")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(0.6)
                        .foregroundColor(WidgetTheme.offWhite)
                    
                    Text(formattedDuration)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("已用时间")
                        .font(.system(size: 12))
                        .foregroundColor(WidgetTheme.offWhite)
                }
                
                Spacer()
                
                // Status indicator (green bar when tracking)
                if state.isTracking && !state.isPaused {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(WidgetTheme.activeGreen)
                        .frame(width: 34, height: 58)
                }
            }
        }
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
    }
}

// MARK: - Daily Mode Lock Screen

struct DailyModeLockScreen: View {
    let state: TrackingActivityAttributes.ContentState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack(spacing: 8) {
                // Tracking indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.isPaused ? WidgetTheme.mutedText : WidgetTheme.activeGreen)
                        .frame(width: 12, height: 12)
                    
                    Text(state.isPaused ? "已暂停" : "追踪中")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Mode indicator
                Text("日常模式")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(WidgetTheme.mutedText)
            }
//            
//            // Add Memory Button
//            Button(intent: AddMemoryIntent()) {
//                HStack(spacing: 8) {
//                    Image(systemName: "plus")
//                        .font(.system(size: 14, weight: .bold))
//                        .foregroundColor(.black)
//                    
//                    Text("添加记忆")
//                        .font(.system(size: 14, weight: .bold))
//                        .tracking(0.55)
//                        .foregroundColor(.black)
//                }
//                .frame(maxWidth: .infinity)
//                .frame(height: 44)
//                .background(WidgetTheme.activeGreen)
//                .cornerRadius(16)
//            }
//            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
    }
}

// MARK: - Widget Theme

enum WidgetTheme {
    static let cardBg = Color(red: 0.04, green: 0.04, blue: 0.04)
    static let cardStroke = Color(red: 0.12, green: 0.16, blue: 0.22)
    static let activeGreen = Color(red: 0, green: 1, blue: 0.25)
    static let offWhite = Color(red: 1, green: 1, blue: 0.97)
    static let mutedText = Color(red: 0.42, green: 0.45, blue: 0.51)
}

// MARK: - Preview

#if DEBUG
struct TrackingLiveActivity_Previews: PreviewProvider {
    static let sportAttributes = TrackingActivityAttributes(
        trackingMode: "sport",
        startTime: Date()
    )
    
    static let dailyAttributes = TrackingActivityAttributes(
        trackingMode: "daily",
        startTime: Date()
    )
    
    static let contentState = TrackingActivityAttributes.ContentState(
        distanceMeters: 2350,
        elapsedSeconds: 1245,
        isTracking: true,
        isPaused: false,
        memoriesCount: 3
    )
    
    static var previews: some View {
        Group {
            // Sport mode lock screen
            sportAttributes
                .previewContext(contentState, viewKind: .content)
                .previewDisplayName("Sport Mode - Lock Screen")
            
            // Daily mode lock screen
            dailyAttributes
                .previewContext(contentState, viewKind: .content)
                .previewDisplayName("Daily Mode - Lock Screen")
            
            // Dynamic Island - Compact
            sportAttributes
                .previewContext(contentState, viewKind: .dynamicIsland(.compact))
                .previewDisplayName("Sport - Dynamic Island Compact")
            
            // Dynamic Island - Expanded
            sportAttributes
                .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
                .previewDisplayName("Sport - Dynamic Island Expanded")
            
            // Dynamic Island - Minimal
            sportAttributes
                .previewContext(contentState, viewKind: .dynamicIsland(.minimal))
                .previewDisplayName("Dynamic Island Minimal")
        }
    }
}
#endif
