# Postcard Inbox Self Reaction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show the current user's own reaction and comment under received postcards while keeping sent postcards showing the peer's reaction and comment.

**Architecture:** Extend the postcard message DTO with explicit role-based reaction fields and keep a compatibility fallback for legacy payloads. Route footer rendering through `PostcardInboxPresentation` so the card row can stay visually unchanged while the data source becomes box-aware.

**Tech Stack:** Swift, SwiftUI, XCTest

---

### Task 1: Model the reaction ownership

**Files:**
- Modify: `StreetStamps/PostcardModels.swift`
- Test: `StreetStampsTests/PostcardInboxPresentationTests.swift`

**Step 1: Write the failing test**

Add tests that construct a postcard message with both `myReaction` and `peerReaction` and assert the received box resolves `myReaction` while the sent box resolves `peerReaction`.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardInboxPresentationTests`

Expected: FAIL because the presentation layer still reads a single `reaction` field.

**Step 3: Write minimal implementation**

Add `myReaction` and `peerReaction` to `BackendPostcardMessageDTO`, keep legacy `reaction` decoding as fallback, and update `PostcardInboxPresentation.cardReaction` to return the right field for each box.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardInboxPresentationTests`

Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/PostcardModels.swift StreetStamps/PostcardInboxPresentation.swift StreetStampsTests/PostcardInboxPresentationTests.swift docs/plans/2026-03-18-postcard-inbox-self-reaction-design.md docs/plans/2026-03-18-postcard-inbox-self-reaction-implementation.md
git commit -m "test: cover postcard reaction ownership by inbox box"
```

### Task 2: Preserve footer behavior in the inbox UI

**Files:**
- Modify: `StreetStamps/PostcardInboxView.swift`
- Test: `StreetStampsTests/PostcardInboxPresentationTests.swift`

**Step 1: Write the failing test**

Add/extend tests so a message with both emoji and comment remains fully renderable through the presentation output used by both sent and received sections.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardInboxPresentationTests`

Expected: FAIL if any box still resolves the wrong reaction payload.

**Step 3: Write minimal implementation**

Update the sent and received section call sites to continue using the presentation helper so both boxes feed the correct reaction data into `PostcardCardRow` without changing the footer layout.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardInboxPresentationTests`

Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/PostcardInboxView.swift StreetStampsTests/PostcardInboxPresentationTests.swift
git commit -m "feat: show self reactions in received postcards"
```

### Task 3: Verify end-to-end decoding compatibility

**Files:**
- Modify: `StreetStampsTests/PostcardInboxPresentationTests.swift`

**Step 1: Write the failing test**

Add coverage for decoding a DTO from JSON with:
- only legacy `reaction`
- explicit `myReaction`
- explicit `peerReaction`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardInboxPresentationTests`

Expected: FAIL until the decoder supports all cases.

**Step 3: Write minimal implementation**

Finalize DTO decoding precedence:
- explicit role-based fields win
- legacy `reaction` fills whichever role is otherwise absent

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardInboxPresentationTests`

Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/PostcardModels.swift StreetStampsTests/PostcardInboxPresentationTests.swift
git commit -m "test: keep postcard reaction decoding compatible"
```
