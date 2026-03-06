# Postcard Flip Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将明信片预览页和详情页统一为可翻面的正反面明信片视图，并支持长按保存当前面。

**Architecture:** 抽取 `FlippablePostcardView` 及前后面子视图作为唯一渲染来源；`PostcardPreviewView` 与 `PostcardDetailView` 复用该组件。发送时渲染正面图像，保存时渲染当前面图像。

**Tech Stack:** SwiftUI, UIKit (`UIImageWriteToSavedPhotosAlbum`), iOS 16 `ImageRenderer`.

---

### Task 1: 抽取复用明信片视图

**Files:**
- Create: `StreetStamps/FlippablePostcardView.swift`
- Modify: `StreetStamps/PostcardPreviewView.swift`
- Modify: `StreetStamps/PostcardInboxView.swift`

**Step 1: Write the failing test**
- 该任务为 SwiftUI 视觉重构，当前仓库无同类 snapshot/UI 自动化基础；采用行为验证替代（编译 + 手工交互检查）。

**Step 2: Run verification baseline**
Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'generic/platform=iOS Simulator' build`
Expected: 当前基线可编译（若失败，记录非本次改动引入错误）。

**Step 3: Write minimal implementation**
- 新建可复用翻面视图和 front/back face。
- 将预览页原左右分栏替换为复用组件。
- 将详情页原 image+detail 布局替换为复用组件。

**Step 4: Run build verification**
Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'generic/platform=iOS Simulator' build`
Expected: Build Succeeded。

### Task 2: 添加交互（点按翻面、长按保存）

**Files:**
- Modify: `StreetStamps/PostcardPreviewView.swift`
- Modify: `StreetStamps/PostcardInboxView.swift`

**Step 1: Write failing behavior check**
- 手工检查预览/详情页长按无保存行为（现状失败）。

**Step 2: Minimal implementation**
- 在复用卡片组件挂载 `onTapGesture` 翻面。
- 在预览与详情页接入 `onLongPressGesture` 保存当前面到相册。

**Step 3: Verify**
- Build 成功。
- 手工确认两页均可翻面且长按保存触发。

### Task 3: 发送图渲染调整为正面

**Files:**
- Modify: `StreetStamps/PostcardPreviewView.swift`

**Step 1: Write failing behavior check**
- 现状发送图是旧左右拼接卡面，不符合新样式。

**Step 2: Minimal implementation**
- `composedPostcardImagePath()` 改为渲染 front face。

**Step 3: Verify**
- Build 成功。
- 发送流程不报错，草稿/消息可继续生成。
