# Tracking Ingest 放宽与跳点独立处理（PR 1 设计）

## 背景

用户反馈：daily 模式下 2 小时行程显示 0m。Memory 有坐标，城市识别成功，journey 距离为 0。

根因：
1. **GPS lock 阶段过严**：daily `lockAccuracy=35m`，walk adjusted 收紧到 25m。室内 / 高架下 accuracy 长期 40-80m，永远凑不齐"连续 2 个 ≤lockAccuracy"，rawCoords 全程为空。
2. **后台 lowPrecision 默认开启** + 不联动 ingest：`DailyTrackingPrecision.defaultPrecision = .lowPrecision`，App 进后台立即 `desiredAccuracy = kCLLocationAccuracyHundredMeters`，但 ingest 仍按 50m 过滤，100% 的后台点被丢弃。
3. **过滤策略保守**：用"丢精度差的点"防跳点，把"精度过滤"和"跳点过滤"耦合，导致城市开车场景大量轨迹断裂。
4. **过度按 mode 细分精度参数**：`adjusted(for:)` 给 walk/run/bike 各设相近但不同的 lockAccuracy，物理上没区分意义，反而造成"识别 walk → 收紧门槛 → 锁不上"的恶性反馈。
5. **Lock 概念本身已不必要**：lock 是"等 GPS 收敛再记起点"的事前防御。它的副作用（锁不上 = 0m）比"起点偏一点"严重得多。主流 GPS 软件都不用 lock，靠 map matching（PR 2 计划做）或后期 cleanup 兜底。

## 目标

**PR 1 范围只解决两件事：门槛 + 废点。**

- 解决 daily 模式 0m 行程 bug：取消 lock 概念，所有 acc ≤ 200m 的点直接接受。
- 把"精度过滤"和"跳点过滤"解耦：跳点用物理规则独立检测，不再依赖 accuracy 门槛。
- 用 warmup 30 秒承担起点保护。
- Sport 模式不再有自己的精度门槛——精度策略全产品统一。
- acc > 200 段（仅 fallback 模式接受时）画虚线作为视觉提示。

## 非目标

- **不动 distance 算法**：接受 acc ≤ 200 的点后 distance 可能比之前略高，由 PR 2 map matching 真正修正（snap 到道路后噪声自动消失，几何距离即真实距离）。
- **不引入 distance 折算 / multiplier 系数**：凭经验拍脑门的折算会引入新的不准确性，无物理基础。
- **不持久化任何"低精度标记"**：`lowAccuracyMode` 字段不上 `JourneyRoute`，仅在 ingest 内部用 `fallbackMode: Bool` 内存状态。
- **不动 UI**：不加 banner、不加 distance "~" 前缀、不加 L10n。差段视觉就是虚线段，足以表达"GPS 不好"。
- **不动 JourneyRoute / CoordinateCodable / JourneyPostCorrection / JourneyFinalizer / CloudKit / 后端 schema**。
- 不引入路网数据 / map matching（PR 2）。
- 不重写 OneEuro / 转弯检测 / static jitter / signal recovery gap 等现有机制，仅协作。
- 不引入 CoreMotion 模式融合（PR 4）。
- 不动 transit / drive / motorcycle / flight 的密度类参数。

## 改动范围

整个 PR 1 改动面只在 **2 个文件**：

- [StreetStamps/TrackingService.swift](StreetStamps/TrackingService.swift)
- [StreetStamps/TrackingMode.swift](StreetStamps/TrackingMode.swift)
- [StreetStamps/LifelogBackgroundMode.swift](StreetStamps/LifelogBackgroundMode.swift) — 仅一行默认值

无新文件，无数据结构变更，无持久化变更。

## 4 层过滤架构

### [L1] 废弃点过滤

入口处 `userLocation = loc` 之后立即检查：

```swift
guard isTracking, !isPaused else { return }
guard loc.horizontalAccuracy >= 0 else { return }
guard loc.horizontalAccuracy <= 500 else { return }              // 新增：硬上限
guard loc.timestamp.timeIntervalSinceNow >= -30 else { return }  // 已存在
guard rawTimestamps.last == nil || loc.timestamp > rawTimestamps.last! else { return }
```

acc > 500 视为完全噪声直接丢，不论 fallback 与否。其他都进 L2。

### [L2] Warmup 30 秒缓冲

替换现有 lock 阶段。新增状态：

```swift
private struct WarmupBufferEntry {
    let loc: CLLocation
}

private var warmupBuffer: [WarmupBufferEntry] = []
private var warmupExpired: Bool = false
private let warmupSeconds: TimeInterval = 30
private let warmupConvergeRadius: Double = 50
private var fallbackMode: Bool = false   // warmup 30s 内未收到任何 acc≤200 的 fix → true
```

