# Product Issues Tracker (2026-03-01)

## 1) Purpose

This document tracks product issues to be fixed one by one.

Update rules:
- All new issues start with `状态=待处理`.
- When done, update `状态=已完成` and fill `完成日期` and `验证结果`.
- Use `ID` for communication and progress tracking.

## 2) Priority Definition

- `P0`: Blocks key user flow or causes clear functional breakage.
- `P1`: Important issue with clear UX or logic impact, but not a hard blocker.
- `P2`: Optimization, refinement, or longer-term investigation.

## 3) Issue Ledger

| ID | 模块 | 标题 | 原始描述 | 状态 | 优先级 | 完成日期 | 验证结果 | 备注 |
|---|---|---|---|---|---|---|---|---|
| ISS-001 | 明信片 | 发送后返回路径错误 | 明信片发送后会返回编辑页，不对，应该发送后就返回好友主页。 | 已完成 | P0 | 2026-03-01 | 发送成功后从预览页回退到好友主页，不再停留编辑页。 | - |
| ISS-002 | 明信片 | 我的主页明信片详情无法进入 | 我的主页明信片发出收到的，都应该可以点进去看到具体的卡，目前点不进去。 | 已完成 | P0 | 2026-03-01 | 发出/收到列表均支持进入明信片详情页，支持图片与文案查看。 | - |
| ISS-003 | 明信片 | 收到明信片交互链路不完整 | 好友会收到明信片的通知，但是通知没法点进去看，而且主页收到里也不会显示，这不是完整的交互。 | 已完成 | P0 | 2026-03-01 | 通知点击后先标记已读再跳转收件箱并按 messageID 定位详情。 | - |
| ISS-004 | 好友 | Activity feed 自己旅程详情不可达 | activity feed 里面我自己的旅程点不进去，我的动态应该和好友的动态保持一致的交互，也可以点进去看详情，点头像进入我的主页。 | 已完成 | P1 | 2026-03-05 | 用户确认已可进入详情，交互与好友动态一致。 | - |
| ISS-005 | 好友 | 消息通知点击后缺少跳转 | 消息通知目前点了只是变灰，完整的交互是这条消息变灰，同时进入好友主页。 | 已完成 | P0 | 2026-03-05 | 用户确认点击后可完成已读并跳转好友主页。 | - |
| ISS-006 | 好友 | 好友可见旅程过滤规则不满足 | 好友可见的旅程至少要满足2个条件之一：1) 2公里及以上；2) 有记录memory。 | 已完成 | P1 | 2026-03-05 | 用户确认过滤规则已按里程/memory 条件生效。 | - |
| ISS-007 | 好友 | feed 文案语义不准确（旅程被写成城市） | 当前虽已区分类型，但文案显示为“完成了伦敦（城市）”；实际应表达为“完成了一段旅程”，需修正文案语义。 | 已完成 | P1 | 2026-03-05 | Journey 类型文案改为固定“完成了一段旅程/Completed a journey”，不再把城市名当作完成对象。 | - |
| ISS-008 | 服务容量 | 服务器承载能力评估 | 需要确定目前的服务器能支持多少人。 | 待处理 | P2 | - | - | - |
| ISS-009 | 账号 | 多设备登录与公开旅程同步逻辑确认 | 目前账号好像可以同步在多个设备登入，但是公开旅程并没有同步，这个逻辑需要再次确认一下。 | 待处理 | P1 | - | - | - |
| ISS-010 | 账号 | Google 登录问题 | Google 登入问题。 | 待处理 | P0 | - | - | 新增 |
| ISS-011 | 账号 | 邮箱验证问题 | 邮箱验证问题。 | 待处理 | P0 | - | - | 新增 |
| ISS-012 | memory | memory detail 编辑体验与背景不一致 | memory detail page 点编辑不需要跳到光标处；整体背景白色与页面不符合，需换成页面一致颜色。 | 已完成 | P1 | 2026-03-01 | 进入编辑态不再自动聚焦滚动；整体记忆区背景改为与页面一致的主题底色。 | - |
| ISS-013 | 心情 | 心情数据未持久化 | 目前心情没有存储，每次build都会清空。 | 已完成 | P0 | 2026-03-01 | 心情写入主 lifelog 文件同时写入独立 mood 侧文件，加载时支持回退恢复。 | - |
| ISS-014 | 数据安全与隐私 | 数据安全与隐私问题梳理 | 数据安全与隐私问题。 | 待处理 | P2 | - | - | 待细化范围 |
| ISS-015 | 设置 | 设置页面完善 | 设置页面完善。 | 待处理 | P2 | - | - | 新增 |
| ISS-016 | 设置/商业化 | 装备接入真实 Purchase | 装备接入真正的purchase。 | 待处理 | P1 | - | - | 新增 |

## 4) Update Log

- 2026-03-01: Initialized issue tracker with 16 pending issues.
- 2026-03-01: Completed ISS-001, ISS-002, ISS-003, ISS-012, ISS-013.
- 2026-03-05: Marked ISS-004, ISS-005, ISS-006 as completed per user confirmation; narrowed ISS-007 to feed copy semantic fix.
- 2026-03-05: Implemented ISS-004, ISS-005, ISS-006, ISS-007 in app code and updated tracker status.
