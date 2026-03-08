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
- Sidebar-launched quick actions do not show a hamburger menu.
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

- Level 1: channel root pages, including tab-root pages and sidebar-promoted primary destinations
- Level 2+: any destination entered from a root page or another detail page
- Quick actions launched from the sidebar are not Level 1 pages

### 2. Leading control

- Level 1 uses hamburger only
- Sidebar quick actions use back/close semantics only
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

Pages hosted directly under the main tab structure remain root pages and render the menu affordance. Sidebar-promoted primary destinations also count as root pages.

Examples from current code:

- main/home
- friends hub
- collection
- memory root
- lifelog root
- postcards root

### Detail pages

Any pushed destination from those roots becomes a detail page and renders an icon-only back button.

Examples from current code:

- friend profile
- add friend
- social notifications
- postcard inbox
- postcard composer
- settings detail pages
- profile/equipment detail pages
- notifications

### Sheet usage

Sheets should be reserved for flows that are truly modal. Presenting app sections such as settings/profile/equipment from the sidebar via sheet keeps creating a parallel navigation model. Those destinations should be evaluated and moved into the same navigation hierarchy where practical.

Sidebar quick actions are allowed to launch a modal flow, but they still must use the unified header semantics for non-root pages. A modal task flow must not reintroduce a hamburger button simply because it originated from the sidebar.

## Sidebar Model

The sidebar should be split into two explicit groups.

### Primary destinations

These are channel-level roots and should follow Level 1 navigation rules:

- home
- memory
- cities
- friends
- lifelog
- profile
- settings
- postcards

### Quick actions

These are shortcut entry points into a task flow. They are launched from the sidebar, but they are not treated as root navigation destinations:

- invite friend

Quick actions must open with the unified non-root header treatment, using `chevron.left` or an equivalent dismiss/back affordance, never a hamburger menu.

## Page-Specific Decisions

### Postcards

`Postcards` should be promoted into the sidebar as a primary destination. It functions as a content center with repeat visitation and should not remain only a secondary sheet-driven surface.

Navigation treatment:

- sidebar entry allowed
- root-page treatment
- hamburger at Level 1
- deeper postcard flows use `chevron.left`

### Invite Friend

`Invite Friend` should be added to the sidebar as a quick action rather than a primary destination.

Navigation treatment:

- sidebar shortcut allowed
- not a root page
- no hamburger on entry
- use the unified non-root header treatment

### Notifications

The notifications experience is not a root page. It should not use its own sheet toolbar style and should not show a hamburger menu.

Navigation treatment:

- no hamburger
- icon-only `chevron.left`
- unified title bar styling

### Postcard Inbox

The postcard inbox is a destination/content page but not a top-level navigation root in the proposed structure.

Navigation treatment:

- no hamburger
- icon-only `chevron.left`
- unified title bar styling

### Postcard Composer

The postcard composer is a task flow and must follow non-root navigation rules.

Navigation treatment:

- no hamburger
- icon-only `chevron.left`
- unified title bar styling

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
