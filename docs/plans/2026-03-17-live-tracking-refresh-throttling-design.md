# Live Tracking Refresh Throttling Design

**Context**

The live tracking screen currently keeps the foreground map render loop very hot while a journey is active. In sport mode the render debounce is `0.08s` and in daily mode it is `0.25s`, while `MapView` also reacts to `tracking.$coords` updates and requests snapshot persistence on each coordinate tick. This gives strong immediacy, but it increases front-end work, especially when the map is visible for long sessions.

**Goal**

Keep the tracking experience feeling live while reducing unnecessary foreground redraws and snapshot churn. The target is a conservative first pass:

- sport mode map rendering around `6Hz`
- daily mode map rendering around `2Hz`
- distance/time chip remains `1Hz`
- coordinate-driven snapshot updates are throttled to roughly `5s`
- event-driven persistence paths such as finish, exit, memory edits, and mode changes remain immediate

**Recommended Approach**

Use a layered cadence model rather than a single "everything follows location updates" loop.

1. Reduce the active foreground render debounce in `TrackingModeConfig` so the map cache rebuilds less often while the map is on screen.
2. Add a tiny snapshot cadence policy for `MapView` so coordinate updates can continue to update live state, but only trigger snapshot persistence at a bounded interval.
3. Leave immediate persistence paths untouched for explicit user actions and lifecycle boundaries.

This keeps the visible route responsive, preserves current behavior for important persistence moments, and avoids a larger architecture rewrite inside `TrackingService`.

**Alternatives Considered**

1. Move all snapshot persistence into `TrackingService`.
This is cleaner long-term, but it is a broader ownership change and touches more call sites than needed for a low-risk tuning pass.

2. Stop publishing `coords` at live cadence and introduce separate UI-only publishers.
This would reduce more SwiftUI churn, but it is a larger refactor with more regression risk.

3. Only change the render debounce values and leave `MapView` snapshot behavior alone.
This helps GPU/CPU work somewhat, but still lets coordinate ticks fan out into repeated `MapView` updates and snapshot scheduling.

**Testing Strategy**

- Add a focused unit test for the new coordinate snapshot cadence policy.
- Add a focused unit test to pin the desired render debounce values for sport and daily tracking.
- Run the affected test file plus the existing tracking tests to make sure no behavior regressed.

**Risk Notes**

- The map will feel slightly less "ink follows the GPS dot instantly" in sport mode, but `~6Hz` should still feel live to users.
- Snapshot persistence becomes intentionally less eager, so crash recovery granularity for an in-progress route becomes interval-based instead of every coordinate tick. The existing store-level throttling and explicit flush paths still protect important moments.
