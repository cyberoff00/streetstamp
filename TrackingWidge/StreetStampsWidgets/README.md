# StreetStamps Widget Extension 设置指南

## 概述

此文件夹包含 Live Activity 锁屏追踪卡片的实现代码。由于 Xcode 项目配置的复杂性，需要手动在 Xcode 中添加 Widget Extension Target。

## 文件结构

```
StreetStampsWidgets/
├── TrackingLiveActivity.swift    # Live Activity 主视图（锁屏 + Dynamic Island）
├── AddMemoryIntent.swift         # App Intent（从锁屏添加记忆按钮）
├── StreetStampsWidgetsBundle.swift # Widget Bundle 入口
├── Info.plist                    # Widget Extension 配置
└── StreetStampsWidgets.entitlements # 权限配置
```

## 在 Xcode 中添加 Widget Extension

### 步骤 1: 添加新 Target

1. 打开 Xcode 项目
2. 点击 **File > New > Target**
3. 选择 **iOS > Widget Extension**
4. 配置：
   - Product Name: `StreetStampsWidgets`
   - Team: 选择你的开发团队
   - Bundle Identifier: `com.claire.streetstamps.widgets`（根据实际情况调整）
   - **取消勾选** "Include Configuration App Intent"
   - **勾选** "Include Live Activity"
5. 点击 **Finish**

### 步骤 2: 替换生成的文件

1. 删除 Xcode 自动生成的文件
2. 将 `StreetStampsWidgets/` 文件夹中的所有文件拖入新创建的 target

### 步骤 3: 配置 App Group

1. 选择主 App target > Signing & Capabilities
2. 点击 **+ Capability** > **App Groups**
3. 添加: `group.com.streetstamps.shared`

4. 选择 Widget Extension target > Signing & Capabilities
5. 同样添加 App Group: `group.com.streetstamps.shared`

### 步骤 4: 确认 Info.plist 配置

主 App 的 Info.plist 中需要包含：
```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

## 使用方法

### 在 TrackingService 中启动/更新/结束 Live Activity

```swift
// 开始追踪时
func startTracking() {
    // ... 其他代码
    startLiveActivity()
}

// 位置更新时
func locationDidUpdate() {
    // ... 其他代码
    updateLiveActivity(memoriesCount: currentMemoriesCount)
}

// 结束追踪时
func stopTracking() {
    // ... 其他代码
    endLiveActivity()
}
```

### 处理从 Widget 触发的操作

在你的 View 或 ViewModel 中监听通知：

```swift
.onReceive(NotificationCenter.default.publisher(for: .openAddMemoryFromWidget)) { _ in
    // 打开添加记忆界面
    showAddMemorySheet = true
}

.onReceive(NotificationCenter.default.publisher(for: .togglePauseFromWidget)) { _ in
    // 切换暂停状态
    TrackingService.shared.isPaused.toggle()
}
```

## 锁屏卡片效果

### 运动模式 (Sport Mode)
- 显示绿色追踪状态指示灯
- 实时距离（公里）
- 实时时长
- 右侧绿色状态条

### 日常模式 (Daily Mode)
- 显示绿色追踪状态指示灯
- 大按钮：点击添加记忆（直接打开 App）

## Dynamic Island

- **紧凑模式**: 左侧绿点 + 右侧距离/时间
- **展开模式**: 完整统计信息 + 日常模式下的添加记忆按钮
- **最小模式**: 仅绿色指示点

## 注意事项

1. Live Activity 需要 iOS 16.1+
2. Dynamic Island 需要 iPhone 14 Pro 及以上机型
3. 确保 App Group 配置正确，否则 Widget 无法与主 App 通信
4. `TrackingActivityAttributes` 需要在主 App 和 Widget Extension 中保持一致

## 测试

1. 运行主 App
2. 开始一个追踪
3. 锁屏查看 Live Activity
4. 点击 "添加记忆" 按钮测试 App Intent
