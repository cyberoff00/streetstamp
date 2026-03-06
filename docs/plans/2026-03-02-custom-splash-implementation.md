# Custom Splash + Warmup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a 1.5-second custom splash screen and run startup warmup for root view readiness and city thumbnail cache priming.

**Architecture:** Add a splash overlay on top of the existing root app content so current startup logic remains intact. Introduce a dedicated warmup service that opportunistically loads top city thumbnails into memory cache in the background. Keep all warmup tasks best-effort and non-blocking.

**Tech Stack:** SwiftUI, UIKit (`UIImage`), existing app services (`CityCache`, `CityImageMemoryCache`), async `Task`.

---

### Task 1: Add splash and warmup state tests (TDD red)

**Files:**
- Create: `StreetStamps/StartupWarmupService.swift`
- Create: `StreetStamps/AppSplashView.swift`
- Test: `StreetStampsTests/` (skip if no XCTest target)

**Step 1: Write the failing test**
- If an XCTest target exists, add tests for:
- `StartupWarmupService` selects up to N thumbnail paths.
- Duplicate paths are removed.
- Missing paths are ignored.

**Step 2: Run test to verify it fails**
Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`
Expected: FAIL on missing service/types.

**Step 3: Write minimal implementation**
- Add pure helper API in warmup service to make selection testable.

**Step 4: Run test to verify it passes**
Run same command and expect PASS for added tests.

**Step 5: Commit**
```bash
git add StreetStamps/StartupWarmupService.swift StreetStamps/AppSplashView.swift
git commit -m "feat: add custom splash and startup warmup scaffolding"
```

### Task 2: Implement splash UI

**Files:**
- Create: `StreetStamps/AppSplashView.swift`

**Step 1: Write the failing test**
- If UI tests unavailable, define acceptance checks in comments and verify by build/runtime.

**Step 2: Run failing check**
- Build and run current app, confirm splash not present yet.

**Step 3: Write minimal implementation**
- Build SwiftUI splash view with:
- Brand green background
- Center logo mark animation
- Wordmark/tagline fade-in
- No user interaction requirement

**Step 4: Verify**
Run: `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`
Expected: BUILD SUCCEEDED.

**Step 5: Commit**
```bash
git add StreetStamps/AppSplashView.swift
git commit -m "feat: implement animated app splash view"
```

### Task 3: Implement warmup service

**Files:**
- Create: `StreetStamps/StartupWarmupService.swift`
- Modify: `StreetStamps/CityStampLibraryView.swift` (if helper exposure needed)

**Step 1: Write the failing test**
- Add/define expected behavior for path selection and cache fill fallback.

**Step 2: Run test to verify it fails**
- Run target tests/build and verify missing implementation failures.

**Step 3: Write minimal implementation**
- Add service that:
- Reads `CityCache.cachedCities`
- Selects prioritized thumbnail relative paths
- Resolves file paths via `CityThumbnailCache.resolveFullPath`
- Loads `UIImage(contentsOfFile:)` off-main-thread
- Writes to `CityImageMemoryCache`

**Step 4: Verify pass**
- Build app and run smoke on simulator.

**Step 5: Commit**
```bash
git add StreetStamps/StartupWarmupService.swift
git commit -m "perf: preload city thumbnails during splash"
```

### Task 4: Integrate splash gate in app root

**Files:**
- Modify: `StreetStamps/StreetStampsApp.swift`

**Step 1: Write the failing test**
- If no test harness, define runtime acceptance checks:
- Splash visible for 1.5s.
- Existing Intro/Main flow still works.

**Step 2: Run failing check**
- Launch app and confirm old behavior has no splash.

**Step 3: Write minimal implementation**
- Add root overlay state:
- `showSplash = true`
- `onAppear` starts warmup and schedules hide after 1.5s
- Keep existing environment/task/onOpenURL/fullScreenCover behavior unchanged.

**Step 4: Verify**
Run:
- `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`
- Manual launch check on simulator.

**Step 5: Commit**
```bash
git add StreetStamps/StreetStampsApp.swift
git commit -m "feat: show splash for 1.5s and start startup warmup"
```

### Task 5: Final verification

**Files:**
- Modify: `docs/plans/2026-03-02-custom-splash-implementation.md` (optional validation notes)

**Step 1: Run full verification**
Run:
- `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

**Step 2: Manual checklist**
- Cold launch shows splash and auto-dismisses at ~1.5s.
- IntroSlides and MainTab route unchanged.
- Open Cities tab: thumbnails load faster with less placeholder flash.

**Step 3: Commit**
```bash
git add docs/plans/2026-03-02-custom-splash-implementation.md
git commit -m "docs: add splash warmup verification notes"
```
