# Mapbox Map Matching 集成（PR 2 设计）

## 背景

PR 1 完成后，ingest 接受 acc ≤ 200m 的点（fallback 时 ≤ 500m）。这解决了"0m journey"问题，但带来新代价——**接受的低精度点会让 distance 略虚高**。我们刻意没在 PR 1 做"distance 折算"修正，理由是：

1. 折算系数（× 0.5 / × 0.85）凭直觉拍脑门，没有物理基础
2. 真正的修正路径是**把 GPS 点 snap 到真实道路**，让漂移自动消失

PR 2 实现这个真正的修正：通过 Mapbox Map Matching API 把 raw GPS 轨迹对齐到道路网络。

## 现有相关代码

[JourneyRoutePostProcessor.swift](StreetStamps/JourneyRoutePostProcessor.swift) 已有一个简化版本——但它实际是"anchor routing"，不是真 map matching：
- 取 8 个 anchor 点
- 用 `MKDirections` 在每对 anchor 之间**重新规划路径**
- 拼接结果

问题：
- MKDirections 给的是"最优路径"，不是用户实际走的路径（绕远路 / 走小巷会被改写）
- 8 个 anchor 太少，长行程信息丢失
- 仅在直线距离 80m–200km 之间触发

PR 2 用 Mapbox Map Matching API 替换这部分逻辑——**真正的 HMM + Viterbi 实现**，保留用户实际路径，只 snap 到最近道路。

## 已具备的基础设施

- ✅ Mapbox SDK 已集成（`import MapboxMaps`，[MapboxEngine.swift](StreetStamps/Map/MapboxEngine.swift)）
- ✅ Mapbox access token 在 [Info.plist](StreetStamps/Info.plist) `MBXAccessToken` 键
- ✅ `JourneyRoute.matchedCoordinates: [CoordinateCodable]` 字段已存在
- ✅ `preferredRouteSource: RouteSource` 枚举支持 `.matched`
- ✅ `displayRouteCoordinates` 已经按 `preferredRouteSource` 优先级取轨迹

也就是说**所有数据结构和读取路径都现成的**，PR 2 只需要写"获取 matched coordinates"这一段。

## 目标

- 把 Mapbox Map Matching API 集成到 `JourneyRoutePostProcessor.processIfNeeded`
- 当 matching 成功且置信度足够时，写入 `matchedCoordinates` 并设 `preferredRouteSource = .matched`
- 当 matching 不适用（飞行 / 非道路场景 / 网络失败）时，回退到现有 `MKDirections anchor routing` 或保留 `correctedCoordinates`
- 不影响 ingest 阶段、不影响实时 distance / UI（journey 完成后才跑）

## 非目标

- 不引入实时 matching（每个 fix 都调 API）—— 太贵且无必要
- 不引入路网数据本地化（OSM + HMM 实现）—— 工程量过大
- 不修改 `JourneyRoute` schema —— `matchedCoordinates` 已存在
- 不动后端 / CloudKit —— matching 在客户端完成
- 不动 UI 渲染层 —— `displayRouteCoordinates` 已经按 `preferredRouteSource` 自动切换

## API 概览

