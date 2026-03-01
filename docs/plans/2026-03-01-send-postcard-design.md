# Send Postcard 设计文档

日期：2026-03-01  
状态：已评审通过（用户确认）

## 1. 目标与范围

实现好友间一对一明信片发送能力，入口位于好友主页；发送后收件人在站内通知和系统推送中收到提醒。我的主页新增明信片入口，支持查看“我寄出”和“我收到”。

本期范围：
- 一对一发送给某个好友
- 城市来源：当前定位城市 + 已解锁城市
- 仅允许上传 1 张本地照片
- 文案上限 80 字
- 发送后不可撤回
- 弱网友好：本地草稿 + 后台同步 + 失败重试
- 明信片在消息体系中建模为特殊消息类型：`postcard message`
- 发送限制：
  - 同一城市对同一好友最多 1 张
  - 同一城市总发送量最多 5 张（按发送人维度）

## 2. 信息架构与页面流

### 2.1 页面入口
- 好友主页：新增 `Send Postcard` 入口
- 我的主页：新增 `Postcards` 入口
  - `Sent`（我寄出的）
  - `Received`（我收到的）

### 2.2 发送流程
1. 从好友主页进入 `New Postcard`（Figma 节点 `150:84`）
2. 选择城市（仅可选“当前定位城市 + 已解锁城市”）
3. 上传 1 张本地照片
4. 输入文案（<=80 字）
5. 进入 `Preview`（Figma 节点 `150:166`）
6. 点击发送后：先本地落草稿并置为 `sending`
7. 后台执行上传与发送（创建 `postcard message`）
8. 成功置 `sent`；失败置 `failed` 并允许重试

### 2.3 接收流程
- 收件人收到：
  - 站内通知中心一条“收到明信片”
  - 系统推送一条“收到明信片”
- 点击通知后跳转到该明信片详情（归属 `Received`）

## 3. 数据模型与状态机

### 3.1 本地模型：`PostcardDraft`
- `draftId`（本地 UUID）
- `clientDraftId`（与服务端幂等键一致，可与 `draftId` 复用）
- `toUserId`
- `cityId`
- `cityName`
- `photoLocalPath`（仅 1 张）
- `message`（<=80）
- `status`：`draft | sending | sent | failed`
- `retryCount`
- `lastError`
- `createdAt` / `updatedAt`

### 3.2 服务端消息模型：`PostcardMessage`
- `messageId`
- `type = postcard`
- `fromUserId`
- `toUserId`
- `cityId`
- `cityName`
- `photoUrl`
- `messageText`
- `sentAt`
- `clientDraftId`（幂等去重）

### 3.3 发送状态机
- `draft`：编辑/预览阶段
- `sending`：点击发送后，本地入队并后台同步
- `sent`：服务端成功创建 `postcard message`
- `failed`：上传或发送失败，允许 `Retry`

状态迁移：
- `draft -> sending -> sent`
- `draft -> sending -> failed -> sending -> sent`

## 4. 业务规则与配额

### 4.1 发送约束
- 发送后不可撤回
- 城市必须属于“当前定位城市 + 已解锁城市”
- 同一城市对同一好友最多 1 张
- 同一城市总发送量最多 5 张（发送人维度）

### 4.2 计数口径
- 仅 `sent` 计入配额
- `failed` 不计入配额
- `Retry` 不算新发送（同 `clientDraftId` 仅一次）

### 4.3 前后端双重校验
- 客户端：发送前即时拦截并提示
- 服务端：最终强校验，防并发/越权

建议错误文案：
- 同好友同城限制：`这个城市你已经送过给 TA 了`
- 同城总量限制：`这个城市的明信片已达到 5 张上限`

## 5. 接口设计（MVP 最小集）

### 5.1 `POST /postcards/send`
入参：
- `clientDraftId`
- `toUserId`
- `cityId`
- `messageText`
- `photoUploadToken`（由上传接口换取）

服务端校验：
- 文案长度 <= 80
- 城市可用性（定位/解锁）
- 同城同好友限制
- 同城总量限制
- 幂等键去重

出参：
- `messageId`
- `sentAt`

### 5.2 `GET /postcards?box=sent|received&cursor=...`
- 获取寄出/收到列表
- 支持分页

### 5.3 重试策略
- 客户端可直接调用 `send` 并复用原 `clientDraftId` 实现幂等重试
- 可选独立端点：`POST /postcards/{draftId}/retry`

### 5.4 通知事件
- 在 `postcard message` 创建成功后触发通知分发
- 收件人获得：站内通知 + 系统推送

## 6. 通知与交互细节

### 6.1 站内通知（收件人）
- 类型：`postcard_received`
- 标题：`你收到一张来自 {senderName} 的明信片`
- 副文案：`{cityName} · 点击查看`
- 跳转：`Postcards > Received > PostcardDetail(messageId)`

### 6.2 系统推送（收件人）
- 标题：`{senderName} 给你寄来一张明信片`
- 内容：`来自 {cityName}`
- 深链：同站内通知

### 6.3 发送端反馈
- 点击发送后 toast：`已加入发送队列`
- `sending`：显示上传/发送中
- `failed`：显示失败原因与 `Retry`
- `sent`：显示发送成功

## 7. 异常处理

- `upload_failed`：图片上传失败，草稿置 `failed`
- `network_timeout`：网络超时，草稿置 `failed`
- `city_friend_quota_exceeded`：同城同好友限制命中
- `city_total_quota_exceeded`：同城总量限制命中
- 幂等重复：返回已发送记录，客户端置 `sent`

## 8. 验收标准（DoD）

1. 好友主页存在 `Send Postcard` 入口
2. 发送页仅支持 1 张本地照片
3. 文案限制为 80 字
4. 城市仅允许“当前定位城市 + 已解锁城市”
5. 同城同好友重复发送被阻止
6. 同城第 6 张发送被阻止
7. 发送后不可撤回
8. 弱网下可见 `sending/failed` 并可重试
9. 发送成功后收件人同时收到站内通知与系统推送
10. 我的主页 `Postcards` 中 `Sent/Received` 展示正确

## 9. 测试建议

- 单元测试：
  - 文案长度校验
  - 城市可用性校验
  - 两类配额校验
  - 幂等去重
  - 状态机迁移
- 集成测试：
  - `send -> message(p type) -> notification/push` 事件链
- UI 测试：
  - 发送页字段限制
  - 预览页发送
  - 失败重试
  - 收件箱/寄件箱展示与跳转

## 10. 后续实现原则

- 视觉与交互按 Figma 节点 `150:84` 与 `150:166` 对齐
- 复用现有消息/通知架构，避免重复通道
- 配额逻辑以服务端为准，客户端仅做体验优化
