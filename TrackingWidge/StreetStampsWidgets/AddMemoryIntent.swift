//
//  AddMemoryIntent.swift
//  StreetStampsWidgets
//
//  App Intent 用于从锁屏添加记忆
//

import AppIntents
import Foundation

struct AddMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Memory"
    static var description = IntentDescription("Add a memory to your current journey")
    
    // 打开主 App 并触发添加记忆
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        // 通过 UserDefaults (App Group) 通知主 App 打开添加记忆界面
        if let defaults = UserDefaults(suiteName: "group.com.streetstamps.shared") {
            defaults.set(true, forKey: "pendingAddMemory")
            defaults.set(Date(), forKey: "pendingAddMemoryTimestamp")
        }
        
        return .result()
    }
}

struct OpenCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Capture"
    static var description = IntentDescription("Open the current journey capture flow")
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult & OpensIntent {
        if let defaults = UserDefaults(suiteName: "group.com.streetstamps.shared") {
            defaults.set(true, forKey: "pendingOpenCapture")
            defaults.set(Date(), forKey: "pendingOpenCaptureTimestamp")
        }
        return .result()
    }
}

// MARK: - Pause/Resume Intent

struct TogglePauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Pause"
    static var description = IntentDescription("Pause or resume tracking")
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        if let defaults = UserDefaults(suiteName: "group.com.streetstamps.shared") {
            defaults.set(true, forKey: "pendingTogglePause")
        }
        
        return .result()
    }
}