Ingest 中 warmup 阶段处理：

```swift
if !warmupExpired {
    let elapsed = (trackingStartedAt.map { loc.timestamp.timeIntervalSince($0) }) ?? 0

    // 30s 未到 + acc ≤ 200 的点 → 入 buffer
    if elapsed < warmupSeconds, acc <= 200 {
        warmupBuffer.append(.init(loc: loc))
        return
    }

    // 30s 到达 → 决定起点
    if elapsed >= warmupSeconds {
        warmupExpired = true
        if warmupBuffer.isEmpty {
            // Fallback：30 秒内没收到任何 ≤200 的 fix
            fallbackMode = true
            // 当前 fix 走 fallback 路径处理（acc≤500 也接受）
        } else {
            flushWarmupBuffer()    // 收敛/散开判断 + 写入
            // 当前 fix 走正常路径
        }
    }
}
```

`flushWarmupBuffer` 实现：

```swift
private func flushWarmupBuffer() {
    let entries = warmupBuffer
    warmupBuffer.removeAll()
    guard !entries.isEmpty else { return }

    let centroid = entries.centroidCoordinate()
    let allWithinRadius = entries.allSatisfy { entry in
        CLLocation(latitude: centroid.latitude, longitude: centroid.longitude)
            .distance(from: entry.loc) < warmupConvergeRadius
    }

    if allWithinRadius {
        // 收敛：单点 centroid 起点（用最早 timestamp）
        let startTs = entries.first!.loc.timestamp
        rawCoords.append(centroid)
        rawTimestamps.append(startTs)
        appendPointToInternalSegments(coord: centroid, at: startTs, preferredStyle: .solid)
        lastLocation = CLLocation(latitude: centroid.latitude, longitude: centroid.longitude)
    } else {
        // 散开：按时间序全写
        for entry in entries {
            rawCoords.append(entry.loc.coordinate)
            rawTimestamps.append(entry.loc.timestamp)
            appendPointToInternalSegments(coord: entry.loc.coordinate, at: entry.loc.timestamp, preferredStyle: .solid)
        }
        lastLocation = entries.last!.loc
    }
}
```

边缘情况：journey 在 warmup 期间结束 / 暂停 / app 退出 → `flushWarmupBuffer()` 在终结路径上调用一次，避免数据丢失。

### [L3] 跳点独立检测（warmup 后跑）

