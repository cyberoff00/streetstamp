# Tab And Equipment Icon Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the start tab, pet equipment, and suit equipment icons with refreshed artwork that matches the app's current template-icon system.

**Architecture:** Keep all call sites unchanged and update only the referenced asset files. The new artwork should preserve the current template-rendering flow, sizing, and selection-state coloring.

**Tech Stack:** SwiftUI asset catalogs, PNG template assets, AppKit-based asset generation, manual visual verification.

---

### Task 1: Lock the replacement scope

**Files:**
- Modify: `docs/plans/2026-03-16-tab-and-equipment-icon-refresh-design.md`
- Modify: `docs/plans/2026-03-16-tab-and-equipment-icon-refresh-implementation.md`
- Verify: `StreetStamps/MainTab.swift`
- Verify: `StreetStamps/EquipmentView.swift`

**Step 1: Confirm referenced asset names**

Verify:
- `MainTab.swift` uses `tab_start_icon`
- `EquipmentView.swift` uses `equipment_icon_pat`
- `EquipmentView.swift` uses `equipment_icon_suit`

**Step 2: Confirm current asset dimensions**

Verify:
- `tab_start_icon` uses the existing tab icon size
- equipment icons use the existing category icon size

### Task 2: Generate refreshed icon assets

**Files:**
- Modify: `StreetStamps/Assets.xcassets/tab_start_icon.imageset/tab_start_icon.png`
- Modify: `StreetStamps/Assets.xcassets/tab_start_icon.imageset/tab_start_icon@2x.png`
- Modify: `StreetStamps/Assets.xcassets/tab_start_icon.imageset/tab_start_icon@3x.png`
- Modify: `StreetStamps/Assets.xcassets/equipment_icon_pat.imageset/icon.png`
- Modify: `StreetStamps/Assets.xcassets/equipment_icon_suit.imageset/icon.png`

**Step 1: Build new artwork**

Draw:
- a flag-shaped start tab icon in the existing tab style
- a pet-shaped category icon in the existing equipment style
- a suit-shaped category icon in the existing equipment style

**Step 2: Replace only the asset bitmaps**

Keep:
- asset names
- asset catalog entries
- template rendering behavior

### Task 3: Verify the asset replacement

**Files:**
- Verify: `StreetStamps/Assets.xcassets/tab_start_icon.imageset`
- Verify: `StreetStamps/Assets.xcassets/equipment_icon_pat.imageset`
- Verify: `StreetStamps/Assets.xcassets/equipment_icon_suit.imageset`

**Step 1: Inspect generated files**

Verify:
- files exist at the expected paths
- file dimensions match the intended slots
- transparency is preserved

**Step 2: Manual visual check**

Verify:
- line weight and padding are aligned with nearby icons
- silhouettes remain legible at UI size

### Task 4: Final verification

**Files:**
- Verify: touched asset files above

**Step 1: Run asset-level checks**

Run dimension and file checks against the touched PNG assets.

**Step 2: Report completion with evidence**

Summarize:
- which assets were replaced
- which checks were run
- any remaining risk limited to in-app visual polish
