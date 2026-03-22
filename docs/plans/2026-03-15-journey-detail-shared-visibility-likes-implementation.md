# Journey Detail Shared Visibility Likes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reuse the original journey visibility and likes sheets on the journey memory detail page so the detail flow matches My Journeys instead of maintaining a duplicate implementation.

**Architecture:** Extract the original visibility and likes SwiftUI sheets plus lightweight presentation helpers into one shared file, then route `JourneyMemoryNew.swift` through those shared components. Keep network calls page-local where they already exist, and only share UI/presentation types that need to stay visually consistent.

**Tech Stack:** Swift, SwiftUI, XCTest, xcodebuild

---

### Task 1: Add the failing routing test

**Files:**
- Create: `StreetStampsTests/JourneyDetailSheetRoutePresentationTests.swift`
- Modify: `StreetStamps/SharedJourneySheets.swift`

**Step 1: Write the failing test**

Add tests for a new helper that decides the first sheet from like count:

```swift
func test_primaryTapPrefersLikesSheetWhenLikesExist() {
    XCTAssertEqual(
        JourneyDetailSheetRoutePresentation.primaryRoute(forLikesCount: 3),
        .likes
    )
}

func test_primaryTapFallsBackToVisibilityWhenNoLikesExist() {
    XCTAssertEqual(
        JourneyDetailSheetRoutePresentation.primaryRoute(forLikesCount: 0),
        .visibility
    )
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyDetailSheetRoutePresentationTests`

Expected: FAIL because `JourneyDetailSheetRoutePresentation` does not exist yet.

**Step 3: Write minimal implementation**

Add a small presentation enum/helper in the shared sheets file:

```swift
enum JourneyDetailSheetRoutePresentation {
    case visibility
    case likes

    static func primaryRoute(forLikesCount likesCount: Int) -> Self {
        likesCount > 0 ? .likes : .visibility
    }
}
```

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStampsTests/JourneyDetailSheetRoutePresentationTests.swift StreetStamps/SharedJourneySheets.swift
git commit -m "test: cover journey detail shared sheet routing"
```

### Task 2: Extract shared journey sheets

**Files:**
- Create: `StreetStamps/SharedJourneySheets.swift`
- Modify: `StreetStamps/MyJourneysView.swift`
- Test: `StreetStampsTests/JourneyVisibilityPolicyTests.swift`

**Step 1: Write the failing test**

Keep the existing `JourneyVisibilityPolicyTests` presentation assertion as the contract for `JourneyVisibilitySheetPresentation`.

**Step 2: Run test to verify it fails after removing local definitions**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyVisibilityPolicyTests`

Expected: FAIL until the moved definitions are restored in the new shared file.

**Step 3: Write minimal implementation**

Move these shared UI/presentation types into `SharedJourneySheets.swift`:
- `JourneyLiker`
- `JourneyVisibilitySheetAccentStyle`
- `JourneyVisibilitySheetOptionPresentation`
- `JourneyVisibilitySheetPresentation`
- `JourneyVisibilitySheet`
- `JourneyLikesSheet`
- `JourneySheetScaffold`

Update `MyJourneysView.swift` to consume the shared types and remove duplicate local definitions.

**Step 4: Run test to verify it passes**

Run the same targeted `JourneyVisibilityPolicyTests` command.

Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/SharedJourneySheets.swift StreetStamps/MyJourneysView.swift StreetStampsTests/JourneyVisibilityPolicyTests.swift
git commit -m "refactor: extract shared journey sheets"
```

### Task 3: Wire journey detail to shared sheets

**Files:**
- Modify: `StreetStamps/JourneyMemoryNew.swift`
- Modify: `StreetStamps/SharedJourneySheets.swift`
- Test: `StreetStampsTests/JourneyDetailSheetRoutePresentationTests.swift`

**Step 1: Write the failing test**

Use the routing test from Task 1 as the contract for the first-tap behavior.

**Step 2: Run test to verify current code does not satisfy the intended flow**

Run the targeted routing test command again before wiring the view.

Expected: PASS for helper coverage, but detail page still uses the old sheet until implementation is finished.

**Step 3: Write minimal implementation**

In `JourneyMemoryNew.swift`:
- replace the inline `visibilitySheet` UI with shared `JourneyVisibilitySheet`
- add local liker list loading/error state
- add a `JourneyLikesSheet` presentation path
- route status-chip taps through `JourneyDetailSheetRoutePresentation.primaryRoute(forLikesCount:)`
- keep existing visibility update backend sync and denial checks

**Step 4: Run test to verify it passes**

Run:
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyDetailSheetRoutePresentationTests`
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyVisibilityPolicyTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/JourneyMemoryNew.swift StreetStamps/SharedJourneySheets.swift StreetStampsTests/JourneyDetailSheetRoutePresentationTests.swift
git commit -m "feat: reuse shared journey sheets in detail page"
```

### Task 4: Verify integrated behavior

**Files:**
- Modify: none expected
- Test: `StreetStampsTests/JourneyDetailSheetRoutePresentationTests.swift`
- Test: `StreetStampsTests/JourneyVisibilityPolicyTests.swift`

**Step 1: Run targeted verification**

Run:
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyDetailSheetRoutePresentationTests`
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/JourneyVisibilityPolicyTests`

Expected: PASS.

**Step 2: Run a focused build smoke test**

Run: `xcodebuild build -quiet -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: BUILD SUCCEEDED.

**Step 3: Commit**

```bash
git add docs/plans/2026-03-15-journey-detail-shared-visibility-likes-design.md docs/plans/2026-03-15-journey-detail-shared-visibility-likes-implementation.md
git commit -m "docs: plan shared journey detail sheets"
```
