# Lifelog Footprint Zoom Threshold Design

**Problem:** Lifelog currently switches to footprint markers only when the map is zoomed in very close, which makes the footprint view feel harder to reach than intended.

**Goal:** Let users see footprint markers from a slightly farther zoom level without changing footprint sampling, caching, or marker styling.

## Approach

Use the existing near-mode gate in `LifelogRenderModeSelector` as the only behavior change point.

- Increase the near-mode latitude and longitude span thresholds.
- Keep the footprint rendering planner unchanged so marker density, cache keys, and viewport clipping stay stable.
- Update selector tests so the new threshold is documented and protected.

## Trade-offs

- Pros: very small change surface, low regression risk, no new state or rendering paths.
- Cons: footprint mode will appear earlier, so dense days may look busier at that zoom level.

## Validation

- Add a selector test proving a wider region still counts as near mode.
- Keep the existing "too wide" test, adjusted to fail just beyond the new threshold.
