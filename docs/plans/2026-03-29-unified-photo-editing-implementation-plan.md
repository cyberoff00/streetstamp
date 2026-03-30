# Unified Photo Editing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build one shared image editing flow for camera and photo-library input, then wire it into every app surface that captures or uploads photos.

**Architecture:** Reuse the existing camera and photo-library acquisition code, but insert a shared editing queue between acquisition and host-feature persistence. Refactor the current `PhotoEditViewController` into a proper full-screen editor with rotate, tap-to-place text, and explicit crop mode, then route feature screens through that shared flow.

**Tech Stack:** SwiftUI, UIKit, `UIImagePickerController`, `PHPickerViewController`, `UIGraphicsImageRenderer`, `PhotoStore`, XCTest

---

### Task 1: Document Current Entry Points

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Modify: `StreetStamps/JourneyMemoryNew.swift`
- Modify: `StreetStamps/SharingCard.swift`
- Modify: `StreetStamps/PostcardComposerView.swift`

**Step 1: Identify each camera and photo-library call site**

Run: `rg -n "SystemCameraPicker\\(|PhotoLibraryPicker\\(" StreetStamps/MapView.swift StreetStamps/JourneyMemoryNew.swift StreetStamps/SharingCard.swift StreetStamps/PostcardComposerView.swift`
Expected: a concise list of host entry points that must adopt the new flow

**Step 2: Mark each host callback shape**

Run: `rg -n "onImage:|onImages:|saveJPEG\\(" StreetStamps/MapView.swift StreetStamps/JourneyMemoryNew.swift StreetStamps/SharingCard.swift StreetStamps/PostcardComposerView.swift`
Expected: the exact places where raw images are currently accepted or persisted

**Step 3: Commit**

```bash
git add docs/plans/2026-03-29-unified-photo-editing-design.md docs/plans/2026-03-29-unified-photo-editing-implementation-plan.md
git commit -m "docs: plan unified photo editing flow"
```

### Task 2: Add Queue-Oriented Shared Models

**Files:**
- Create: `StreetStamps/UnifiedPhotoEditingFlow.swift`
- Test: `StreetStampsTests/UnifiedPhotoEditingFlowTests.swift`

**Step 1: Write the failing test**

```swift
func test_queueCompletion_returnsEditedAndSkippedItems_only() {
    var flow = PhotoEditingQueueState(items: [
        .init(id: "1", original: UIImage()),
        .init(id: "2", original: UIImage()),
        .init(id: "3", original: UIImage())
    ])

    flow.completeCurrent(with: UIImage())
    flow.skipCurrent()
    flow.discardCurrent()

    XCTAssertEqual(flow.finalizedItems.count, 2)
    XCTAssertTrue(flow.isFinished)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/UnifiedPhotoEditingFlowTests`
Expected: FAIL because the shared queue state does not exist yet

**Step 3: Write minimal implementation**

Create queue state types that model:

- source item identity
- current index
- edited output
- skipped original
- discarded item
- completion state

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/UnifiedPhotoEditingFlowTests`
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/UnifiedPhotoEditingFlow.swift StreetStampsTests/UnifiedPhotoEditingFlowTests.swift
git commit -m "feat: add shared photo editing queue state"
```

### Task 3: Refactor the Single-Image Editor

**Files:**
- Modify: `StreetStamps/PhotoCropRotateView.swift`

**Step 1: Add editor modes**

Implement explicit modes for:

- viewing
- text placement
- crop
- text selection

**Step 2: Replace center-insert text with tap-to-place text**

When the user taps the text tool:

- arm text-placement mode
- wait for a tap on the image surface
- create the overlay at the tapped location

**Step 3: Add text selection and deletion**

Selected overlays should expose a simple delete affordance and support editing the text content.

**Step 4: Add explicit crop mode**

Replace the current implicit viewport crop behavior with a visible crop interaction model and a crop confirmation path.

**Step 5: Preserve final image rendering**

Ensure the export path still composites:

- current rotation
- cropped image result
- text overlays in their final positions

**Step 6: Commit**

```bash
git add StreetStamps/PhotoCropRotateView.swift
git commit -m "feat: rebuild unified single-photo editor"
```

### Task 4: Build the Editing Queue Presenter

