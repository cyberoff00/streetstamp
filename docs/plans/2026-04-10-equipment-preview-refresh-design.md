# Equipment Preview Refresh Design

**Date:** 2026-04-10

**Scope:** Refresh the equipment preview card so the avatar background matches the new profile tint, make try-on controls lighter and embedded into the preview corner, and add a green hair color swatch.

## Confirmed Constraints

- Change the equipment preview avatar background to `#e0f1ed`.
- Remove the standalone try-on row from the top of the page.
- Move try-on entry/actions into the preview card corner and keep the interaction lighter.
- Add one new green hair color option without changing the rest of the color system.
- Do not expand the feature set beyond these presentation updates.

## Layout Direction

1. **Preview background**
   - Update `avatarPreviewCard` to use the shared soft mint background.

2. **Try-on controls**
   - Replace the full-width top try-on row with a compact corner control inside the preview card.
   - Idle state: compact pill/button in the preview corner.
   - Active state: same corner expands to show lightweight apply/cancel actions.

3. **Hair colors**
   - Append one green swatch to the hair color options list.

## Implementation Notes

- Keep try-on state/data flow unchanged; only move and restyle the controls.
- Use source-parity tests because current Xcode verification is intermittently blocked by environment issues.
