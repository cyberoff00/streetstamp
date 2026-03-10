# City Thumbnail Persistent Cache Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move city card thumbnails from view-time live rendering to persistent render-keyed caching with warmup so repeated page entries can show cached images immediately.

**Architecture:** Keep the existing snapshot renderer, but introduce a stable render key plus disk-backed lookup/write path. City thumbnail views will read memory first, disk second, and only render on cache miss. The city library view model will trigger a small background warmup for the top cities after loading.

**Tech Stack:** Swift, SwiftUI, XCTest, MapKit, UIKit

---

### Task 1: Lock render key and file naming behavior with tests

**Files:**
- Create: `StreetStampsTests/CityThumbnailPersistenceTests.swift`

**Step 1: Write the failing test**

Add tests that assert:
- render keys change when appearance changes
- render keys change when route content changes
- file names are stable and sanitized

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination "platform=iOS Simulator,name=iPhone 16,OS=18.3.1" -only-testing:StreetStampsTests/CityThumbnailPersistenceTests`

Expected: FAIL because the render key API does not exist yet.

**Step 3: Write minimal implementation**

Add a render-key helper in the thumbnail code path and expose a testable file-name helper.

**Step 4: Run test to verify it passes**

Run the same command and confirm the new tests pass.

### Task 2: Implement persistent render-keyed cache lookup and writes

**Files:**
- Modify: `StreetStamps/CityStampLibraryView.swift`
- Modify: `StreetStamps/CityCache.swift`

**Step 1: Write the failing test**

Extend tests to assert that a render key maps to a predictable relative path in the thumbnails directory.

**Step 2: Run test to verify it fails**

Run the same focused test target and confirm the path lookup fails.

**Step 3: Write minimal implementation**

Change city thumbnail loading to:
- compute a stable render key
- check memory cache
- check disk using a render-key-derived filename
- write the rendered image to disk on cache miss

**Step 4: Run test to verify it passes**

Run the focused test target and confirm green.

### Task 3: Warm top city thumbnails after city library load

**Files:**
- Modify: `StreetStamps/CityLibraryVM.swift`
- Modify: `StreetStamps/CityStampLibraryView.swift`
- Modify: `StreetStamps/StartupWarmupService.swift`

**Step 1: Write the failing test**

Skip if there is no clean unit seam for warmup ordering. Keep the warmup logic small and deterministic.

**Step 2: Write minimal implementation**

Trigger background warmup for the top loaded cities using the new render-keyed cache API, reusing in-flight work and keeping concurrency limited.

**Step 3: Run verification**

Run focused tests plus a simulator build to confirm the new cache path compiles and the app still builds.
