# Frontend Navigation Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace sidebar-based primary navigation with a five-tab layout, fold memories into a swipeable two-page Worldo tab, remove the standalone journeys landing page, and make child navigation rely on standard push/pop behavior.

**Architecture:** Keep the existing `TabView` shell, but remove sidebar state and promote `ProfileView` into a bottom tab. Rebuild `CollectionTabView` into a two-page Worldo pager that reuses the city and memory surfaces. Reuse journey-detail presentation from the existing journeys feature by linking to it from memory context instead of from a standalone top-level journeys page.

**Tech Stack:** SwiftUI, `NavigationStack`, XCTest, existing StreetStamps view models and environment objects

---

### Task 1: Lock Down Navigation Expectations

**Files:**
- Modify: `StreetStampsTests/MainTabLayoutTests.swift`
- Modify: `StreetStampsTests/TabRenderPolicyTests.swift`

**Step 1: Write the failing tests**

- Update bottom-tab order expectations to `start, cities, lifelog, friends, profile`.
- Update icon assertions to match the new visible tab set.
- Extend render-policy expectations if `profile` behaves differently from the removed `memory` tab.

**Step 2: Run tests to verify failure**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/MainTabLayoutTests -only-testing:StreetStampsTests/TabRenderPolicyTests`

Expected: failures showing the old tab order and any stale assumptions about retained tabs.

**Step 3: Write minimal implementation**

- Update `MainTabLayout.bottomTabs`.
- Update any supporting enum or render-policy helpers that still assume `memory` is top-level.

**Step 4: Run the focused tests to verify they pass**

Run the same `xcodebuild test` command.

Expected: both test classes pass.

**Step 5: Commit**

```bash
git add StreetStampsTests/MainTabLayoutTests.swift StreetStampsTests/TabRenderPolicyTests.swift StreetStamps/MainTab.swift StreetStamps/SidebarNavigation.swift
git commit -m "test: update tab navigation expectations"
```

### Task 2: Remove Sidebar-Driven Primary Navigation

**Files:**
- Modify: `StreetStamps/MainTab.swift`
- Modify: `StreetStamps/SidebarNavigation.swift`
- Search/reference: `StreetStamps/AppFlowCoordinator` usages if sidebar requests remain

**Step 1: Write the failing test or assertion surface**

- If there is no clean UI test hook, rely on updated unit tests plus compile-time removal of sidebar-only paths.
- Add a small unit test only if a pure helper can express the new allowed top-level tabs.

**Step 2: Run targeted tests/build to verify breakage**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: compile errors or stale references to sidebar-only state after initial code removal.

**Step 3: Write minimal implementation**

- Remove `showSidebar`, sidebar gestures, overlay launcher, and sidebar sheets from `MainTabView`.
- Remove `memory` from the top-level `TabView`.
- Add `ProfileView` as the last tab inside a `NavigationStack`.
- Leave any non-primary sidebar destinations for later cleanup only if they are no longer reachable.

**Step 4: Run targeted build**

Run the same `xcodebuild build` command.

Expected: project builds with no sidebar references required by `MainTabView`.

**Step 5: Commit**

```bash
git add StreetStamps/MainTab.swift StreetStamps/SidebarNavigation.swift
git commit -m "feat: remove sidebar from primary navigation"
```

### Task 3: Convert Worldo Into a Two-Page Swipe Container

**Files:**
- Modify: `StreetStamps/CollectionTabView.swift`
- Reference: `StreetStamps/CityStampLibraryView.swift`
- Reference: `StreetStamps/JourneyMemoryNew.swift`

**Step 1: Write the failing test**

- Add a small view-model/helper test if you extract page metadata for Worldo.
- Otherwise use compile/build verification and existing tab tests.

**Step 2: Run targeted build**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: breakage while replacing the old segmented control structure.

**Step 3: Write minimal implementation**

- Replace segmented control state with a two-page pager model.
- Use `.tabViewStyle(.page(indexDisplayMode: ...))` or an equivalent horizontal paging container.
- Host `CityStampLibraryView` on page 1 and `JourneyMemoryMainView` on page 2.
- Remove the `journeys` segment and any onboarding hook tied only to that segment.

**Step 4: Run targeted build/tests**

Run the same build command and rerun the focused tab tests.

Expected: build succeeds and tab tests remain green.

**Step 5: Commit**

```bash
git add StreetStamps/CollectionTabView.swift StreetStamps/MainTab.swift StreetStampsTests/MainTabLayoutTests.swift StreetStampsTests/TabRenderPolicyTests.swift
git commit -m "feat: make worldo a swipeable two-page tab"
```

### Task 4: Rehome Journey Entry Into Memory Context

**Files:**
- Modify: `StreetStamps/JourneyMemoryNew.swift`
- Reference: `StreetStamps/MyJourneysView.swift`
- Reference: `StreetStamps/MemoryEditorKit.swift`

**Step 1: Write the failing test**

- Add a focused unit test only if a helper is extracted to resolve the linked journey for a memory.
- Otherwise rely on build verification and, if possible, an existing memory-detail test target.

**Step 2: Run targeted build/tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/MemoryEditorPresentationTests -only-testing:StreetStampsTests/JourneyMemoryDetailExportPresentationTests`

