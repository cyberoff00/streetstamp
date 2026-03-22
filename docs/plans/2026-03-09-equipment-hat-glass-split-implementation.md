# Equipment Hat Glass Split Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split front accessories into independent hat and glass single-select slots while keeping the remaining accessory items as a multi-select category with renumbered asset references.

**Architecture:** Extend `RobotLoadout` with dedicated `hatId` and `glassId` fields while preserving `accessoryIds` for the remaining multi-select accessories. Update the avatar catalog, renderer, equipment view, and ownership logic so the UI exposes three categories with the correct selection behavior and layered rendering order `accessory -> glass -> hat`.

**Tech Stack:** Swift, SwiftUI, XCTest, JSON bundle catalog, Xcode project assets

---

### Task 1: Document target numbering and write failing tests

**Files:**
- Modify: `StreetStampsTests/UserScopedProfileStateStoreTests.swift`
- Create: `StreetStampsTests/EquipmentCatalogSplitTests.swift`
- Modify: `StreetStamps/AvatarCatalog.json`

**Step 1: Write the failing tests**

Add tests that assert:
- `RobotLoadout` encodes and decodes `hatId`, `glassId`, and `accessoryIds` independently.
- The bundled avatar catalog contains separate `hat`, `glass`, and `accessory` categories.
- `hat` and `glass` item ids start at `001` and map to `front_hat001...` / `front_glass001...`.
- Remaining `accessory` item ids start at `001` and continue using `front_ac001...`.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/EquipmentCatalogSplitTests -only-testing:StreetStampsTests/UserScopedProfileStateStoreTests`

Expected: FAIL because the loadout and catalog do not yet expose `hatId` / `glassId` or the split categories.

**Step 3: Write minimal implementation**

Update the catalog and model declarations only enough to satisfy the new test compile errors and first assertions.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and confirm the new tests pass before moving on.

**Step 5: Commit**

```bash
git add StreetStampsTests/UserScopedProfileStateStoreTests.swift StreetStampsTests/EquipmentCatalogSplitTests.swift StreetStamps/AvatarCatalog.json
git commit -m "test: cover hat and glass equipment split"
```

### Task 2: Update loadout, catalog access, and renderer layering

**Files:**
- Modify: `StreetStamps/AvatarRenderer.swift`
- Modify: `StreetStamps/GearCatalog.swift`

**Step 1: Write the failing test**

Extend the new catalog test file with assertions that:
- `RobotLoadout.normalizedForCurrentAvatar()` preserves `hatId`, `glassId`, and `accessoryIds`.
- Renderer catalog lookup resolves hat and glass items by category.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/EquipmentCatalogSplitTests`

Expected: FAIL because renderer and catalog access still only know about `accessory`.

**Step 3: Write minimal implementation**

Add `hatId` and `glassId` to `RobotLoadout`, keep `accessoryIds` for the multi-select leftovers, and update renderer helper methods and layer order to use the three categories.

**Step 4: Run test to verify it passes**

Run the same focused test command and confirm it passes.

**Step 5: Commit**

```bash
git add StreetStamps/AvatarRenderer.swift StreetStamps/GearCatalog.swift StreetStampsTests/EquipmentCatalogSplitTests.swift
git commit -m "feat: split avatar hat and glass loadout slots"
```

### Task 3: Update equipment UI and economy logic

**Files:**
- Modify: `StreetStamps/EquipmentView.swift`
- Modify: `StreetStamps/en.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hant.lproj/Localizable.strings`

**Step 1: Write the failing test**

Add assertions that ownership bootstrap and try-on missing-item detection handle `hat`, `glass`, and multi-select `accessory` separately.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/EquipmentCatalogSplitTests`

Expected: FAIL because economy and selection logic still treat accessories as a single category and multi-select.

**Step 3: Write minimal implementation**

Update category ordering, icons, selected-state logic, apply-selection behavior, ownership bootstrap, and try-on purchase planning so:
- `hat` is single-select.
- `glass` is single-select.
- `accessory` remains multi-select.

Add localization keys for the new category labels.

**Step 4: Run test to verify it passes**

Run the same focused test command and confirm it passes.

**Step 5: Commit**

```bash
git add StreetStamps/EquipmentView.swift StreetStamps/en.lproj/Localizable.strings StreetStamps/zh-Hans.lproj/Localizable.strings StreetStamps/zh-Hant.lproj/Localizable.strings StreetStampsTests/EquipmentCatalogSplitTests.swift
git commit -m "feat: add hat and glass equipment categories"
```

### Task 4: Verify assets, references, and regressions

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStampsTests/LocalizationCoverageTests.swift`
- Inspect: `StreetStamps/Assets.xcassets/人物装备/*`

**Step 1: Write the failing test**

Add coverage for any new localization keys and update friend equipment summary expectations if the UI now shows hat and glass separately.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LocalizationCoverageTests`

Expected: FAIL until new localization keys and any summary changes are wired.

**Step 3: Write minimal implementation**

Update remaining read paths and labels, then audit the asset catalog references so all renumbered item ids point at existing `front_hat`, `front_glass`, and `front_ac` imagesets.

**Step 4: Run test to verify it passes**

Run:
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/EquipmentCatalogSplitTests -only-testing:StreetStampsTests/UserScopedProfileStateStoreTests -only-testing:StreetStampsTests/LocalizationCoverageTests`
- `xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'`

Expected: Tests pass and build succeeds.

**Step 5: Commit**

```bash
git add StreetStamps/FriendsHubView.swift StreetStampsTests/LocalizationCoverageTests.swift StreetStamps/AvatarCatalog.json StreetStamps/AvatarRenderer.swift StreetStamps/EquipmentView.swift
git commit -m "feat: wire split accessory equipment across app"
```
