# Six Equipment Assets Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 6 newly provided equipment images to the existing equipment area and append them to the correct asset/catalog sequences.

**Architecture:** The change stays fully data-driven. New image assets are added under `StreetStamps/Assets.xcassets/人物装备/`, `AvatarCatalog.json` exposes them to the equipment UI, and `AvatarCatalogStore.fallbackCatalog()` mirrors the same entries so runtime fallback behavior stays aligned.

**Tech Stack:** Swift, XCTest, Xcode asset catalogs, JSON catalog data

---

### Task 1: Lock the new assets with a failing catalog test

**Files:**
- Modify: `StreetStampsTests/EquipmentCatalogSplitTests.swift`

**Step 1: Write the failing test**

Add assertions that prove:
- `accessory` contains `front_ac012` and `front_ac013`
- `pat` contains `front_pat005`, `front_pat006`, and `front_pat007`
- `suit` contains `front_suit010`
- the fallback catalog mirrors the new tail items

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/EquipmentCatalogSplitTests`
Expected: FAIL because the new assets are not yet present in the catalog.

**Step 3: Write minimal implementation**

Add the new asset folders/files, append the new JSON catalog items, and append the same entries in `fallbackCatalog()`.

**Step 4: Run test to verify it passes**

Run the same targeted command and confirm `EquipmentCatalogSplitTests` pass.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-15-six-equipment-assets-design.md docs/plans/2026-03-15-six-equipment-assets-implementation.md StreetStampsTests/EquipmentCatalogSplitTests.swift StreetStamps/AvatarCatalog.json StreetStamps/GearCatalog.swift StreetStamps/Assets.xcassets/人物装备
git commit -m "feat: add six equipment assets"
```
