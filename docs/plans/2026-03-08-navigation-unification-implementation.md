# Navigation Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify app navigation so root pages use a menu button, detail pages use an icon-only `chevron.left`, and all page chrome comes from one shared header system.

**Architecture:** Extend the shared custom header in `AppTopHeader.swift`, then migrate root and detail screens to that API in small slices. Preserve existing `NavigationStack` routing, but reduce sheet-based app-section navigation where it conflicts with hierarchy semantics.

**Tech Stack:** SwiftUI, `NavigationStack`, custom `FigmaTheme` design tokens, app-local routing/state in `MainTabView`, `FriendsHubView`, and related screens.

---

### Task 1: Define the shared header API

**Files:**
- Modify: `StreetStamps/AppTopHeader.swift`
- Inspect: `StreetStamps/SettingsView.swift`
- Inspect: `StreetStamps/CollectionTabView.swift`

**Step 1: Write the failing test**

Create a small Swift test around the new header mode model if the mode logic is extracted into a testable value type. If extracting a pure model is not worth the indirection, document this task as a UI contract change and skip direct unit coverage.

**Step 2: Run test to verify it fails**

Run the new unit test if created and confirm the missing mode API fails to compile or the assertion fails.

**Step 3: Write minimal implementation**

Add a shared leading-mode abstraction to `UnifiedTabPageHeader` with explicit cases for menu, back, and none. Standardize 42x42 leading/trailing slots and add a reusable icon-only back button using `chevron.left`.

**Step 4: Run test to verify it passes**

Run the focused unit test if present, or build the project target and confirm the header compiles.

**Step 5: Commit**

```bash
git add StreetStamps/AppTopHeader.swift
git commit -m "refactor: unify navigation header modes"
```

### Task 2: Normalize existing compliant root pages

**Files:**
- Modify: `StreetStamps/SettingsView.swift`
- Modify: `StreetStamps/CollectionTabView.swift`
- Modify: `StreetStamps/JourneyMemoryNew.swift`

**Step 1: Write the failing test**

If there is an existing UI or snapshot-style test harness for headers, add one root-page case. Otherwise, define a manual verification checklist in the plan notes:

- root page shows menu, not back
- title stays centered
- no parent title text appears

**Step 2: Run test to verify it fails**

Run the focused test if available or verify current pages still use ad hoc leading closures.

**Step 3: Write minimal implementation**

Switch these root pages to the shared root-page header configuration and remove any page-local leading-button differences.

**Step 4: Run test to verify it passes**

Build the app and verify each root page renders the same header spacing and menu affordance.

**Step 5: Commit**

```bash
git add StreetStamps/SettingsView.swift StreetStamps/CollectionTabView.swift StreetStamps/JourneyMemoryNew.swift
git commit -m "refactor: standardize root page navigation headers"
```

### Task 3: Refactor the friends root page to the shared header

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Inspect: `StreetStamps/AppTopHeader.swift`

**Step 1: Write the failing test**

Add a focused test for any extracted friends-header state helper if practical. Otherwise define manual verification for:

- friends root shows menu only
- pushed friends detail pages do not show menu
- no screen in the friends area shows both controls

**Step 2: Run test to verify it fails**

Run the focused test if added or inspect the current implementation and confirm it still uses hidden system nav plus local header composition.

**Step 3: Write minimal implementation**

Replace the current friends root header usage with the shared header API. Remove duplicated leading-control logic from the root screen and align title spacing with the standard header.

**Step 4: Run test to verify it passes**

Build and manually verify the friends root screen.

**Step 5: Commit**

```bash
git add StreetStamps/FriendsHubView.swift
git commit -m "refactor: align friends root with unified navigation"
```

### Task 4: Migrate friends-area detail pages to icon-only back navigation

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Inspect: other friend-detail views embedded in the same file

**Step 1: Write the failing test**

Document and, where possible, codify that detail destinations:

- show `chevron.left`
- do not show hamburger
- do not show system back text or parent-title text

**Step 2: Run test to verify it fails**

Navigate current friend-detail flows and confirm the old hidden-nav/manual-header behavior still differs from the target.

**Step 3: Write minimal implementation**

Update the detail destinations inside `FriendsHubView.swift` to use the shared detail-page header/back affordance, including any screens that currently call `.navigationBarHidden(true)` and manage sidebar-hide tokens.

**Step 4: Run test to verify it passes**

Build and verify common friend-detail routes end-to-end.

**Step 5: Commit**

```bash
git add StreetStamps/FriendsHubView.swift
git commit -m "refactor: unify friends detail back navigation"
```

### Task 5: Audit sidebar-driven app sections

**Files:**
- Modify: `StreetStamps/MainTab.swift`
- Inspect: `StreetStamps/ProfileView.swift`
- Inspect: `StreetStamps/EquipmentView.swift`
- Inspect: `StreetStamps/SettingsView.swift`

**Step 1: Write the failing test**

Define manual checks for sidebar destinations:

- opening an app section does not create conflicting navigation semantics
- section roots still obey the root/detail rules

**Step 2: Run test to verify it fails**

Verify the current `sheet(item:)` flow in `MainTabView` creates separate navigation behavior for profile/settings/equipment.

**Step 3: Write minimal implementation**

