# Unified Memory Photo Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Route `JourneyMemoryNew` and `MemoryEditorSheet/Page` through the same photo editing path and prevent stale new-memory drafts from hiding preloaded images.

**Architecture:** Add a tiny shared state/bootstrap layer for memory photo editing, then reuse the existing `PhotoEditorView` queue flow from both entry points. Keep persistence in host screens, but ensure new media always passes through the shared editor before filenames are saved.

**Tech Stack:** SwiftUI, UIKit, XCTest, `PhotoStore`, `PHPhotoLibrary`

---

### Task 1: Add shared contracts and regression tests

**Files:**
- Create: `StreetStamps/UnifiedPhotoEditingFlow.swift`
- Modify: `StreetStampsTests/UnifiedPhotoEditingFlowTests.swift`
- Modify: `StreetStampsTests/MemoryEditorPresentationTests.swift`

**Step 1:** Add a pure queue model for edited/skipped/discarded image progression.

**Step 2:** Add a pure bootstrap helper for memory editor initialization, with preloaded new-memory images taking precedence over stale `"new"` drafts.

**Step 3:** Add tests for queue completion, CTA semantics, and preloaded-image precedence.

### Task 2: Unify `JourneyMemoryNew` media entry

**Files:**
- Modify: `StreetStamps/JourneyMemoryNew.swift`

**Step 1:** Replace direct camera/library persistence with pending editor images state.

**Step 2:** Present `PhotoEditorView` after camera/library dismissal and save only finalized editor output.

### Task 3: Fix `MemoryEditorSheet` bootstrap regression

**Files:**
- Modify: `StreetStamps/MapView.swift`

**Step 1:** Replace ad-hoc init branching with the shared bootstrap helper.

**Step 2:** Preserve existing edit-resume behavior for existing memories while preventing stale `"new"` draft data from hiding incoming preloaded images.

### Task 4: Verify focused behavior

**Files:**
- Test only

**Step 1:** Run focused XCTest targets for photo-flow and memory-editor presentation.

**Step 2:** Report what is fixed now and what still remains outside this patch, especially the Instagram-like text/crop interaction work.
