# Lifelog 后台记录模式设计（高精度 / 低精度）

## 背景
当前 Lifelog 被动记录默认走低功耗模式，真机优先 `significant location changes`，省电但轨迹连续性偏弱。目标是做出更接近 Pikmin 的被动后台记录体验，同时保持可控功耗。

## 目标
- 仅影响 Lifelog 被动记录（不影响 Journey 的 sport/daily 追踪逻辑）。
- 在设置页提供两档可切换：`高精度` / `低精度`。
- `高精度` 目标：连续性显著提升，额外功耗约中高档（用户接受 8%~15%/天）。
- `低精度` 目标：保持当前省电优先能力，轨迹允许稀疏。

## 非目标
- 不尝试绕过 iOS force-quit 限制（手动划掉后后台定位不可持续）。
- 不重做 Journey 主流程、Map 渲染或 Lifelog UI 大改版。

## 方案对比
### A. 双固定档
- 高精度：持续后台定位
- 低精度：SLC 为主
- 优点：实现快
- 缺点：高精度静止时可能浪费电

### B. 双固定档 + Visit
- 高精度：持续定位 + SLC + Visit
- 低精度：SLC + Visit
- 优点：比 A 补点能力更强
- 缺点：固定策略，场景自适应不足

### C. 双档 + 自适应（选定）
- 高精度：后台持续定位为主；长时间静止自动轻降功耗，移动恢复
- 低精度：SLC + Visit 为主，必要时短窗粗粒度连续补洞
- 优点：连续性与功耗平衡最好，接近 Pikmin 的行为体验
- 缺点：实现复杂度更高

## 架构设计
### 1) 新增配置模型
新增 `LifelogBackgroundMode`：
- `highPrecision`
- `lowPrecision`

通过 `@AppStorage` 持久化（默认 `highPrecision`）。

### 2) App 层路由
`StreetStampsApp.ensurePassiveLocationTrackingIfNeeded()` 不再直接 `startLowPower()`，改为读取 Lifelog 配置后调用 `LocationHub.startPassiveLifelog(mode:)`。

### 3) LocationHub 增加被动入口
新增：
- `startPassiveLifelog(mode: LifelogBackgroundMode)`

该入口仅在 `!TrackingService.shared.isTracking` 时使用，Journey 期间仍完全由 `TrackingService` 控制前后台定位策略。

### 4) SystemLocationSource 增加两套被动策略
新增：
- `startPassiveHighPrecision()`
- `startPassiveLowPrecision()`

`高精度`建议策略：
- `allowsBackgroundLocationUpdates = true`
- 以中高精度连续定位为主（避免导航级满功耗）
- 同时开启 `SLC + Visit` 兜底
- 静止达到阈值自动降频（降低 distanceFilter / desiredAccuracy）
- 检测到移动后恢复主档

`低精度`建议策略：
- `SLC + Visit` 为主
- 必要时短窗粗粒度连续补洞

## UI 与文案
设置页新增区块：`后台记录模式`。
选项：`高精度` / `低精度`。
文案强调：
- 高精度更连续、耗电更高
- 低精度更省电、轨迹更稀疏

## 数据与兼容
- 新配置仅新增一个 `UserDefaults` key，向后兼容。
- 不改已有 Lifelog 轨迹文件结构。
- 不影响已有 Journey 存储、回放与分享。

## 验收标准
- 设置切换后即时生效。
- 仅 Lifelog 被动记录受影响，Journey 行为不变。
- 高精度轨迹点密度明显高于低精度。
- 低精度功耗明显低于高精度。

## 风险与缓解
- 风险：高精度档耗电超预算。
  - 缓解：引入静止自适应降档与恢复阈值。
- 风险：被动模式与 Journey 抢占定位状态。
  - 缓解：统一在 `LocationHub` 做入口隔离，Journey 优先级最高。
- 风险：force-quit 被误解为“记录失效”。
  - 缓解：设置说明补充 iOS 限制。
