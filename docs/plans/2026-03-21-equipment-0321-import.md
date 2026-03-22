# Equipment 0321 Import Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Import the approved 2026-03-21 equipment assets into the existing avatar equipment areas by appending them to the correct categories without changing category structure.

**Architecture:** Keep the current data-driven equipment setup. Add the new PNGs into `StreetStamps/Assets.xcassets/人物装备/`, append matching entries in `StreetStamps/AvatarCatalog.json`, and mirror the same newest items in `StreetStamps/GearCatalog.swift` so fallback loading stays in sync.

**Tech Stack:** Swift, XCTest, Xcode asset catalogs, JSON catalog data

---

### Task 1: Extend the targeted regression tests

**Files:**
- Modify: `StreetStampsTests/EquipmentCatalogSplitTests.swift`

**Step 1: Write the failing test**

Add assertions covering the newly approved imports:
- `front_exp014` in `expression`
- `front_pat009` and `front_pat010` in `pat`
- `front_hair013` through `front_hair016` in `hair`
- `front_ac015` through `front_ac018` in `accessory`

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/EquipmentCatalogSplitTests`

Expected: the new assertions fail because the assets/catalog entries do not exist yet.

### Task 2: Import the assets and wire the JSON catalog

**Files:**
- Create: `StreetStamps/Assets.xcassets/人物装备/front_exp014.imageset/*`
- Create: `StreetStamps/Assets.xcassets/人物装备/front_pat009.imageset/*`
- Create: `StreetStamps/Assets.xcassets/人物装备/front_pat010.imageset/*`
- Create: `StreetStamps/Assets.xcassets/人物装备/front_hair013.imageset/*`
- Create: `StreetStamps/Assets.xcassets/人物装备/front_hair014.imageset/*`
- Create: `StreetStamps/Assets.xcassets/人物装备/front_hair015.imageset/*`
- Create: `StreetStamps/Assets.xcassets/人物装备/front_hair016.imageset/*`
- Create: `StreetStamps/Assets.xcassets/人物装备/front_ac015.imageset/*`
- Create: `StreetStamps/Assets.xcassets/人物装备/front_ac016.imageset/*`
- Create: `StreetStamps/Assets.xcassets/人物装备/front_ac017.imageset/*`
- Create: `StreetStamps/Assets.xcassets/人物装备/front_ac018.imageset/*`
- Modify: `StreetStamps/AvatarCatalog.json`

**Step 1: Write minimal implementation**

Append only the approved items:
- `front_exp1.png` -> `expression` as `front_exp014`
- `front_pat1.png` and `front_pat2.png` -> `pat` as `front_pat009`, `front_pat010`
- `front_hair1.png` to `front_hair4.png` -> `hair` as `front_hair013` to `front_hair016`
- `front_ac1.png`, `front_ac5.png`, `front_ac6.png`, `front_ac7.png` -> `accessory` as `front_ac015` to `front_ac018`

### Task 3: Mirror the newest items in the fallback catalog

**Files:**
- Modify: `StreetStamps/GearCatalog.swift`

**Step 1: Write minimal implementation**

Extend `AvatarCatalogStore.fallbackCatalog()` so the last items in `expression`, `pat`, `hair`, and `accessory` match the appended JSON catalog entries.

### Task 4: Verify green

**Files:**
- Test: `StreetStampsTests/EquipmentCatalogSplitTests.swift`

**Step 1: Run targeted tests**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/EquipmentCatalogSplitTests`

Expected: PASS for the targeted equipment catalog suite.
