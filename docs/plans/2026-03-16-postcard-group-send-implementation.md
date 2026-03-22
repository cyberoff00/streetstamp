# Postcard Group Send Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add postcard group sending with up to three recipients, a new postcard-page compose entry, and sent-box aggregation that shows one postcard card with multiple recipient names.

**Architecture:** Reuse the existing postcard compose and preview flow, but replace the single-recipient assumption with a shared recipient list and batch send identifier. The UI stays centered on one postcard draft while `PostcardCenter` manages per-recipient send attempts and the sent box groups matching backend records into a single presentation item.

**Tech Stack:** SwiftUI, async/await, existing `BackendAPIClient`, `PostcardCenter`, `UserDefaults` draft persistence, XCTest.

---

### Task 1: Lock sent-box grouping behavior with tests

**Files:**
- Modify: `StreetStampsTests/PostcardInboxPresentationTests.swift`
- Modify: `StreetStamps/PostcardInboxPresentation.swift`

**Step 1: Write the failing test**

Add a test that builds three sent postcard DTOs with the same batch/group identifier and asserts the presentation layer returns one sent row with three recipient names.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardInboxPresentationTests`
Expected: FAIL because grouping support does not exist yet.

**Step 3: Write minimal implementation**

Add a sent-row grouping helper in `PostcardInboxPresentation.swift` that collapses matching items into one presentation model.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStampsTests/PostcardInboxPresentationTests.swift StreetStamps/PostcardInboxPresentation.swift
git commit -m "test: cover postcard sent box group aggregation"
```

### Task 2: Lock local group draft behavior with tests

**Files:**
- Modify: `StreetStampsTests/PostcardSendCompletionPresentationTests.swift`
- Modify: `StreetStampsTests/PostcardSendErrorPresentationTests.swift`
- Modify: `StreetStamps/PostcardDraftStore.swift`
- Modify: `StreetStamps/PostcardCenter.swift`

**Step 1: Write the failing test**

Add tests that create a draft with multiple recipients and verify:
- recipients persist and reload;
- partial success is reflected as a batch state;
- retry targets only unsent recipients.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardSendCompletionPresentationTests -only-testing:StreetStampsTests/PostcardSendErrorPresentationTests`
Expected: FAIL because draft/state models are still 1:1.

**Step 3: Write minimal implementation**

Add recipient-list and batch metadata to the draft model and update `PostcardCenter` state transitions accordingly.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStampsTests/PostcardSendCompletionPresentationTests.swift StreetStampsTests/PostcardSendErrorPresentationTests.swift StreetStamps/PostcardDraftStore.swift StreetStamps/PostcardCenter.swift
git commit -m "feat: add postcard group draft state"
```

### Task 3: Lock composer recipient UX with tests

**Files:**
- Create: `StreetStampsTests/PostcardComposerRecipientsTests.swift`
- Modify: `StreetStamps/PostcardComposerView.swift`
- Modify: `StreetStamps/FriendsHubView.swift`

**Step 1: Write the failing test**

Add tests for:
- composer launched from postcard page starts with zero recipients;
- composer launched from friend profile starts with one recipient;
- recipient count cannot exceed three.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardComposerRecipientsTests`
Expected: FAIL because the composer only supports one `friendID`.

**Step 3: Write minimal implementation**

Refactor composer inputs to accept a recipient list and render the new top recipient section with add/remove actions.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStampsTests/PostcardComposerRecipientsTests.swift StreetStamps/PostcardComposerView.swift StreetStamps/FriendsHubView.swift
git commit -m "feat: add postcard composer recipient management"
```

### Task 4: Implement inbox entry and preview/send plumbing

**Files:**
- Modify: `StreetStamps/PostcardInboxView.swift`
- Modify: `StreetStamps/PostcardComposerView.swift`
- Modify: `StreetStamps/PostcardPreviewView.swift`
- Modify: `StreetStamps/PostcardModels.swift`
- Modify: `StreetStamps/BackendAPIClient.swift`

**Step 1: Write the failing test**

Add tests for preview/send payload construction so one logical draft can create multiple recipient send requests with shared batch metadata.

**Step 2: Run test to verify it fails**

Run the targeted postcard-related tests.
Expected: FAIL because payloads are still single-recipient.

**Step 3: Write minimal implementation**

- Add the top-right envelope button to the postcard page header.
- Add recipient-aware preview inputs.
- Expand the request/DTO models with batch metadata and recipient information needed for grouping.

**Step 4: Run test to verify it passes**

Run the same targeted postcard test suite.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/PostcardInboxView.swift StreetStamps/PostcardComposerView.swift StreetStamps/PostcardPreviewView.swift StreetStamps/PostcardModels.swift StreetStamps/BackendAPIClient.swift
git commit -m "feat: wire postcard group send entry and payloads"
```

### Task 5: Full verification

**Files:**
- Modify: any touched postcard files from earlier tasks

**Step 1: Run focused postcard tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardInboxPresentationTests -only-testing:StreetStampsTests/PostcardComposerRecipientsTests -only-testing:StreetStampsTests/PostcardSendCompletionPresentationTests -only-testing:StreetStampsTests/PostcardSendErrorPresentationTests`
Expected: PASS.

**Step 2: Run broader build verification**

Run: `xcodebuild build -quiet -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`
Expected: PASS.

**Step 3: Review requirements checklist**

Verify:
- postcard page has a top-right envelope entry;
- inbox-entry compose starts empty;
- friend-entry compose starts prefilled;
- max recipients is three;
- sent box shows one card with multiple names;
- 1:1 sending still works.

**Step 4: Commit**

```bash
git add StreetStamps docs/plans StreetStampsTests
git commit -m "feat: add postcard group send flow"
```
