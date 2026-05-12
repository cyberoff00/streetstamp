# CoreMotion 距离校验（PR 5 设计）

## 背景

PR 1+2+3 完成后，distance 算法的核心逻辑：

```
ingest 实时累加: totalDistance += d2d
finalize 时:    r.distance = correctedDistance(corrected coords)
```

存在的问题：

1. **静止时 GPS 漂移虚增 distance**：用户在咖啡店坐 30 分钟，GPS 漂动累计上百米虚假位移
2. **跑步机场景**：用户在跑但 GPS 不动 → distance ≈ 0（这次 PR 不解决）
3. **慢漂场景**：公园树荫下 GPS 整体偏移，distance 略虚高

PR 5 用 CoreMotion `CMMotionActivityManager` + `CMPedometer` 校验距离累计——区分用户**真的在动** vs **GPS 漂动**。

## 目标

- **GPS 漂移虚增 distance 修正**（主要场景：咖啡店、办公室、室内停留）
- **走路 / 跑步用步频校验**：CMPedometer 30 秒内步数 = 0 + GPS 报位移 → 不累计
- **trust-GPS fallback**：CoreMotion 说静止但 GPS 持续在动 → 信 GPS（覆盖被推婴儿车 / 轮椅 / 滑板等场景）
- 不影响开车 / 骑行 / 飞行场景的 distance（CoreMotion 识别为 automotive/cycling 时走 GPS-only）

## 非目标

- **跑步机距离修复**（GPS 不动 + 用户在跑 → 用 step→distance 转换累加）—— 留给 PR 6
- 海拔修正
- 多传感器 EKF 融合
- 心率 / 步频高级运动指标

## 现有基础设施

`StreetStamps/MotionActivityFusion.swift` 已有：

- `MotionActivityHub.shared` —— `CMMotionActivityManager` 封装，`snapshot: MotionActivitySnapshot` 实时活动类型
- `MotionActivitySnapshot.kind` —— `.stationary / .walking / .running / .cycling / .automotive / .unknown`
- `MotionActivitySnapshot.confidence` —— `.low / .medium / .high`

PR 5 新增 `CMPedometer` 封装 + 在 ingest 改造 distance 累计逻辑。

## 数据流

```
GPS fix → ingest L4 距离累计前:
   ↓
  let activity = MotionActivityHub.shared.snapshot   ← 已有
  let recentSteps = PedometerHub.shared.stepsInLast(30)   ← PR 5 新增
   ↓
  按 activity 类型决定累不累加:
    stationary + GPS 慢 → 不累加
    stationary + GPS 持续在动 30s+ → 信 GPS（fallback）
    walking/running + recentSteps == 0 + GPS 报位移 → 不累加（GPS 漂移）
    walking/running + recentSteps > 0 → 累加
    cycling/automotive → GPS-only（同现状）
    unknown → 兜底走 GPS-only（不变差不变好）
```

## 数据结构变更

**完全无 schema 变更**：

- 不动 `JourneyRoute` schema
- 不动 `CoordinateCodable`
- 不持久化任何步频 / activity 数据
- 仅在 TrackingService 内部决策距离累计

## 新增文件

### `StreetStamps/PedometerHub.swift`

封装 `CMPedometer`，沿用 `MotionActivityHub` 的设计模式：

```swift
@MainActor
final class PedometerHub: ObservableObject {
    static let shared = PedometerHub()

    @Published private(set) var isAvailable: Bool
    @Published private(set) var isRunning = false

    private let pedometer = CMPedometer()
    private var stepHistory: [(time: Date, cumSteps: Int)] = []
    private let historyMaxAge: TimeInterval = 90   // keep last 90s of step samples
    private var started = false

    /// Step count in the last `seconds`. Synchronous read from cached history.
    /// Returns 0 if pedometer not yet started or no samples in window.
    func stepsInLast(_ seconds: TimeInterval) -> Int

    /// Start pedometer updates from `date` (typically journey start).
    /// Idempotent — second call ignored.
    func start(from date: Date)

    /// Stop pedometer updates and clear history.
    func stop()
}
```

实现细节：
- `pedometer.startUpdates(from: date)` 持续监听
- 每次回调更新 `stepHistory`（追加新 cumulative steps + timestamp）
- `stepsInLast(s)` 用滑动窗口算法：找 `s` 秒前最接近的 baseline，返回 `latest - baseline`
- 内部 history 90s 上限，超期自动 evict
- 线程：CMPedometer 回调在后台线程，hop 到 MainActor 更新 history

