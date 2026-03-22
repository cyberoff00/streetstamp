# City Render Cache Scope Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make city thumbnail render cache user-scoped and context-safe so city cards stop missing disk cache after account switching or friend preview flows.

**Architecture:** Replace the global thumbnail-directory singleton with an explicit render-cache store bound to a specific `StoragePath.thumbnailsDir`. Route city-card render cache reads/writes through that store, inject/rebind it from the active app and friend-preview contexts, and keep legacy thumbnail fallback isolated from the new render-cache path. Validate the refactor with focused tests around scoped path resolution and cache reuse behavior.

**Tech Stack:** Swift, SwiftUI, XCTest, MapKit, UIKit

---

### Task 1: Document the current failure with a focused test

**Files:**
- Modify: `StreetStampsTests/CityThumbnailPersistenceTests.swift`

**Step 1: Write the failing test**

Add a test that creates two render-cache stores pointing at different thumbnail directories, writes the same render key into one store, and asserts the other store cannot see it.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CityThumbnailPersistenceTests`
Expected: FAIL because current path resolution is global and not per-store.

**Step 3: Write minimal implementation**

Introduce the smallest API surface needed for a store instance to resolve `renderCacheRelativePath(forKey:)` within its own root.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStampsTests/CityThumbnailPersistenceTests.swift StreetStamps/CityCache.swift
git commit -m "test: cover scoped city render cache paths"
```

### Task 2: Add a dedicated user-scoped render cache store

**Files:**
- Modify: `StreetStamps/CityCache.swift`

**Step 1: Write the failing test**

Extend the test coverage to assert a render cache store can save and reload a rendered image by key without touching global mutable state.

**Step 2: Run test to verify it fails**

Run the focused thumbnail persistence test target.
Expected: FAIL because saving and loading still depends on `sharedThumbnailsDir`.

**Step 3: Write minimal implementation**

Create `CityRenderCacheStore` in `StreetStamps/CityCache.swift` or a nearby cache-focused file. Give it:

```swift
final class CityRenderCacheStore {
    init(rootDir: URL, fm: FileManager = .default)
    func relativePath(forKey key: String) -> String
    func fullPath(forRelativePath relativePath: String) -> String?
    func exists(forKey key: String) -> Bool
    func image(forKey key: String) -> UIImage?
    func save(_ image: UIImage, forKey key: String)
}
```

Do not use static mutable directory state inside this store.

**Step 4: Run test to verify it passes**

Run the focused thumbnail persistence tests again.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/CityCache.swift StreetStampsTests/CityThumbnailPersistenceTests.swift
git commit -m "feat: add scoped city render cache store"
```

### Task 3: Move city-card render cache reads and writes onto the store

**Files:**
- Modify: `StreetStamps/CityStampLibraryView.swift`
- Modify: `StreetStamps/StartupWarmupService.swift`

**Step 1: Write the failing test**

Add a test that loads a city card image through `CityThumbnailLoader` using an injected store and verifies it reads the prewritten scoped cache entry instead of falling through to render-on-demand.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CityThumbnailPersistenceTests`
Expected: FAIL because `CityThumbnailLoader` still uses static helpers.

**Step 3: Write minimal implementation**

Change `CityThumbnailLoader` and `StartupWarmupService` to accept a `CityRenderCacheStore` dependency. Route:
- render cache existence checks
- disk image loads
- rendered image saves
- warmup prepopulation

through that store. Keep legacy `routePath/basePath` fallback logic separate.

**Step 4: Run test to verify it passes**

Run the focused tests again.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/CityStampLibraryView.swift StreetStamps/StartupWarmupService.swift StreetStampsTests/CityThumbnailPersistenceTests.swift
git commit -m "refactor: inject scoped city render cache store"
```

### Task 4: Rebind scoped cache stores from app and friend contexts

**Files:**
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/CityStampLibraryView.swift`

**Step 1: Write the failing test**

Add or update a regression test to cover friend-preview isolation, asserting that creating a friend-preview cache context does not alter the main context’s render-cache root.

**Step 2: Run test to verify it fails**

Run the focused thumbnail persistence test target.
Expected: FAIL because contexts still share global path state.

**Step 3: Write minimal implementation**

Instantiate one render-cache store per active `StoragePath.thumbnailsDir`:
- main app state owns one and replaces it on account switch
- friend preview owns its own store
- `CityStampLibraryView` reads it from the environment or another explicit injection point

Ensure `rebind(paths:)` updates the active cache store.

**Step 4: Run test to verify it passes**

Run the focused tests again.
Expected: PASS.

**Step 5: Commit**

```bash
git add StreetStamps/StreetStampsApp.swift StreetStamps/FriendsHubView.swift StreetStamps/CityStampLibraryView.swift StreetStampsTests/CityThumbnailPersistenceTests.swift
git commit -m "fix: isolate city render cache per context"
```

### Task 5: Verify no regressions in existing city cache load paths

**Files:**
- Test: `StreetStampsTests/CityCacheLoadOrderTests.swift`
- Test: `StreetStampsTests/CityCacheCallsiteTests.swift`
- Test: `StreetStampsTests/CityThumbnailPersistenceTests.swift`

**Step 1: Run focused verification**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CityThumbnailPersistenceTests -only-testing:StreetStampsTests/CityCacheLoadOrderTests -only-testing:StreetStampsTests/CityCacheCallsiteTests
```

Expected: PASS.

**Step 2: Run broader regression coverage if time permits**

Run:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests
```

Expected: PASS or a short list of unrelated existing failures.

**Step 3: Commit**

```bash
git add StreetStampsTests/CityThumbnailPersistenceTests.swift StreetStampsTests/CityCacheLoadOrderTests.swift StreetStampsTests/CityCacheCallsiteTests.swift
git commit -m "test: verify scoped city render cache behavior"
```
