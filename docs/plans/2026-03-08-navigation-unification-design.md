# Navigation Unification Design

**Date:** 2026-03-08

## Goal

Unify the iOS app navigation system so every screen follows one visual language and one hierarchy rule. Remove mixed navigation colors, eliminate pages that show both hamburger and back affordances, and standardize back navigation to an icon-only `chevron.left`.

## Current State

The app already has a partial design system built around `FigmaTheme`, a white tab bar, and a custom sidebar entry point. However, navigation behavior is split across multiple patterns:

- `MainTabView` uses a tab root plus a custom sidebar launcher overlay.
- Root pages such as settings and collection already use `UnifiedTabPageHeader`.
- `FriendsHubView` and several deep views hide the system navigation bar and build page chrome manually.
- Some destinations are shown through `.sheet`, which creates a separate navigation world with different title and dismissal behavior.

This creates three user-facing problems:

1. Inconsistent color semantics: green, blue, and black are all used as navigation signals.
2. Inconsistent hierarchy semantics: some screens show hamburger, some show back, and some can collide.
3. Inconsistent title behavior: some pages use custom centered titles while others inherit system navigation behavior.

## Requirements

### Product requirements

- Root pages show a hamburger menu and never show a back button.
- Pushed detail pages show a back button and never show a hamburger menu.
- Back buttons show icon only: `chevron.left`.
- The navigation bar never shows "Back" text or parent-page titles.
- The title always represents the current screen.
- Navigation colors must come from one shared token set.

### Implementation requirements

- Use one shared header component across root and detail pages.
- Remove ad hoc per-screen header implementations where possible.
- Keep existing page content and navigation destinations intact unless required for hierarchy correctness.
- Prefer push-based navigation for in-app destinations over presenting root app sections as sheets.

## Approaches Considered

### Approach A: One custom navigation system layered on SwiftUI navigation

Build one shared header abstraction and use it on all custom pages. Root pages render `.menu`; detail pages render `.back`; the underlying `NavigationStack` remains in place for routing.

Pros:

- Matches the app's existing custom design direction.
- Gives exact control over icon-only back behavior.
- Fixes both visual inconsistency and hierarchy inconsistency.
- Reuses `UnifiedTabPageHeader` and existing `FigmaTheme`.

Cons:

- Requires touching multiple screens that currently hand-roll navigation chrome.

### Approach B: Minimal visual cleanup only

Keep current structures and just normalize colors and button icons.

Pros:

- Smallest code change.

Cons:

- Does not solve menu/back collisions.
- Leaves multiple navigation patterns in the codebase.
- Regressions will continue as new screens are added.

### Approach C: Revert to more of the system navigation bar

Lean back into default `NavigationStack` bar behavior and style it globally.

Pros:

- Lower custom surface area.

Cons:

- Hard to enforce icon-only back behavior and centered custom titles consistently.
- Poor fit for the current custom sidebar architecture.

## Recommendation

Choose **Approach A**.

The app already depends on a custom sidebar and custom tab-root chrome, so the right move is to finish that system rather than mixing it with default behavior. This provides the cleanest user mental model:

- top-level = menu
- deeper level = back

That rule is simple enough to enforce across the entire app and easy for future contributors to follow.

## Final Navigation Rules

### 1. Hierarchy

- Level 1: tab-root pages only
- Level 2+: any destination entered from a root page or another detail page

### 2. Leading control

- Level 1 uses hamburger only
- Level 2+ uses `chevron.left` only
- Menu and back cannot appear together on the same screen

### 3. Title

- Centered current-page title
- No system back text
- No parent-title breadcrumb
- Single line with scaling when needed

### 4. Visual system

- Header background: `FigmaTheme.card` or equivalent near-white surface
- Primary text and icons: `FigmaTheme.text`
- Accent/selection state: `FigmaTheme.primary`
- Remove blue/black per-screen nav styling unless it is content styling rather than navigation styling

### 5. Hit area and spacing

- Leading and trailing control slots are always 42x42
- Header layout remains symmetric to keep centered titles visually stable

## Component Design

Extend the existing header infrastructure in `StreetStamps/AppTopHeader.swift`:

- Keep `UnifiedTabPageHeader` as the shared base
- Add a clear leading-mode API:
  - `.menu`
  - `.back`
  - `.none`
- Keep a trailing slot for page-specific actions

This yields one navigation primitive for all app screens rather than separate implementations for root pages, settings pages, and friends-related pages.

## Routing Design

### Root pages

Pages hosted directly under the main tab structure remain root pages and render the menu affordance.

Examples from current code:

- main/home
- friends hub
- collection
- memory root
- lifelog root

### Detail pages

Any pushed destination from those roots becomes a detail page and renders an icon-only back button.

Examples from current code:

- friend profile
- add friend
- social notifications
- postcard inbox
- settings detail pages
- profile/equipment detail pages

### Sheet usage

Sheets should be reserved for flows that are truly modal. Presenting app sections such as settings/profile/equipment from the sidebar via sheet keeps creating a parallel navigation model. Those destinations should be evaluated and moved into the same navigation hierarchy where practical.

## Screen Migration Priorities

### Priority 1: shared header API

Update the shared header component first so there is a single target API for the rest of the app.

### Priority 2: top-level roots already close to compliant

Standardize pages already using `UnifiedTabPageHeader`, including:

- `SettingsView`
- `CollectionTabView`
- memory root header usage

### Priority 3: friends area

Refactor `FriendsHubView` and its pushed destinations because this area currently hides the navigation bar in several places and is the most likely source of menu/back collisions.

### Priority 4: sidebar destination flow

Replace sheet-based navigation for app sections where doing so improves hierarchy consistency.

## Risks

### Risk: changing modal flows that were intentionally modal

Mitigation:

- Only migrate sidebar destinations that function as app sections rather than transient tasks.
- Keep genuinely modal flows such as scanners or importers as sheets/full-screen flows.

### Risk: breaking dismiss behavior on detail pages

Mitigation:

- Use explicit dismiss closures in the shared header back mode.
- Verify pushed and modal contexts separately.

### Risk: title regressions on long localized strings

Mitigation:

- Keep a symmetric header layout.
- Keep line limit at one and preserve minimum scale factor.

## Success Criteria

- No screen shows both hamburger and back.
- All back affordances are icon-only `chevron.left`.
- Root and detail pages use one shared header component.
- Navigation color semantics are consistent across the app.
- Settings, friends, and other deep areas no longer visually break from the main navigation pattern.