Replace sheet presentation with a routing approach that keeps these app sections in the same navigation model where feasible. If a destination must remain modal, explicitly document why it is modal and ensure it still uses the shared header semantics.

**Step 4: Run test to verify it passes**

Build and manually test sidebar entry into profile/settings/equipment flows.

**Step 5: Commit**

```bash
git add StreetStamps/MainTab.swift StreetStamps/ProfileView.swift StreetStamps/EquipmentView.swift StreetStamps/SettingsView.swift
git commit -m "refactor: align sidebar sections with navigation hierarchy"
```

### Task 6: Add postcards and sidebar quick actions to the new model

**Files:**
- Modify: `StreetStamps/MainTab.swift`
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/ProfileView.swift`
- Inspect: `StreetStamps/PostcardInboxView.swift`
- Inspect: `StreetStamps/PostcardComposerView.swift`

**Step 1: Write the failing test**

Define manual checks for the new sidebar model:

- `Postcards` is reachable as a sidebar primary destination
- `Invite Friend` is reachable as a sidebar quick action
- entering `Invite Friend` does not show hamburger
- entering `Postcards` root follows Level 1 menu behavior only if implemented as a true root destination

**Step 2: Run test to verify it fails**

Verify current code still exposes postcards and invite-friend mostly through local buttons and sheets rather than the new sidebar model.

**Step 3: Write minimal implementation**

Add `Postcards` as a sidebar primary destination and add `Invite Friend` as a sidebar quick action. Route both through the unified navigation semantics rather than their current ad hoc entry points.

**Step 4: Run test to verify it passes**

Build and manually verify sidebar entry into both flows.

**Step 5: Commit**

```bash
git add StreetStamps/MainTab.swift StreetStamps/FriendsHubView.swift StreetStamps/ProfileView.swift StreetStamps/PostcardInboxView.swift StreetStamps/PostcardComposerView.swift
git commit -m "feat: add unified sidebar entry points for postcards and invite friend"
```

### Task 7: Unify activity notifications and postcard task flows

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/ProfileView.swift`
- Modify: `StreetStamps/PostcardInboxView.swift`
- Modify: `StreetStamps/PostcardComposerView.swift`
- Modify: `StreetStamps/PostcardPreviewView.swift`

**Step 1: Write the failing test**

Define focused checks:

- activity notifications page has no hamburger
- postcard inbox has no hamburger
- postcard composer has no hamburger
- postcard preview/completion flow keeps the unified non-root header treatment

**Step 2: Run test to verify it fails**

Verify the current pages still use mixed sheet toolbar or default `navigationTitle` behavior.

**Step 3: Write minimal implementation**

Replace mixed toolbar and default nav-bar behavior in the activity-notifications flow and postcard-related task flows with the shared unified detail-page header.

**Step 4: Run test to verify it passes**

Build and manually verify the notification path, inbox path, composer path, and preview path.

**Step 5: Commit**

```bash
git add StreetStamps/FriendsHubView.swift StreetStamps/ProfileView.swift StreetStamps/PostcardInboxView.swift StreetStamps/PostcardComposerView.swift StreetStamps/PostcardPreviewView.swift
git commit -m "refactor: unify activity notifications and postcard navigation"
```

### Task 8: Remove old navigation styling drift

**Files:**
- Modify: `StreetStamps/FriendsHubView.swift`
- Modify: `StreetStamps/MainTab.swift`
- Inspect: `StreetStamps/FigmaDesignSystem.swift`
- Search: all screens with `.navigationBarHidden(true)` or custom nav color usage

**Step 1: Write the failing test**

Create a final audit checklist:

- no mixed menu/back pages
- no text back labels
- no parent-title breadcrumbs
- no page-specific navigation colors outside the shared design tokens

**Step 2: Run test to verify it fails**

Search the codebase for leftover custom navigation affordances and hidden-bar workarounds that conflict with the new standard.

**Step 3: Write minimal implementation**

Remove or consolidate leftover per-screen navigation color or chrome logic that is now redundant with the shared header.

**Step 4: Run test to verify it passes**

Run a code search and a final build to confirm all targeted pages use the standard.

**Step 5: Commit**

```bash
git add StreetStamps/MainTab.swift StreetStamps/FriendsHubView.swift StreetStamps/AppTopHeader.swift StreetStamps/FigmaDesignSystem.swift
git commit -m "refactor: remove navigation style drift"
```

### Task 9: Verification pass

**Files:**
- Modify: `docs/plans/2026-03-08-navigation-unification-design.md`
- Modify: `docs/plans/2026-03-08-navigation-unification-implementation.md`

**Step 1: Build**

Run the app build command for the main iOS target and confirm the project compiles.

**Step 2: Verify key flows manually**

Check:

- each tab root page
- settings root
- friend profile path
- postcard inbox path
- sidebar entry paths

**Step 3: Search for stragglers**

Run:

```bash
rg -n "navigationBarHidden\\(true\\)|navigationBarBackButtonHidden\\(true\\)|ToolbarItem\\(placement: \\.topBarLeading\\)" StreetStamps
```

Expected:

- only intentional remaining cases

**Step 4: Update docs if needed**

Record any intentional exceptions directly in the design doc.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-08-navigation-unification-design.md docs/plans/2026-03-08-navigation-unification-implementation.md
git commit -m "docs: finalize navigation unification plan"
```
