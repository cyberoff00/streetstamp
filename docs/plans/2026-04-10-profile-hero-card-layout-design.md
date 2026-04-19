# Profile Hero Card Layout Design

**Date:** 2026-04-10

**Scope:** Refresh the nickname and stats layout on the personal profile and friend profile screens without changing copy, metrics, data sources, scene art, or downstream sections.

## Confirmed Constraints

- Keep the sofa/character scene on both screens.
- Keep all existing copy and number formatting logic.
- Keep the friend profile CTA ("坐一坐"/leave seat states) and place it in the top-right action slot of the info card.
- Keep the personal profile top-right action entry in the matching position.
- Keep the rest of the page order and content unchanged.

## Layout Direction

Replace the current post-scene header block with two stacked cards:

1. **Info card**
   - Left: display name, level pill, joined/since date.
   - Right: existing contextual action button.
   - Personal profile uses the current equipment entry.
   - Friend profile uses the current seat CTA button.

2. **Stats row**
   - Two compact stat cards side by side.
   - Style follows the provided reference: soft icon tile, bold metric, uppercase/light secondary label.
   - Personal profile shows journeys and total distance.
   - Friend profile shows journeys and total distance using the existing friend stat sources.

## Implementation Notes

- Extract a shared SwiftUI component so both screens render the same structure.
- Keep formatting logic close to current screens to avoid changing localization or number rules.
- Use source-parity tests to lock the new shared component usage because the repo currently has unrelated failing test compilation.
