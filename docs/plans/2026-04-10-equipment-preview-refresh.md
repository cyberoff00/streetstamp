# Equipment Preview Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update the equipment preview UI to use the mint avatar backdrop, move try-on controls into the preview corner, and add a green hair color choice.

**Architecture:** Keep all existing try-on behavior and loadout updates intact while changing only the preview presentation. Implement the try-on control relocation entirely within `EquipmentView` and lock the intended structure with source-parity tests.

**Tech Stack:** SwiftUI, XCTest source-parity tests

---

### Task 1: Add a failing source-parity test

**Files:**
- Modify: `StreetStampsTests/InteractiveSurfaceCoverageTests.swift`

**Step 1: Write the failing test**

Assert that `EquipmentView.swift`:
- contains the mint preview background color
- no longer references `tryOnRow`
- renders a compact corner try-on control in `avatarPreviewCard`
- includes a new green hair color hex

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/InteractiveSurfaceCoverageTests/test_equipmentPreviewUsesCornerTryOnControlsAndMintBackdrop`

Expected: the new assertion fails, or execution is blocked by existing repo/environment test issues.

### Task 2: Move try-on controls into the preview card

**Files:**
- Modify: `StreetStamps/EquipmentView.swift`

**Step 1: Remove the standalone top try-on row**

Delete the separate `tryOnRow` placement from the main page stack.

**Step 2: Add lightweight corner controls**

Embed a compact try-on control in `avatarPreviewCard`:
- idle state for entering try-on mode
- active state for apply/cancel actions

### Task 3: Update preview tint and hair colors

**Files:**
- Modify: `StreetStamps/EquipmentView.swift`

**Step 1: Update preview background**

Set the preview card background color to `Color(red: 224.0 / 255.0, green: 241.0 / 255.0, blue: 237.0 / 255.0)`.

**Step 2: Add the green swatch**

Append a new green hex value to `hairColorOptions`.

### Task 4: Verify and report blockers

**Files:**
- Review only

**Step 1: Run source verification**

Run:
- `rg -n "224.0 / 255.0|tryOnCornerControl|#4CAF50|hairColorOptions|tryOnRow" StreetStamps/EquipmentView.swift`
- `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/InteractiveSurfaceCoverageTests/test_equipmentPreviewUsesCornerTryOnControlsAndMintBackdrop`

**Step 2: Report actual verification state**

If Xcode remains blocked by environment or unrelated compile issues, report that exactly instead of claiming a passing run.
