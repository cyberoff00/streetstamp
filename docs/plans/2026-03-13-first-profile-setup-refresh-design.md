# First Profile Setup Refresh Design

Date: 2026-03-13
Status: Approved
Owner: Codex + liuyang

## Background

[`StreetStamps/FirstProfileSetupView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/FirstProfileSetupView.swift) currently presents first-time profile setup as a vertically scrolling composition with multiple explanatory blocks:

- a top-right `跳过`
- a title plus subtitle
- an avatar card with extra helper copy
- a nickname card with extra helper copy
- a separate "还差一步" summary card
- a bottom confirm CTA

The approved product direction is to make this screen feel lighter, faster, and closer to a one-screen setup moment rather than a dense onboarding form.

The user also reported a broader interaction issue: some custom buttons only respond when tapping directly on the text instead of the full visible button surface. The refreshed setup screen should correct that behavior for all buttons it contains.

## Goal

Turn the first profile setup screen into a compact single-screen flow with only essential copy, clear hierarchy, and full-surface tap targets for its visible buttons.

## Non-Goals

- no backend or submission contract changes
- no new setup steps or multi-page flow
- no redesign of the equipment editor itself
- no app-wide audit of every button in the project during this pass

## Approved UX

### Layout

- keep the screen to a single compact page without relying on vertical scrolling
- keep only one top-right action: `跳过`
- keep the main setup title
- keep avatar preview and `去换装`
- keep nickname input
- keep the bottom primary CTA

### Copy Simplification

- remove the current subtitle below the main title
- remove the nickname helper text
- remove the entire "还差一步" information card
- replace the avatar area copy with:
  - title: `设置初始形象`
  - helper: `后续可在装备页探索更多`

### Interaction

- visible button surfaces on this screen must be fully tappable, not just the text glyph area
- this includes:
  - top-right `跳过`
  - `去换装`
  - bottom confirm CTA

## Proposed Architecture

### 1. Introduce a Small Presentation Layer

Add a lightweight presentation/config type near the setup view that provides:

- hero section title
- hero section helper copy
- booleans for whether to show subtitle, nickname helper, and final summary card

This keeps the simplification testable without requiring SwiftUI snapshot infrastructure.

### 2. Restructure the SwiftUI View Around a Fixed Vertical Stack

Replace the outer `ScrollView` with a fixed-height composition that uses `Spacer` and tighter spacing to fit within a standard iPhone viewport. The page should remain visually breathable while no longer implying a multi-step scrolling experience.

### 3. Fix Button Hit Areas at the Label Level

For setup-screen buttons, move frame/background/shape modifiers onto the button label content and add explicit `.contentShape(...)` so the tappable region matches the rendered shape.

This avoids the common SwiftUI pitfall where a visually large button has a smaller interactive hit target when styling is applied outside the label.

## Testing Strategy

### Unit Tests

Add focused tests that verify the setup presentation config uses the approved minimal state:

- avatar title matches the approved copy
- avatar helper matches the approved copy
- subtitle is hidden
- nickname helper is hidden
- summary card is hidden

Add a focused button-hit-area policy test by exposing a small helper or view-level contract that ensures setup buttons opt into full-surface hit targeting.

### Manual Verification

1. Present the first profile setup screen on an iPhone simulator
2. Confirm the screen fits without scrolling
3. Confirm only `跳过` appears in the top-right corner
4. Confirm avatar area shows `设置初始形象`
5. Confirm avatar helper shows `后续可在装备页探索更多`
6. Confirm no subtitle appears below the main title
7. Confirm no nickname helper appears below the text field
8. Confirm no "还差一步" card appears
9. Confirm tapping empty padded areas inside `跳过`, `去换装`, and the bottom CTA still triggers the button

## Risks

- removing the `ScrollView` could create clipping on unusually small devices if spacing is not tightened carefully
- button hit-area fixes must preserve the existing press style and visual treatment

## Implementation Notes

- keep localization keys instead of hardcoding copy in the view
- update English, Simplified Chinese, and Traditional Chinese strings for consistency
- avoid changing submit/skip behavior while simplifying the presentation