替换 [TrackingService.swift:1188-1221](StreetStamps/TrackingService.swift#L1188-L1221) 的 drift / accuracy gate / speed outlier 混合逻辑。

```swift
// L3.1: 物理上限（绝对硬过滤，不论模式）
if dt > 0, d2d / dt > 50 {   // 50 m/s = 180 km/h
    droppedByJumpCount += 1
    return
}

// L3.2: V 字回弹（候选点观察机制）
let vReboundOffset: Double = fallbackMode ? 300 : 100
let vReboundReturn: Double = fallbackMode ? 50 : 20

if let pending = pendingJumpCandidate {
    let backToAnchor = loc.distance(from: pending.anchor)
    let pendingOffset = pending.candidate.distance(from: pending.anchor)
    let totalDt = loc.timestamp.timeIntervalSince(pending.anchor.timestamp)
    if pendingOffset > vReboundOffset && backToAnchor < vReboundReturn && totalDt < 10 {
        // 中间 candidate 被确认是跳点 → 已经在前一次 return 时丢弃，这里清状态
        pendingJumpCandidate = nil
        droppedByJumpCount += 1
    } else if totalDt > 10 {
        retroactivelyAcceptCandidate(pending.candidate)
        pendingJumpCandidate = nil
    }
}

// L3.3: 突然加速暂存
let recentMedianSpeed = computeRecentMedianSpeed()   // 最近 60s 速度中位数
let suddenAccel = (impliedSpeed > recentMedianSpeed * 5 + 5) && (impliedSpeed > 8)
if suddenAccel {
    pendingJumpCandidate = JumpCandidate(anchor: last, candidate: loc)
    return
}

// L3.4: accuracy 软过滤（仅非 fallback 时）
if !fallbackMode, acc > 200, !keepBecauseTurn {
    droppedByAccuracyCount += 1
    return
}
```

Fallback 模式下 acc 200-500 的点也通过 L3.4，进入 L4 写入。

`pendingJumpCandidate`：

```swift
private struct JumpCandidate {
    let anchor: CLLocation
    let candidate: CLLocation
}
private var pendingJumpCandidate: JumpCandidate?
```

`retroactivelyAcceptCandidate` 把暂存的 candidate 走完正常 ingest（进 L4 写入），保证 timestamp 顺序不破坏 `rawTimestamps` 单调性。

### [L4] 写入 + segment style

```swift
// segment style 决策（acc-based hysteresis 防边界抖动）
let preferredStyle: SegmentStyle = {
    if isGapLike { return .dashed }                               // 现有 gap detection 优先
    let currentStyle = internalSegments.last?.style ?? .solid
    if currentStyle == .solid {
        return acc > 230 ? .dashed : .solid                       // solid → dashed 阈值 230
    } else {
        return acc <= 170 ? .solid : .dashed                      // dashed → solid 阈值 170
    }
}()

// 距离累计：保持现有逻辑不变（按 d2d 1.0x 累加）
if shouldAccumulateDistance {
    totalDistance += d2d
    accumulateElevation(from: last, to: loc)
}

// 写入
rawCoords.append(outCoord)
rawTimestamps.append(loc.timestamp)
appendPointToInternalSegments(coord: outCoord, at: loc.timestamp, preferredStyle: preferredStyle)
```

`rawCoords` 类型保持 `[CLLocationCoordinate2D]` 不变。distance 算法**保持现有逻辑不变**——接受 acc≤200 后 distance 可能略虚高，PR 2 的 map matching 是真正的修正路径。

## TravelMode 配置精简（密度类参数仍按 mode 区分）

`TrackingMode.swift` `TrackingModeConfig` 字段精简——**删除**精度类字段：

- `maxAcceptableAccuracy` → 删，用全局常量 `Ingest.maxAcceptableAccuracy = 200` 替代
- `lockAccuracy` → 删（已无 lock 概念）

`adjusted(for:)` 现在只调密度类参数：

| | foregroundMinDistance | stationaryMinMove | gapSec / gapDistance | maxPoints/h | OneEuro |
|---|---|---|---|---|---|
| daily（合并 walk） | 10m | 12m | 180s / 2000m | 250 | minCutoff=1.0, beta=0.05 |
| run | 5m | 5m | 60s / 800m | 800 | minCutoff=1.1, beta=0.06 |
| bike | 8m | 12m | 90s / 1500m | 500 | minCutoff=1.05, beta=0.05 |
| transit | 15m | 20m | 120s / 2000m | 180 | off |
| drive / motorcycle | 25m | 30m | 180s / 3000m | 120 | off |
| flight | 500m | 100m | 300s / 15000m | 30 | off |

合并 daily-base 和 walk：原值差异（12m vs 8m, 15m vs 12m）不构成实际产品差异。

`gapSecondsThreshold` 全产品大幅放宽（少画虚线），尤其 daily 从 60s → 180s。

## 默认 DailyTrackingPrecision

[LifelogBackgroundMode.swift:9](StreetStamps/LifelogBackgroundMode.swift#L9)：

```swift
static let defaultPrecision: DailyTrackingPrecision = .highPrecision   // lowPrecision → highPrecision
```

老用户主动选过的不动（`@AppStorage` 已存 UserDefaults）。新用户和未碰过开关的用户默认走 highPrecision，不进 100m 后台精度模式。

⚠️ **关键澄清**：lowPrecision 不再触发 ingest 配置切换。它只影响 GPS 硬件 desiredAccuracy（已经存在的逻辑）。Ingest 的过滤行为对所有模式统一。

## TravelMode 识别防御

加 90 秒"不应用 adjusted(for:)"窗口，防御早期错误识别：

```swift
// updateModeIfNeeded
guard newMode != mode else { return }
mode = newMode
lastModeChangeAt = now

if trackingMode == .daily {
    let elapsed = now.timeIntervalSince(trackingStartedAt ?? now)
    guard elapsed >= 90 else { return }   // 新增
    let adjustedConfig = modeConfig.adjusted(for: newMode)
    applyModeConfig(adjustedConfig)
}
```

注：精度参数已从 `adjusted(for:)` 移除，所以即使没有 90s 窗口，"识别 walk → 锁不上"的恶性循环已经不存在。这条防御是兜底。

## 向后兼容

| 数据源 | 兼容方式 |
|---|---|
| 所有持久化 | **完全不变**（PR 1 不动任何 schema） |

`fallbackMode` 是 TrackingService 内存状态，不持久化。journey 完成后写入磁盘的 JSON 跟以前一致。

## 回归风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| 接受 acc ≤ 200 的点后 distance 略虚高 | 用户看到 5km 但 Apple Watch 显示 4km | OneEuro 平滑 + 跳点独立检测 + 完成时 dedupeTinySteps + Douglas-Peucker。**根本修正在 PR 2 map matching** |
| Warmup 30s 期间用户感觉"按下没反应" | 蓝点在动但 totalDistance=0 | 与现有 lock 期间体验一致，不变差 |
| Warmup buffer 散开但实际是 cached fix 异常 | 起点跳到旧位置 | 已有 `timestamp < -30s` 过滤 |
| acc 在 200 边界抖动 → dashed/solid 切换锯齿 | 视觉很乱 | hysteresis 170/230 |
| `pendingJumpCandidate` 与 stationary jitter 状态机交互 | 两个状态机都暂存"等下一个观察" | 优先级：warmup → stationary jitter → jump candidate；同时只持有一个 |
| Retroactive accept candidate 时 timestamp 顺序 | rawTimestamps 单调性可能破坏 | candidate 入队时记录 timestamp，retroactive accept 时按 timestamp 插入 |
| `accuracyVeryBad`（acc≥120）现有多处使用 | 直接放宽到 200 后，drift / dashed / 距离不累计逻辑变化 | 保留 `accuracyVeryBad = 120` 作为 drift / segment style / 距离决策的 *软* 信号；硬过滤改用 `acc > 200` |
| Mode 识别在 warmup 之前不工作 | mode 永远是 unknown，base config 应用 | 不修复（PR 4 用 CoreMotion 解决）。base 现已统一到 `acc ≤ 200`，不再阻塞 |

## 测试要求

### 单元测试（StreetStampsTests）

新增 `TrackingIngestRelaxationTests.swift`：

- `testPhysicalSpeedLimit`：implied speed > 50 m/s 直接丢
- `testJumpCandidateVRebound`：A(0,0) → B(0.001,0.001) → A(0,0)，B 被丢
- `testJumpCandidateVReboundFallback`：fallback 模式下阈值放宽，普通漂移不误丢
- `testWarmupConverge`：5 个 ≤200 点都在 50m 内 → 输出单 centroid
- `testWarmupDiverge`：5 个 ≤200 点散开 → 全部保留
- `testWarmupFallback`：30 秒内 0 个 ≤200 点 → fallbackMode = true
- `testWarmupFallbackAcceptLowAccuracy`：fallback 后 acc=300 也接受
- `testSegmentStyleHysteresis`：acc 在 200 边界附近来回（210/195/220/180）不导致段 style 反复切换

### 真机回归

| 场景 | 期望 |
|---|---|
| 户外步行 30 分钟（acc 通常 ≤30） | 全程 solid |
| 城市开车 30 分钟（含高架/桥下） | 主要 solid，过桥下时短暂 dashed 段，恢复后 solid |
| daily + 后台锁屏 30 分钟（lowPrecision） | 默认改为 highPrecision，新用户不会撞此场景；老用户主动选 lowPrecision 后台→收到 100m 精度点→正常接受（acc 100 ≤ 200），全 solid |
| 室内 30 分钟（acc 200-400） | warmup 30s 后 fallback，写入 dashed 段 |
| 隧道穿越 5 分钟 | 进隧道 GPS 丢失，gap detection 触发 dashed 单段，出隧道恢复 solid |
| Sport 户外跑步 30 分钟 | 全程 solid |

### 回归现有测试

- `JourneyPostCorrectionTests`（如存在）—— 不动，distance 算法未变
- `JourneyFinalizerTests` —— 不动
- `CityCacheTests` —— 不动

## 实施顺序

子 PR 拆分（每个独立可合并）：

1. **PR 1.1**（配置简化）：
   - 删除 TrackingModeConfig 的 `lockAccuracy / maxAcceptableAccuracy` 字段
   - `adjusted(for:)` 仅保留密度类参数
   - 合并 daily-base 和 walk 配置
   - `gapSecondsThreshold` 放宽
   - `LifelogBackgroundMode.defaultPrecision` 改 `.highPrecision`
   - 测试：编译通过 + sport/daily 真机基础回归

2. **PR 1.2**（4 层过滤架构 + 跳点独立）：
   - 删除 `isLocationLocked / lockStreak / lockConsecutiveCount`
   - 实现 L1（acc>500 / ts<-30 / ts 倒退）
   - 实现 L2 warmup 30s 缓冲 + flushWarmupBuffer + fallbackMode
   - 实现 L3 跳点独立检测（物理上限 + V 字回弹 + 突然加速暂存）
   - 实现 L4 segment style hysteresis
   - 加 `updateModeIfNeeded` 90s 窗口
   - 单元测试 + 真机室内 fallback / 隧道穿越场景

每子 PR 单独 review、单独合并。每合一个跑真机基础场景，无回归再做下一步。

## 不在范围（后续 PR）

- **PR 2**：Mapbox Map Matching 集成。Snap 到道路后 distance 自然准确，无需任何折算。这是 distance 准确性的真正修正路径。
- **PR 3**：UI 视觉差异化（如果未来需要点级精度信息，PR 3 时再决定持久化方式）
- **PR 4**：CoreMotion 模式融合
