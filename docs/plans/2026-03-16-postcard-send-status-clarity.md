# Postcard Send Status Clarity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep the current immediate jump to the sent box after tapping send, while making the local postcard card clearly show whether it is queued, failed, or confirmed sent.

**Architecture:** Continue using `PostcardDraft` as the source of truth for local send state. Present a richer draft status model in the sent box UI, and navigate to the sent box immediately after enqueueing so users can watch the state progress on the local card even when backend refresh is delayed.

**Tech Stack:** SwiftUI, XCTest, existing `PostcardCenter` draft persistence and inbox presentation helpers.

---

### Task 1: Lock the draft status copy with tests

**Files:**
- Modify: `StreetStampsTests/PostcardInboxPresentationTests.swift`
- Modify: `StreetStamps/PostcardInboxPresentation.swift`

**Step 1: Write the failing test**

Add tests for local draft presentation covering:
- `sending` => badge `发送中` / detail `已加入发送队列，正在确认是否发送成功`
- `failed` => badge `发送失败` / detail `发送失败，可重试` / retry visible
- `sent` => badge `已发送` / detail `已发送`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardInboxPresentationTests`

Expected: FAIL because the new presentation helper does not exist yet.

**Step 3: Write minimal implementation**

Add a lightweight presentation struct/helper in `PostcardInboxPresentation.swift` that maps `PostcardDraftStatus` to badge/detail/retry UI state.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm `PostcardInboxPresentationTests` passes.

### Task 2: Wire the sent-box card UI to local draft state

**Files:**
- Modify: `StreetStamps/PostcardInboxView.swift`

**Step 1: Write the failing test**

If a focused view test is practical, add one for failed drafts remaining visible with retry UI. Otherwise keep this task implementation-only and rely on Task 1’s presentation tests plus manual verification.

**Step 2: Write minimal implementation**

Update sent-box draft rendering to:
- keep failed drafts visible
- show badge/detail text for `sending`, `failed`, and local-only `sent`
- show a retry button for failed drafts

**Step 3: Run targeted verification**

Run the same postcard presentation tests, then build or test the relevant app target if needed.

### Task 3: Jump to sent box immediately after enqueue

**Files:**
- Modify: `StreetStamps/PostcardPreviewView.swift`

**Step 1: Write the failing test**

If practical, add a presentation-level test; otherwise keep behavior verification manual because the logic is view/dismiss timing based.

**Step 2: Write minimal implementation**

After creating the local draft and starting background send, dismiss the preview and post the existing sent-box navigation notification immediately instead of waiting for confirmed success.

**Step 3: Run verification**

Run postcard tests and a simulator build/test command that covers SwiftUI compilation.
