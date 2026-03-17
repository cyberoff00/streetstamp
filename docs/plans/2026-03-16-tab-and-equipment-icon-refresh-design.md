# Tab And Equipment Icon Refresh Design

日期：2026-03-16
状态：已评审通过（用户确认）

## 1. 目标

将用户提供的 3 个图标语义接入现有 app，但保持当前产品里的 icon 规范不变：
- 开始 tab 替换为旗帜语义图标
- 宠物装备区替换为宠物语义图标
- suit 装备区替换为连体服语义图标

## 2. 范围

包含：
- 重绘 `tab_start_icon`
- 重绘 `equipment_icon_pat`
- 重绘 `equipment_icon_suit`

不包含：
- SwiftUI 逻辑调整
- tab / 装备栏布局改动
- 着色、选中态、交互状态改动

## 3. 设计约束

- 保持现有 asset 名称不变，避免改动代码引用
- 保持模板图标渲染方式不变，继续交给 app 当前着色逻辑处理
- `tab_start_icon` 继续使用 28x28 tab icon 规格
- `equipment_icon_pat` 与 `equipment_icon_suit` 继续使用 48x48 装备分类 icon 规格
- 新图标只保留用户提供图形的核心识别特征，并向现有 app 的线条粗细、留白和视觉重心对齐

## 4. 实现策略

- 不改 `MainTab.swift` 与 `EquipmentView.swift`
- 直接替换对应 asset 图片文件
- 继续保留 `template-rendering-intent`

## 5. 验收标准

1. 开始 tab 显示旗帜语义图标
2. 宠物装备区显示宠物语义图标
3. suit 装备区显示连体服语义图标
4. 三处 icon 的尺寸、选中态、颜色变化沿用当前 app 逻辑
5. 不引入布局偏移或明显风格断层