**Files:**
- Modify: `StreetStamps/UnifiedPhotoEditingFlow.swift`
- Modify: `StreetStamps/PhotoCropRotateView.swift`
- Test: `StreetStampsTests/UnifiedPhotoEditingFlowTests.swift`

**Step 1: Write the failing test**

```swift
func test_lastItem_usesDoneAllSemantics() {
    let state = PhotoEditingQueueState(items: [.stub("1")])
    XCTAssertEqual(state.primaryActionTitle, "Done All")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/UnifiedPhotoEditingFlowTests`
Expected: FAIL because CTA semantics are not modeled yet

**Step 3: Implement queue navigation**

Add presenter behavior for:

- `completeCurrent`
- `skipCurrent`
- `discardCurrent`
- `cancelQueue`
- queue progress labels
- last-item CTA handling

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/UnifiedPhotoEditingFlowTests`
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/UnifiedPhotoEditingFlow.swift StreetStamps/PhotoCropRotateView.swift StreetStampsTests/UnifiedPhotoEditingFlowTests.swift
git commit -m "feat: add photo editing queue presentation"
```

### Task 5: Integrate MemoryEditor Surfaces

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: `StreetStampsTests/MemoryEditorPresentationTests.swift`

**Step 1: Write the failing test**

Add a focused test that captures the new contract in a small pure helper, for example:

```swift
func test_newMedia_requiresEditing_beforePersistence() {
    XCTAssertTrue(MemoryEditorMediaPolicy.requiresEditingBeforeSave)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/MemoryEditorPresentationTests`
Expected: FAIL because the helper or contract does not exist

**Step 3: Route camera and library through the shared editing flow**

Update both `MemoryEditorSheet` and `MemoryEditorPage` so that:

- capture returns an image queue with one item
- library returns the selected image queue
- final edited outputs are the only images persisted to `PhotoStore`

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/MemoryEditorPresentationTests`
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/MapView.swift StreetStampsTests/MemoryEditorPresentationTests.swift
git commit -m "feat: route memory editor media through shared editor"
```

### Task 6: Integrate Journey Memory Entry Points

**Files:**
- Modify: `StreetStamps/JourneyMemoryNew.swift`

**Step 1: Replace direct persistence paths**

Route all new image acquisition in this file through the shared editing flow before saving filenames.

**Step 2: Verify memory creation still works**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/MemoryEditorPresentationTests`
Expected: PASS for the existing memory-editor tests after the integration

**Step 3: Commit**

```bash
git add StreetStamps/JourneyMemoryNew.swift
git commit -m "feat: unify journey memory photo editing flow"
```

### Task 7: Integrate Sharing Card and Postcard Upload

**Files:**
- Modify: `StreetStamps/SharingCard.swift`
- Modify: `StreetStamps/PostcardComposerView.swift`

**Step 1: Replace raw image acceptance with the shared flow**

Ensure both features:

- launch the shared editor after capture or selection
- only receive finalized image output

**Step 2: Manually verify both surfaces**

Check:

- single camera image enters editor
- single and multi-select library flows enter editor queue
- final result returns to the host screen

**Step 3: Commit**

```bash
git add StreetStamps/SharingCard.swift StreetStamps/PostcardComposerView.swift
git commit -m "feat: unify sharing and postcard photo editing"
```

### Task 8: Verify Shared Flow End to End

**Files:**
- Test: `StreetStampsTests/UnifiedPhotoEditingFlowTests.swift`
- Test: `StreetStampsTests/MemoryEditorPresentationTests.swift`

**Step 1: Run focused automated tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/UnifiedPhotoEditingFlowTests -only-testing:StreetStampsTests/MemoryEditorPresentationTests`
Expected: PASS

**Step 2: Perform manual verification**

Manually check:

- camera -> editor -> host feature
- library multi-select -> queue editor -> host feature
- tap-to-place text
- text delete
- crop mode
- rotate
- queue cancel confirmation
- last-item `Done All`

**Step 3: Commit**

```bash
git add StreetStampsTests/UnifiedPhotoEditingFlowTests.swift StreetStampsTests/MemoryEditorPresentationTests.swift
git commit -m "test: cover unified photo editing flow"
```
