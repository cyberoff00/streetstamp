//
//  LiveActivityManager.swift
//  StreetStamps
//
//  管理 Live Activity（锁屏追踪卡片）的启动、更新和结束
//

import Foundation
import ActivityKit
import UIKit
import Combine

@MainActor
final class LiveActivityManager: ObservableObject {
    
    static let shared = LiveActivityManager()
    
    // 当前活动的 Live Activity
    private var currentActivity: Activity<TrackingActivityAttributes>?
    
    // 追踪开始时间
    private var trackingStartTime: Date?
    private var updateTimer: Timer?
    private static let updateInterval: TimeInterval = 30.0  // 每30秒更新一次
    // ✅ 新增：缓存最新状态（用于定时刷新）
    private var cachedDistance: Double = 0
    private var cachedMemoriesCount: Int = 0
    private var cachedIsPaused: Bool = false
    private var accumulatedPausedDuration: TimeInterval = 0
    private var currentPauseStartedAt: Date?
    
    // App Group UserDefaults 用于与 Widget 通信
    private let sharedDefaults = UserDefaults(suiteName: "group.com.streetstamps.shared")
    
    private init() {
        // 监听来自 Widget 的操作
        setupWidgetActionObserver()
    }
    
    // MARK: - Public API

    /// 检查设备是否支持 Live Activity
    var isLiveActivitySupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// End all Live Activities left over from a previous process (e.g. app was killed).
    /// Call this on cold start when there is no ongoing journey to resume.
    func endAllStaleActivities() {
        guard isLiveActivitySupported else { return }
        Task {
            for activity in Activity<TrackingActivityAttributes>.activities {
                let finalState = TrackingActivityAttributes.ContentState(
                    distanceMeters: 0,
                    elapsedSeconds: 0,
                    isTracking: false,
                    isPaused: false,
                    memoriesCount: 0
                )
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
            currentActivity = nil
            trackingStartTime = nil
            accumulatedPausedDuration = 0
            currentPauseStartedAt = nil
        }
    }
    
    /// 开始 Live Activity
    func startActivity(mode: TrackingMode) {
        guard isLiveActivitySupported else {
            print("[LiveActivity] Not supported on this device")
            return
        }
        
        // 如果已有活动，先结束
        if currentActivity != nil {
            endActivity()
        }
        
        let startTime = Date()
        trackingStartTime = startTime
        accumulatedPausedDuration = 0
        currentPauseStartedAt = nil

        let attributes = TrackingActivityAttributes(
            trackingMode: mode == .sport ? "sport" : "daily",
            startTime: startTime
        )
        
        let initialState = TrackingActivityAttributes.ContentState(
            distanceMeters: 0,
            elapsedSeconds: 0,
            isTracking: true,
            isPaused: false,
            memoriesCount: 0
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            print("[LiveActivity] Started: \(activity.id)")
            startUpdateTimer()
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }
    
    /// 更新 Live Activity 状态
    func updateActivity(
        distanceMeters: Double,
        elapsedSeconds: Int,
        isPaused: Bool,
        memoriesCount: Int
    ) {
        guard let activity = currentActivity else { return }
        cachedDistance = distanceMeters
        cachedIsPaused = isPaused
        cachedMemoriesCount = memoriesCount
        
        let updatedState = TrackingActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            isTracking: true,
            isPaused: isPaused,
            memoriesCount: memoriesCount
        )
        
        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil)
            )
        }
    }
    
    /// 暂停状态更新
    func updatePauseState(isPaused: Bool, distanceMeters: Double, elapsedSeconds: Int, memoriesCount: Int) {
        let now = Date()
        if isPaused {
            if currentPauseStartedAt == nil {
                currentPauseStartedAt = now
            }
        } else if let pauseStart = currentPauseStartedAt {
            accumulatedPausedDuration += max(0, now.timeIntervalSince(pauseStart))
            currentPauseStartedAt = nil
        }
        cachedIsPaused = isPaused
        updateActivity(
            
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            isPaused: isPaused,
            memoriesCount: memoriesCount
        )
    }
    
    /// 结束 Live Activity
    func endActivity() {
        stopUpdateTimer()
        guard let activity = currentActivity else { return }

        // 同步清除引用，防止 startActivity() 创建新 activity 后被异步回调覆盖
        currentActivity = nil
        trackingStartTime = nil
        accumulatedPausedDuration = 0
        currentPauseStartedAt = nil

        let finalState = TrackingActivityAttributes.ContentState(
            distanceMeters: 0,
            elapsedSeconds: 0,
            isTracking: false,
            isPaused: false,
            memoriesCount: 0
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
            print("[LiveActivity] Ended")
        }
    }
    
    /// 获取当前已追踪的秒数
    func getElapsedSeconds() -> Int {
        guard let startTime = trackingStartTime else { return 0 }
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(startTime))
        var paused = max(0, accumulatedPausedDuration)
        if let pauseStart = currentPauseStartedAt {
            paused += max(0, now.timeIntervalSince(pauseStart))
        }
        return Int(max(0, elapsed - paused))
    }
    // MARK: - ✅ 定时更新 Timer
    
    private func startUpdateTimer() {
        stopUpdateTimer()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: Self.updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.timerFired()
            }
        }
    }
    private func timerFired() {
        guard currentActivity != nil else { return }
        
        // 使用缓存的距离和记忆数，但更新时间
        let elapsed = getElapsedSeconds()
        updateActivity(
            distanceMeters: cachedDistance,
            elapsedSeconds: elapsed,
            isPaused: cachedIsPaused,
            memoriesCount: cachedMemoriesCount
        )
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - Widget Action Observer
    
    private func setupWidgetActionObserver() {
        // 监听 App 进入前台时检查 Widget 操作
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkPendingWidgetActions),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func checkPendingWidgetActions() {
        guard let defaults = sharedDefaults else { return }

        if defaults.bool(forKey: "pendingOpenCapture") {
            defaults.set(false, forKey: "pendingOpenCapture")

            NotificationCenter.default.post(
                name: .openCaptureFromWidget,
                object: nil
            )
        }
        
        // 检查是否有待处理的"添加记忆"操作
        if defaults.bool(forKey: "pendingAddMemory") {
            defaults.set(false, forKey: "pendingAddMemory")
            
            // 发送通知让主 App 打开添加记忆界面
            NotificationCenter.default.post(
                name: .openAddMemoryFromWidget,
                object: nil
            )
        }
        
        // 检查是否有待处理的暂停/继续操作
        if defaults.bool(forKey: "pendingTogglePause") {
            defaults.set(false, forKey: "pendingTogglePause")
            
            NotificationCenter.default.post(
                name: .togglePauseFromWidget,
                object: nil
            )
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openCaptureFromWidget = Notification.Name("openCaptureFromWidget")
    static let openAddMemoryFromWidget = Notification.Name("openAddMemoryFromWidget")
    static let togglePauseFromWidget = Notification.Name("togglePauseFromWidget")
}

// MARK: - TrackingService Integration

extension TrackingService {
    
    /// 开始追踪时启动 Live Activity
    func startLiveActivity() {
        Task { @MainActor in
            guard AppSettings.isLiveActivityEnabled else { return }
            LiveActivityManager.shared.startActivity(mode: trackingMode)
        }
    }
    
    /// 更新 Live Activity（在位置更新时调用）
    func updateLiveActivity(memoriesCount: Int = 0) {
        Task { @MainActor in
            refreshDurations()
            guard AppSettings.isLiveActivityEnabled else {
                LiveActivityManager.shared.endActivity()
                return
            }
            LiveActivityManager.shared.updateActivity(
                distanceMeters: totalDistance,
                elapsedSeconds: movingSeconds,
                isPaused: isPaused,
                memoriesCount: memoriesCount
            )
        }
    }
    
    /// 结束追踪时结束 Live Activity
    func endLiveActivity() {
        Task { @MainActor in
            LiveActivityManager.shared.endActivity()
        }
    }
}
