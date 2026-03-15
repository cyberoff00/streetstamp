# Equipment Shoes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add the new front avatar assets to the correct equipment groups and ship a fully functional `shoes` equipment zone.

**Architecture:** The change stays data-driven. `AvatarCatalog.json` and `fallbackCatalog()` define the catalog, `RobotLoadout` and `RobotRendererView` carry and render the equipped shoes, and `EquipmentView` exposes the new category as the last zone with the existing purchase/try-on flows.

**Tech Stack:** Swift, SwiftUI, XCTest, Xcode asset catalogs

---

### Task 1: Lock the new behavior with tests

**Files:**
- Modify: `StreetStampsTests/EquipmentCatalogSplitTests.swift`

**Step 1: Write the failing test**

Add tests that assert:
- `RobotLoadout` round-trips `shoesId`
- the catalog contains a `shoes` category using `shoesId`
- the imported front assets are present in the expected groups, including `front_shoes001`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/EquipmentCatalogSplitTests`
Expected: FAIL because `shoes` does not exist yet.

**Step 3: Write minimal implementation**

Extend the catalog, loadout, renderer, equipment UI ordering, and localized labels just enough to satisfy the tests.

**Step 4: Run test to verify it passes**

Run the same targeted command and confirm `EquipmentCatalogSplitTests` pass.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-15-equipment-shoes-design.md docs/plans/2026-03-15-equipment-shoes-implementation.md StreetStampsTests/EquipmentCatalogSplitTests.swift StreetStamps/AvatarCatalog.json StreetStamps/GearCatalog.swift StreetStamps/AvatarRenderer.swift StreetStamps/EquipmentView.swift StreetStamps/Assets.xcassets StreetStamps/*.lproj/Localizable.strings
git commit -m "feat: add shoes equipment category"
```