[Mapbox Map Matching API v5](https://docs.mapbox.com/api/navigation/map-matching/) 文档：

```
GET https://api.mapbox.com/matching/v5/{profile}/{coordinates}
```

参数：
- `profile`: `driving` / `walking` / `cycling`
- `coordinates`: `lon,lat;lon,lat;...`（最多 100 个点 / 请求）
- `radiuses`: 每个点的搜索半径（米），可选——传 GPS accuracy 让算法考虑不确定性
- `geometries`: `geojson` / `polyline`（默认 polyline6）
- `overview`: `full` / `simplified`（推荐 `full` 拿到完整 snapped 几何）
- `tidy`: `true` 让 Mapbox 自动清理重复/抖动点
- `access_token`: query string 传

响应（geojson 模式）：
```json
{
  "matchings": [{
    "geometry": { "type": "LineString", "coordinates": [[lon, lat], ...] },
    "confidence": 0.85,
    "distance": 5234.5
  }],
  "code": "Ok"
}
```

定价（2026 年）：
- 前 10 万次请求 / 月免费
- 之后约 $0.50 / 1000 次

按当前用户规模（独立产品，DAU 数千），每月免费额度足够。

## 数据流

```
journey finalize
  ↓
JourneyFinalizer.finalize()
  ↓
JourneyPostCorrection.correctedCoordinates (现有：清理离群点)
  ↓
JourneyRoutePostProcessor.processIfNeeded (改造)
  ↓
  ├─ 1. 决策 profile (walking/cycling/driving/skip)
  ├─ 2. 检测是否在道路场景（前置 sample 测试）
  ├─ 3. 切分 → Mapbox API (每 90 点一段，重叠 5 点)
  ├─ 4. 拼接结果 → matchedCoordinates
  ├─ 5. 失败回退到现有 MKDirections anchor routing
  └─ 6. 都失败 → 留空，preferredRouteSource = .corrected
  ↓
JourneyRoute.distance = JourneyPostCorrection.correctedDistance(route)
   (correctedDistance 现在用 displayRouteCoordinates，自动取 matched)
  ↓
journey 持久化
```

## Profile 决策

```swift
enum MapMatchProfile: String {
    case driving
    case walking
    case cycling
}

static func profile(for route: JourneyRoute) -> MapMatchProfile? {
    if route.trackingMode == .sport {
        return .walking   // sport 默认跑步/走路场景
    }
    // daily mode: 看 mode 检测结果（持久化在 JourneyRoute 里没？需 verify）
    // 暂时按 trackingMode 推断:
    //   sport → walking
    //   daily 默认 → walking（保守，绝大多数 daily journey 是步行）
    //   未来扩展：根据 journey 平均速度判断
    return .walking
}
```

注意：`mode: TravelMode` 是 TrackingService 内存字段，**未持久化到 JourneyRoute**。所以 finalize 时无法从 journey 读出"用户主要是步行/骑行/开车"。

简化：**默认所有 daily/sport journey 用 `walking`**。如果未来需要按出行方式区分，再加一个字段持久化（属于 PR 范围之外）。

`flight` 场景如何判断？看 journey 的 `correctedCoordinates` 平均速度——如果 > 50 m/s（180 km/h）→ 跳过 matching（飞机不在道路上）。

## 切分策略

Mapbox API 单次最多 100 个点。超过的轨迹要切分：

```
轨迹 [0..N]
  → 切分成段 [0..89], [85..174], [170..259], ...
    （相邻段重叠 5 个点）
  → 每段调一次 API
  → 拼接结果（去重重叠点）
```

为什么重叠 5 个点：保证拼接处的几何连续性。两个独立段的端点位置可能略有不同（snap 到不同的道路位置），重叠点让我们能识别"段 N 的尾部 = 段 N+1 的头部"，平滑过渡。

实现：

```swift
let segmentSize = 90
let overlapSize = 5
var segments: [[CoordinateCodable]] = []
var idx = 0
while idx < coords.count {
    let endIdx = min(idx + segmentSize, coords.count)
    segments.append(Array(coords[idx..<endIdx]))
    if endIdx == coords.count { break }
    idx = endIdx - overlapSize
}
```

拼接：
```swift
var merged: [CoordinateCodable] = []
for (i, snapped) in matchedSegments.enumerated() {
    if i == 0 { merged.append(contentsOf: snapped) }
    else { merged.append(contentsOf: snapped.dropFirst(overlapSize)) }
}
```

## 是否调用 matching 的前置检测

不是所有 journey 都该调 matching：

| Journey 特征 | 应该 matching | 理由 |
|---|---|---|
| 城市开车 | ✅ | 主战场，效果最好 |
| 城市走路 / 骑行 | ✅ | 人行道 / 骑行道也在 OSM 里 |
| 公园散步（远离道路）| ❌ | 公园小径未必在 OSM，匹配会把轨迹 snap 到旁边马路 |
| 山地徒步 | ❌ | 大部分山路 OSM 没有 |
| 海滩 / 户外野外 | ❌ | 完全无路 |
| 室内购物中心 | ❌ | 不在 OSM |
| 飞行 | ❌ | 飞机不在地面道路 |

判断规则（启发式）：

1. **平均速度 > 50 m/s**（180 km/h）→ 飞行 → 跳过
2. **平均速度 < 0.5 m/s**（约 1.8 km/h）→ 用户基本静止 → 跳过（轨迹长度本身就不可信）
3. **首尾直线距离 < 80m**（现有逻辑）→ 跳过
4. **抽样 confidence 测试**：取轨迹首/中/尾 3 个点 → 单独发一次 matching API（3 个点 + driving profile）→ 如果返回 `confidence < 0.4`，说明这条轨迹大概率不在道路 → 跳过完整 matching
5. **路径距离过长**（> 200km，现有阈值）→ 跳过

抽样 confidence 测试是额外的 API 调用（成本），但能避免对非道路 journey 浪费完整切分匹配的 API 调用。

简化版：**省略前置抽样，直接调完整 matching**。Mapbox 返回的 confidence 本身就能判断结果是否可用——如果整体 confidence < 0.5，丢弃 matched 结果，回退 corrected。

我倾向**简化版**，PR 2 不做前置抽样。如果实际跑下来浪费 API 太多再加。

## 失败 / 回退

按优先级：

1. **Mapbox API 调用成功 + 全部段 confidence ≥ 0.5** → 用 matched
2. **Mapbox API 调用成功但 confidence < 0.5** → 丢弃 matched，回退到现有 MKDirections anchor routing
3. **Mapbox API 网络/超时/错误** → 回退到现有 MKDirections anchor routing
4. **MKDirections 也失败 / 距离超出 80m–200km 范围** → `matchedCoordinates` 留空，`preferredRouteSource = .corrected`

`displayRouteCoordinates` 已经按 fallback 顺序取（matched → corrected → raw），UI 自动适配。

## 数据结构（无变更）

`JourneyRoute.matchedCoordinates` / `preferredRouteSource` 已经存在，PR 2 只是填数据。

`CoordinateCodable` 不变。matched coordinates 是新坐标点，不带原始 timestamp（snapped 几何点没有时间戳）。这是**与原始 raw coordinates 的关键差别**——matched 不能用于"按时间复原速度"，但完全够用于"轨迹可视化 + 距离计算"。

## 改动文件

只动一个文件：

**[StreetStamps/JourneyRoutePostProcessor.swift](StreetStamps/JourneyRoutePostProcessor.swift)**

- 新增 `mapMatchViaMapbox(coords:profile:) async -> [CLLocationCoordinate2D]?` 函数
- 修改 `processIfNeeded`：先尝试 Mapbox，失败回退到现有 `mapMatchIfPossible`（MKDirections）
- 新增 helper：`profileForRoute / averageSpeed / segmentForMatching`

可选新文件：

**[StreetStamps/MapboxMapMatchingClient.swift](StreetStamps/MapboxMapMatchingClient.swift)**（如果 PostProcessor 太长）

- 封装 URLSession 调用、JSON 解析、错误处理
- 单元测试可以 mock URLSession

我倾向**新建一个文件**，让 PostProcessor 保持干净——它只做"决策路径"，不做"HTTP 细节"。

## 测试要求

### 单元测试（StreetStampsTests）

新增 `MapboxMapMatchingClientTests.swift`：

- `testRequestURLConstruction`：参数正确编码（profile / coordinates / token / radiuses）
- `testParseSuccessResponse`：mock 200 响应，解析 geometry + confidence
- `testParseErrorResponse`：mock 500 / 错误 code，返回 nil
- `testCoordinateChunking`：350 个点 → 4 段 (89+5 重叠 + 89+5 + 89+5 + 78)
- `testChunkMerging`：拼接重叠段后单一连续 polyline

新增/扩展 `JourneyRoutePostProcessorTests.swift`：

- `testProfileSelection`：sport → walking, daily → walking
- `testFlightSkipsMatching`：avg speed > 50 m/s → matchedCoordinates 留空
- `testFallbackToMKDirections`：mock Mapbox 失败 → 走 MKDirections 路径
- `testLowConfidenceRejected`：mock confidence=0.3 → matchedCoordinates 留空

### 真机回归

| 场景 | 期望 |
|---|---|
| 城市开车 5 km | matchedCoordinates 非空，confidence ≥ 0.7，UI 渲染显示明显贴合道路 |
| 公园散步 | confidence 可能 < 0.5 → 回退 corrected，轨迹不被改写 |
| 山地徒步 | confidence < 0.4 → 回退 corrected |
| Sport 跑步公路 | matched walking profile 生效，距离接近实测 |
| 室内 / fallback journey | matched 可能失败 → 回退 corrected，至少有原始轨迹 |

### 监控指标（建议添加）

- Mapbox API 月调用量（防超免费额度）
- Matching 成功率（confidence ≥ 0.5 的 journey 占比）
- Matching 平均 confidence（评估算法效果）

## 实施顺序

子 PR 拆分：

1. **PR 2.1**：新建 `MapboxMapMatchingClient.swift` 独立 client + 单元测试（mock URLSession）
2. **PR 2.2**：集成到 `JourneyRoutePostProcessor.processIfNeeded`，加 profile 决策、切分、回退到现有 MKDirections
3. **PR 2.3**（可选）：监控埋点 + 远程 confidence 阈值可调

每子 PR 独立可合并。PR 2.1 完成后 client 单独测过，PR 2.2 才接到主流程。

## 不在范围（后续）

- **PR 3**：UI 视觉差异化（如果未来想区分原始 / matched 段，需要持久化 confidence 字段）
- **PR 4**：CoreMotion 模式融合（与 PR 2 完全独立）
- 后端代理 Mapbox 请求（如果客户端 token 滥用风险大）—— 暂未必要
- 离线 map matching（OSM + 本地 HMM）—— 长期不计划

## 风险

| 风险 | 缓解 |
|---|---|
| Mapbox 月请求量超额 | 用户规模上来后加监控 + 服务端代理（PR 2.3 或单独 PR） |
| Token 暴露 | `MBXAccessToken` 是 public token（pk.*），按 Mapbox 设计就是客户端可见。设置 token URL 限制白名单（在 Mapbox dashboard） |
| 网络不稳定 → 大量 journey 没 matched | 自动回退到 MKDirections。失败的 journey 下次打开时可以加"重新匹配"按钮（PR 2.3） |
| 中国用户连不上 Mapbox API | Mapbox 国内可达性较好但不保证。失败回退到 MKDirections（Apple Maps 在中国用高德数据，可用） |
| 用户走非道路（公园小径）被强行 snap 到旁边马路 | confidence 检测：< 0.5 拒绝采用，保留 raw 轨迹 |