## 修改文件

### `StreetStamps/StreetStampsApp.swift`

跟 `MotionActivityHub` 一起启动：

```swift
MotionActivityHub.shared.setShouldRun(...)
PedometerHub.shared.setShouldRun(...)   // 新增
```

### `StreetStamps/TrackingService.swift`

#### 1. 引用 PedometerHub

```swift
private let pedometerHub = PedometerHub.shared   // 新增
```

#### 2. `startNewJourney` 启动 pedometer

```swift
func startNewJourney(mode: TrackingMode = .daily) {
    // ... existing ...
    pedometerHub.start(from: Date())   // 新增
    // ...
}
```

#### 3. `stopJourney` / `endJourney` 停止 pedometer

```swift
func endJourney() {
    // ... existing ...
    pedometerHub.stop()   // 新增
    // ...
}
```

#### 4. ingest L4 距离累加改造

替换现有 `shouldAccumulateDistance` 逻辑（约 [TrackingService.swift:1334-1340](StreetStamps/TrackingService.swift#L1334)）：

```swift
let shouldAccumulateDistance: Bool = {
    if isMissingSegment { return trackingMode == .daily }

    // PR 5: activity-based distance validation
    let activity = motionHub.snapshot
    let recentSteps = pedometerHub.stepsInLast(30)
    let gpsImpliesMoving = impliedSpeed > 1.0 && acc < 100

    switch activity.kind {
    case .stationary:
        // CoreMotion says not moving. Trust GPS only if persistently moving.
        // (catches wheelchair / stroller / skateboard / unrecognized vehicles)
        if gpsImpliesMoving && stationaryButGpsMovingDuration > 30 {
            return true   // trust-GPS fallback
        }
        return false

    case .walking, .running:
        // Step count validation: if GPS reports >5m movement but no steps recorded
        // in last 30s, this is GPS drift — don't accumulate.
        // Skip validation if confidence is low (CoreMotion uncertain).
        guard activity.confidence != .low else { return true }
        if recentSteps == 0 && d2d > 5 { return false }
        return true

    case .cycling, .automotive:
        // No step-count validation possible. Trust GPS.
        return true

    case .unknown:
        // Fallback: trust GPS (preserve current behavior).
        return true
    }
}()
```

需要新增追踪 `stationaryButGpsMovingDuration` 状态字段：

```swift
private var stationaryGpsMovingFirstSeenAt: Date?
```

逻辑：
- 进入 stationary + gpsImpliesMoving → 记录 `firstSeenAt`
- 持续 stationary + gpsImpliesMoving → 算 duration
- 切出 stationary 或 GPS 不再 moving → 清空

## Trust-GPS Fallback 详细规则

```swift
// At ingest entry (after L1 reject filters):
let activity = motionHub.snapshot
let isMovingByGps = impliedSpeed > 1.0 && acc < 100

if activity.kind == .stationary && isMovingByGps {
    if stationaryGpsMovingFirstSeenAt == nil {
        stationaryGpsMovingFirstSeenAt = loc.timestamp
    }
} else {
    stationaryGpsMovingFirstSeenAt = nil
}

let stationaryButGpsMovingDuration: TimeInterval = {
    guard let start = stationaryGpsMovingFirstSeenAt else { return 0 }
    return loc.timestamp.timeIntervalSince(start)
}()
```

**为什么需要 30 秒持续判定**：

CoreMotion activity 更新频率约 1 分钟一次。开始 journey 后第一分钟是 `unknown`，然后才有第一个 activity。如果用户在车上但 CoreMotion 还没识别出 automotive，会短暂判为 stationary——这种情况不应该立即丢 distance。30 秒持续判定能滤掉这种过渡 case。

如果用户真的在被推（持续 GPS 移动 + 持续 CoreMotion stationary），30 秒后开始信 GPS。

## 阈值调参

| 参数 | 默认值 | 调整方向 |
|---|---|---|
| `recentSteps` 窗口 | 30s | 太短：步频抖动误判；太长：响应慢 |
| `step==0 + d2d>5` 才 drop | 5m | 太小：误丢真实小位移；太大：漏掉真实漂移 |
| trust-GPS fallback 持续时长 | 30s | 太短：CoreMotion 切换抖动误信 GPS；太长：被推场景前 30s 漏记录 |
| GPS 速度阈值 | 1.0 m/s | 太低：站立微动也算 moving；太高：慢走漏判 |

这些都先用保守值，根据真机数据调。

## 兼容性 / 兜底

| 场景 | 行为 |
|---|---|
| 设备无 CoreMotion（极旧 iPhone） | `MotionActivityHub` 已经处理，snapshot 永远 `.unknown` → 走 GPS-only fallback |
| 设备无 pedometer | `PedometerHub.isAvailable = false`，`stepsInLast` 永远返回 0 → 但因为 confidence 检查会走 GPS-only |
| 用户拒绝 motion permission | iOS 不报错，CMMotionActivityManager 回调可能被静默 → snapshot 一直 unknown → GPS-only |
| iOS 隐私设置关闭 health/motion | 同上 → GPS-only |

**任何 CoreMotion 路径失败都自动回退到 GPS-only**，跟当前 PR 1-3 行为一致。**永远不会比现状差**。

## 风险

| 风险 | 缓解 |
|---|---|
| CoreMotion 误判 walking → 步频 0 时正常移动被丢 | confidence 检查（.low 不参与判断） + GPS 速度门槛 |
| 跑步机场景 distance ≈ 0 | 现状就是 0，不变差。完整修复留 PR 6 |
| 被推婴儿车 / 轮椅误判 stationary | trust-GPS fallback 30s 后转 GPS-only |
| 用户拿手机静止但被传送（电梯、滑梯）| trust-GPS fallback 兜住 |
| Pedometer 启动延迟（permission prompt） | 第一个 30s 内 stepsInLast 返回 0 → 但 walking confidence 在前 30s 也是 low → 走 GPS-only |
| Hub start 后 CMPedometer 首次回调慢 | history 空时 stepsInLast 返回 0，会跟现状一样接受所有 GPS-reported 距离 |

## 测试要求

### 单元测试

新增 `PedometerHubTests.swift`：

- `testStepsInLastEmptyHistory` → 0
- `testStepsInLastWithinWindow` → 步数差
- `testStepsInLastEvictionAfterMaxAge` → 90s 前数据不算
- `testStepsInLastInterpolation` → 找 baseline 正确

新增/扩展 `TrackingDistanceValidationTests.swift`：

- `testStationaryDropsDistance` → activity=stationary + d2d=10 → 不累加
- `testStationaryWithGpsMovingTrustsGpsAfter30s` → fallback 触发
- `testWalkingZeroStepsDropsDistance` → walking + recentSteps=0 + d2d>5 → 不累加
- `testWalkingWithStepsAccumulates` → walking + recentSteps>0 → 累加
- `testAutomotiveAccumulatesAlways` → automotive + d2d 任意 → 累加
- `testUnknownFallsBackToGps` → unknown → 累加
- `testLowConfidenceFallsBackToGps` → walking confidence=low → 累加（不参与步频校验）

### 真机回归

| 场景 | 期望 |
|---|---|
| 户外纯走路 30 分钟 | distance 接近现状（不变差） |
| 走 30 分钟 + 长椅休息 10 分钟 | **distance 显著降低**（休息 10 分钟不累加） |
| 城市开车 1 小时 | distance 同现状 |
| 跑步机 30 分钟 | distance ≈ 0（同现状，PR 5 不解决） |
| 室内办公一整天（GPS 偶尔漂动）| **distance 接近 0**（stationary 全程不累加） |
| 推婴儿车散步 30 分钟 | distance 正常累加（trust-GPS fallback） |

## 实施顺序

子 PR 拆分：

1. **PR 5.1**：新建 `PedometerHub.swift` + 单元测试 + StreetStampsApp 启动集成
2. **PR 5.2**：TrackingService 集成 PedometerHub + ingest 距离累计改造 + trust-GPS fallback + 真机回归

每子 PR 单独可合并。PR 5.1 完成 hub 单测过，PR 5.2 接到主流程。

## 不在范围（后续 PR）

- **PR 6**：跑步机距离修复（CMPedometer step→distance 转换 + activity=running + GPS 不动 检测）
- **PR 7**：海拔修正（CMAltimeter 气压计 + SRTM 数据库）
- **PR 8**：完整 EKF + IMU 融合（Strava Premium 级）
