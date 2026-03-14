# Button Hit Target Unification Design

Date: 2026-03-13
Status: Approved
Owner: Codex + liuyang

## Background

`StreetStamps` contains many custom SwiftUI buttons and tap targets styled with `.buttonStyle(.plain)` plus bespoke padding, backgrounds, and rounded shapes. In several cases the visible surface looks large and button-like, but the actual interactive area collapses toward the text or icon content.

The user-reported symptom is straightforward:

- buttons often require tapping directly on the text
- card-like and row-like affordances do not consistently honor the full visible surface
- this makes the app feel unreliable and harder to use

This issue is not isolated to a single screen. It appears across:

- auth entry primary and guest CTAs
- sidebar menu items
- map floating action buttons
- profile action buttons and expandable rows
- settings segmented controls and row cards
- equipment cards
- onboarding coach cards
- friend feed and card-like entry points

## Goal

Make high-frequency interactive surfaces behave consistently so that the visible shape or row bounds are the actual tap target.

## Non-Goals

- no attempt to convert every single tap target in the repository in one pass
- no expansion of system alert buttons or intentionally tiny icon-only controls beyond their intended shape
- no visual redesign beyond what is necessary to align hit testing with current rendered surfaces

## Approved Scope

The approved scope is broader than traditional buttons. This pass should cover:

- primary buttons
- secondary capsule buttons
- floating buttons
- card buttons
- row buttons
- avatar/profile action buttons
- list/cell-like entry surfaces that visually imply full-row tapping

## Design Principles

### 1. Visible Surface Equals Interactive Surface

If a UI element renders a clear rounded rectangle, capsule, circle, or full row background, tapping anywhere inside that visible surface should trigger the action.

### 2. Shared Rule, Explicit Adoption

Instead of relying on ad-hoc `.contentShape(...)` calls, add a small shared modifier that marks a view as a full-surface tap target:

- rectangle
- rounded rectangle
- capsule
- circle

This keeps the rule searchable and auditable in source.

### 3. Prioritize Shared Components and High-Traffic Pages

The fastest, safest way to raise overall quality is:

1. add a reusable tap-target modifier
2. apply it to shared button-like components
3. apply it to key high-frequency screens with known issues

## Proposed Architecture

### Shared Modifier

Add a new SwiftUI helper in `StreetStamps`:

- `AppFullSurfaceTapTargetShape`
- `View.appFullSurfaceTapTarget(_:)`

This modifier should wrap `contentShape(...)` for the supported shapes and be used on label content rather than on outer containers whenever possible.

### Audited Coverage Targets

This pass should explicitly cover these files/components:

- `StreetStamps/AuthEntryView.swift`
- `StreetStamps/ProfileView.swift`
- `StreetStamps/SettingsView.swift`
- `StreetStamps/FriendsHubView.swift`
- `StreetStamps/MapView.swift`
- `StreetStamps/EquipmentView.swift`
- `StreetStamps/MainView.swift`
- `StreetStamps/SidebarNavigation.swift`
- `StreetStamps/OnboardingCoachCard.swift`

### Pattern Rules

- use `.appFullSurfaceTapTarget(.roundedRect(...))` for pill/rounded-rect buttons
- use `.appFullSurfaceTapTarget(.capsule)` for capsule buttons
- use `.appFullSurfaceTapTarget(.circle)` for circular buttons
- use `.appFullSurfaceTapTarget(.rectangle)` for full-row/cell targets

## Testing Strategy

### Contract Test

Add a source-level coverage test that reads the audited files and ensures they adopt `appFullSurfaceTapTarget(`. This is not a UI test, but it gives a cheap regression guard that the explicit hit-target rule remains in place on the selected screens.

### Manual Verification

Check these interactions in simulator:

1. auth primary CTA
2. auth guest CTA
3. main start button
4. map floating action buttons
5. sidebar menu rows
6. profile action buttons
7. settings segment buttons and row cards
8. equipment item cards
9. onboarding coach CTA card
10. friend feed cards / like capsule where applicable

## Risks

- over-expanding a hit target could cause overlap with nearby controls if applied to the wrong container
- source-level coverage tests protect explicit adoption, but they do not fully replace manual interaction testing

## Implementation Notes

- prefer applying the modifier to the button label content after final `frame/background/clipShape`
- keep existing visuals and animations intact
- only expand hit areas for surfaces that clearly present themselves as tappable
