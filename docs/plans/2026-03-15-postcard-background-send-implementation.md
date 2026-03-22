# Postcard Background Send Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make tapping `Send` dismiss the postcard preview immediately while the upload and send continue in the background.

**Architecture:** Keep the existing `PostcardDraft` and `PostcardCenter` state machine, but change the preview screen to enqueue a background send task instead of awaiting the full network flow. Preserve `sending/failed/sent` transitions so the inbox remains the single source of truth for delivery status.

**Tech Stack:** SwiftUI, Swift Concurrency, XCTest

---

### Task 1: Add a failing UI-behavior test

**Files:**
- Modify: `StreetStampsTests/PostcardSendFlowPerformanceTests.swift`

**Step 1: Write the failing test**

Add a test that simulates a slow `/v1/media/upload` request and verifies the preview-triggered send path returns immediately instead of blocking on the upload.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardSendFlowPerformanceTests`

Expected: FAIL because the preview send path still awaits `enqueueSend`.

**Step 3: Write minimal implementation**

Introduce a fire-and-forget enqueue entry point for the preview screen and keep draft creation synchronous.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS

### Task 2: Wire preview dismissal to background send

**Files:**
- Modify: `StreetStamps/PostcardPreviewView.swift`
- Modify: `StreetStamps/PostcardCenter.swift`

**Step 1: Write the failing test**

Cover the `PostcardCenter` helper that should return immediately while the draft remains `sending` until the async upload completes.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardSendFlowPerformanceTests`

Expected: FAIL because no detached enqueue helper exists yet.

**Step 3: Write minimal implementation**

Add a non-blocking wrapper in `PostcardCenter` that starts the existing async send flow in a `Task`, then update `PostcardPreviewView` to call it and dismiss immediately after draft creation.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS

### Task 3: Verify related postcard behavior

**Files:**
- Verify: `StreetStampsTests/PostcardSendFlowPerformanceTests.swift`
- Verify: `StreetStampsTests/PostcardSendErrorPresentationTests.swift`

**Step 1: Run focused regression tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardSendFlowPerformanceTests -only-testing:StreetStampsTests/PostcardSendErrorPresentationTests`

Expected: PASS

**Step 2: Review touched files**

Confirm only postcard-preview and postcard-center files changed plus the focused test file.
