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

struct TrackingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var elapsedSeconds: Int
        var isTracking: Bool
        var isPaused: Bool
        var memoriesCount: Int
    }

    var trackingMode: String
    var startTime: Date
}

struct TrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingActivityAttributes.self) { context in
            UnifiedLockScreenView(state: context.state)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(WidgetTheme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MiniAvatarBadge()
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Link(destination: URL(string: "streetstamps://capture")!) {
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(WidgetTheme.buttonGreen)
                            .clipShape(Circle())
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(formatDistance(context.state.distanceMeters))
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                Text(distanceUnitLabel())
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(WidgetTheme.islandMuted)
                            }

                            HStack(spacing: 5) {
                                Circle()
                                    .fill(context.state.isPaused ? WidgetTheme.mutedDot : WidgetTheme.buttonGreen)
                                    .frame(width: 7, height: 7)

                                Text(formatDuration(context.state.elapsedSeconds))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Button(intent: TogglePauseIntent()) {
                        Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 40, height: 26)
                            .background(
                                Capsule().fill(context.state.isPaused ? WidgetTheme.buttonGreen : Color.white.opacity(0.22))
                            )
                    }
                    .buttonStyle(.plain)
                }
            } compactLeading: {
                MiniAvatarBadge()
            } compactTrailing: {
                Text(formatDistance(context.state.distanceMeters))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            } minimal: {
                Circle()
                    .fill(context.state.isPaused ? WidgetTheme.mutedDot : WidgetTheme.buttonGreen)
                    .frame(width: 10, height: 10)
            }
        }
    }
}

private struct UnifiedLockScreenView: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            LiveActivityAvatar()

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatDistance(state.distanceMeters))
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(WidgetTheme.ink)
                        .lineLimit(1)

                    Text(distanceUnitLabel())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetTheme.unitText)
                }
                .minimumScaleFactor(0.7)

                HStack(spacing: 6) {
                    Circle()
                        .fill(state.isPaused ? WidgetTheme.mutedDot : WidgetTheme.buttonGreen)
                        .frame(width: 9, height: 9)

                    Text(formatDuration(state.elapsedSeconds))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button(intent: TogglePauseIntent()) {
                    ZStack {
                        Circle()
                            .fill(state.isPaused ? WidgetTheme.buttonGreen : WidgetTheme.buttonWarm)
                            .frame(width: 42, height: 42)
                        Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: "streetstamps://capture")!) {
                    ZStack {
                        Circle()
                            .fill(WidgetTheme.buttonGreen)
                            .frame(width: 42, height: 42)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(WidgetTheme.panelFill)
        )
    }
}

private struct LiveActivityAvatar: View {
    var body: some View {
        Image("LiveActivityAvatar")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: 88, height: 88)
    }
}

private struct MiniAvatarBadge: View {
    var body: some View {
        Image("LiveActivityAvatar")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .padding(2)
        .frame(width: 24, height: 24)
    }
}

enum WidgetTheme {
    static let cardBg = Color.clear
    static let panelFill = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let buttonGreen = Color(red: 0.29, green: 0.78, blue: 0.67)
    static let ink = Color(red: 0.39, green: 0.33, blue: 0.27)
    static let secondaryText = Color(red: 0.48, green: 0.42, blue: 0.35)
    static let unitText = Color(red: 0.52, green: 0.47, blue: 0.41)
    static let buttonWarm = Color(red: 0.55, green: 0.50, blue: 0.44)
    static let mutedDot = Color(red: 0.66, green: 0.66, blue: 0.62)
    static let islandMuted = Color.white.opacity(0.68)
    static let noteIcon = Color.white
}

private func formatDistance(_ meters: Double) -> String {
    let kilometers = meters / 1000
    return String(format: "%.2f", kilometers)
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

private func distanceUnitLabel() -> String {
    NSLocalizedString("lockscreen_distance_unit_km_short", comment: "")
}
