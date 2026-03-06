# 自定义开屏 + 冷启动预热 设计稿

## 目标
将用户提供的品牌 HTML 视觉做成 App 内自定义开屏（非系统 Launch Screen），固定展示 1.5 秒；开屏期间并行预热主页面与 City Library 缩略图，降低冷启动体感等待。

## 约束与结论
- 当前项目是 SwiftUI `@main App` 启动，不使用 LaunchScreen.storyboard。
- iOS 系统开屏不支持 HTML/CSS 动效，因此采用 App 内开屏实现。
- 开屏必须不改变现有引导页、登录弹层、DeepLink、定位初始化等业务流程。

## 方案对比
1. WebView 直接加载 HTML
- 优点：还原度高
- 缺点：冷启动额外引入 WebKit 初始化，稳定性与性能不可控

2. SwiftUI 原生重建视觉与动效（推荐）
- 优点：启动轻、易控、和现有主题/状态管理一致
- 缺点：需要手工映射动画

3. 静态图 + 渐变
- 优点：实现快
- 缺点：品牌表达弱，和原稿差异大

结论：采用方案 2。

## 架构设计
1. 新增 `AppSplashView`
- 绿色背景
- 中央品牌图形（简化路径 + 小角色跳动）
- 品牌文字淡入
- 动画总时长小于 1.5 秒，确保消失前已经完成关键动画。

2. 新增 `StartupWarmupService`
- 提供 `start(...)` 启动并行预热。
- 预热项 A：提前实例化 `MainTabView` 的视图树（由 `ZStack` 后景承载）。
- 预热项 B：读取 City 缩略图到 `CityImageMemoryCache`。
- 预热范围：优先 `CityCache` 中排序靠前城市，限制数量，防止启动抖动。

3. 修改 `StreetStampsApp`
- 根内容外层加 `SplashGate`：
  - 背景放真实根页面（继续执行 `.task` 里的业务初始化）
  - 前景放开屏视图，1.5s 后淡出
- `onAppear` 触发 warmup，不阻塞主线程。

## 数据流
1. App 启动 -> `StreetStampsApp` 构建根视图
2. 根视图后台正常执行已有初始化 task
3. 同时启动 warmup:
- 读取 `cityCache.cachedCities` -> 选择可用缩略图路径 -> 磁盘加载 `UIImage` -> 写入 `CityImageMemoryCache`
4. 1.5s 到时移除开屏层，用户看到已完成部分预热的主界面

## 错误处理
- 任一预热任务失败均静默降级，不阻断开屏结束。
- 缩略图缺失时跳过。
- 用户切换账号后已有 `cityCache` rebind 机制，本次 warmup 只做当前会话预热。

## 验证标准
- 冷启动看到开屏且持续约 1.5s。
- 开屏结束后可正常进入 Intro/Main。
- 城市库首次打开缩略图明显减少“占位图”比例。
- 无 crash、无主线程卡顿告警。