Expected: either baseline pass or failures once memory-detail UI is changed.

**Step 3: Write minimal implementation**

- Identify the memory detail surface that represents the "overall memory" content.
- Add a journey entry block above that content when the memory belongs to a journey that can be opened.
- Reuse the existing journey detail/deepview destination instead of reimplementing journey rendering.
- Remove or orphan-proof any top-level entry that still points users to the old standalone journeys page.

**Step 4: Run targeted tests/build**

Run the same focused tests plus a build if needed.

Expected: tests pass and the journey entry compiles cleanly in memory detail.

**Step 5: Commit**

```bash
git add StreetStamps/JourneyMemoryNew.swift StreetStamps/MyJourneysView.swift
git commit -m "feat: link journey deepviews from memory detail"
```

### Task 5: Restore Standard Back Navigation Behavior

**Files:**
- Modify: `StreetStamps/JourneyMemoryNew.swift`
- Modify: `StreetStamps/MyJourneysView.swift`
- Modify: `StreetStamps/CityDeepView.swift`
- Modify: any other touched child page that still uses right-top back affordances as primary exit

**Step 1: Write the failing test or verification target**

- Use build verification plus manual inspection points, because interactive pop is largely behavioral.

**Step 2: Run build**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: baseline compile before cleanup.

**Step 3: Write minimal implementation**

- Remove right-top back buttons where they are redundant.
- Stop using patterns that disable interactive pop unless absolutely necessary.
- Keep left-leading dismiss controls only where a custom branded header is still needed.

**Step 4: Run build and relevant tests**

Run the same build command, plus any touched focused test classes.

Expected: clean build and no regressions in touched tests.

**Step 5: Commit**

```bash
git add StreetStamps/JourneyMemoryNew.swift StreetStamps/MyJourneysView.swift StreetStamps/CityDeepView.swift
git commit -m "feat: favor gesture-friendly child navigation"
```

### Task 6: Final Verification

**Files:**
- Verify all modified files from previous tasks

**Step 1: Run focused tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/MainTabLayoutTests -only-testing:StreetStampsTests/TabRenderPolicyTests -only-testing:StreetStampsTests/MemoryEditorPresentationTests -only-testing:StreetStampsTests/JourneyMemoryDetailExportPresentationTests`

Expected: all selected tests pass.

**Step 2: Run app build**

Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: build succeeds.

**Step 3: Sanity-check changed surfaces manually**

- Confirm tab order is `Home -> Worldo -> Footprints -> Friends -> My Profile`.
- Confirm `Worldo` only has two horizontally swipeable pages.
- Confirm there is no standalone journeys landing page reachable from primary navigation.
- Confirm a memory can open its linked journey deepview.
- Confirm child routes can be exited with the standard back swipe where expected.

**Step 4: Commit**

```bash
git add StreetStamps StreetStampsTests docs/plans
git commit -m "feat: redesign primary navigation and worldo flow"
```
