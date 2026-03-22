# Memory Editor Fullscreen Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the full-screen memory editor feel larger and lighter by increasing the notes editor height and removing the heavy boxed text-area styling, without changing save/photo/draft behavior.

**Architecture:** Keep the existing `MemoryEditorSheet` and `MemoryEditorPage` entry points. Limit changes to layout and presentation code inside `StreetStamps/MapView.swift`, and add a focused presentation test so the new full-screen sizing and lightweight treatment are covered without touching persistence or media logic.

**Tech Stack:** SwiftUI, XCTest, existing presentation-style unit tests in `StreetStampsTests`

---

### Task 1: Add a failing presentation test for full-screen memory editor sizing

**Files:**
- Create: `StreetStampsTests/MemoryEditorPresentationTests.swift`
- Modify: `StreetStamps/MapView.swift`
- Test: `StreetStampsTests/MemoryEditorPresentationTests.swift`

**Step 1: Write the failing test**

Add a small test-facing presentation model or constants assertion that expects the full-screen editor to expose a taller notes area than the compact sheet and to use a different visual style token than the compact card.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/MemoryEditorPresentationTests`

Expected: FAIL because the presentation constants or model do not exist yet.

**Step 3: Write minimal implementation**

Extract the relevant sizing/style values into small testable helpers in `StreetStamps/MapView.swift` and wire the full-screen editor to use the larger height and lighter style.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift StreetStampsTests/MemoryEditorPresentationTests.swift
git commit -m "feat: lighten fullscreen memory editor layout"
```

### Task 2: Update the full-screen editor layout

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: `StreetStampsTests/MemoryEditorPresentationTests.swift`

**Step 1: Write the failing test**

Extend the test to assert the chosen notes height and lightweight style values match the approved design.

**Step 2: Run test to verify it fails**

Run the same focused `xcodebuild test` command.

Expected: FAIL with mismatched presentation values.

**Step 3: Write minimal implementation**

Update `MemoryEditorPage` to:

- use the larger full-screen notes height
- remove the heavy inner rounded white card treatment
- keep photo thumbnails and footer actions intact

**Step 4: Run test to verify it passes**

Run the same focused `xcodebuild test` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift StreetStampsTests/MemoryEditorPresentationTests.swift
git commit -m "feat: expand fullscreen memory editor notes area"
```

### Task 3: Verify no regressions in related presentation tests

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: `StreetStampsTests/MemoryEditorPresentationTests.swift`

**Step 1: Run focused related tests**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/MemoryEditorPresentationTests
```

**Step 2: Run a broader smoke check**

Run:

```bash
xcodebuild build -quiet -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'
```

Expected: build succeeds with the updated layout.

**Step 3: Commit**

```bash
git add StreetStamps/MapView.swift StreetStampsTests/MemoryEditorPresentationTests.swift
git commit -m "test: cover fullscreen memory editor presentation"
```
