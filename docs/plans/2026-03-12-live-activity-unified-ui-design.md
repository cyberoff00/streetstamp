# Live Activity Unified UI Design

**Date:** 2026-03-12

## Goal

Replace the current sport-vs-daily Live Activity presentation with one shared visual design. The lock screen card should show the user's avatar on the left, distance and elapsed time in the center, and one fixed action button on the right that always opens the app into the active tracking screen and launches the capture camera flow directly.

## Current State

The existing Live Activity implementation in `TrackingWidge/StreetStampsWidgets/TrackingLiveActivity.swift` still branches on `trackingMode`:

- lock screen uses `SportModeLockScreen` for distance/time stats
- lock screen uses `DailyModeLockScreen` for add-memory actions
- Dynamic Island compact and expanded regions also change behavior by mode
- the existing widget action route uses `AddMemoryIntent`, which opens the app and lands in the add-memory editor instead of camera capture

This creates two problems:

1. The visual design does not match the requested unified pill layout.
2. The action path does not match the requested direct-capture behavior.

## Product Requirements

- Lock screen Live Activity uses one shared capsule card for all tracking modes.
- The left side always shows the user's avatar miniature.
- The center always shows both live distance and elapsed duration.
- The right side always shows one circular green action button.
- The action button does not change meaning based on tracking mode.
- Tapping the action button opens the app, returns the user to the active tracking screen, and launches camera capture immediately.
- Sport mode and daily mode remain available as data concepts if other app logic still needs them, but the Live Activity UI must stop exposing that distinction.

## Non-Goals

- Redesigning the in-app tracking screen beyond the minimum routing work required to open capture
- Removing `trackingMode` from app state or Activity attributes
- Changing pause/resume behavior outside the Live Activity
- Reworking the Journey Memory editor UX

## Approaches Considered

### Approach A: Keep mode data, remove mode-specific presentation

Keep `trackingMode` in `TrackingActivityAttributes`, but replace all mode-based Live Activity view branching with one shared presentation and one shared capture action.

Pros:

- Lowest-risk change to ActivityKit data contracts
- Avoids touching tracking lifecycle code that still passes `.sport` or `.daily`
- Keeps compatibility with any future analytics or app logic that still reads the mode

Cons:

- Leaves a no-longer-user-visible field in the Live Activity attributes

### Approach B: Remove mode from the Live Activity data model entirely

Delete `trackingMode` from the Activity attributes and refactor app/widget startup and update paths to stop sending it.

Pros:

- Data model becomes closer to what the UI now presents

Cons:

- Higher-risk change across ActivityKit request/update compatibility
- Unnecessary for the requested UI behavior

### Approach C: Keep current widget actions and only restyle the card

Change visuals only, but continue routing the button through the current add-memory flow.

Pros:

- Smallest routing change

Cons:

- Does not satisfy the direct-capture requirement
- Keeps misleading behavior behind a new button design

## Recommendation

Choose **Approach A**.

The requested behavior is primarily a UI and routing change, not a state-model redesign. Keeping the existing Activity attributes but collapsing the UI to one shared layout is the safest way to deliver the new behavior without creating avoidable risk in ActivityKit lifecycle code.

## Final UX Design

### Lock Screen Card

The lock screen Live Activity becomes a single rounded capsule:

- soft light background using the current widget palette
- left avatar tile with the user's mini character
- center stat stack with:
  - distance on the first line, including unit styling
  - elapsed duration on the second line with a live-status dot
- right circular green button with a capture affordance

The card no longer shows:

- sport/daily labels
- separate daily-only button states
- sport-only status bar ornamentation

### Dynamic Island

Dynamic Island also becomes mode-agnostic:

- compact leading: avatar or tracking-status indicator
- compact trailing: one primary live stat, biased toward distance for scanability
- expanded: avatar + distance + elapsed time + fixed capture button
- minimal: simplified active-state indicator

The exact expanded-region composition can adapt to Dynamic Island space limits, but it must stop branching by mode.

### Action Behavior

The right-side circular button always means:

- open the app
- navigate back to the active tracking map screen if the user is elsewhere
- open the system camera capture flow immediately

This replaces the current "open add memory editor" behavior.

## Technical Design

### Widget UI Structure

Refactor `TrackingWidge/StreetStampsWidgets/TrackingLiveActivity.swift` to:

- replace `LockScreenView` mode branching with a shared component, e.g. `UnifiedTrackingLockScreen`
- remove `SportModeLockScreen` and `DailyModeLockScreen`
- move formatting helpers into reusable shared helpers where possible
- add one avatar-rendering surface suitable for widget constraints
- replace mode-specific Dynamic Island regions with one shared implementation

### Avatar Strategy

Use a lightweight avatar rendering approach compatible with the widget target. The design intent is to show the user's small character on the left, not a generic icon. Implementation can use:

- an existing avatar asset stack already available to the widget target, or
- a simplified mirrored subset of avatar assets if the full renderer is not widget-safe

The key contract is visual identity on the left side. Exact rendering fidelity can be reduced if widget constraints require it.

### Capture Routing

Introduce a dedicated widget intent for capture instead of reusing `AddMemoryIntent`.

Recommended shape:

- `OpenCaptureIntent` or similar in `TrackingWidge/StreetStampsWidgets/AddMemoryIntent.swift` or a renamed intent file
- `openAppWhenRun = true`
- write a distinct App Group flag such as `pendingOpenCapture`

Main app handling in `StreetStamps/LiveActivityManager.swift` should:

- detect `pendingOpenCapture`
- clear the flag
- publish a dedicated notification such as `.openCaptureFromWidget`

### App Navigation Handoff

When the app receives `.openCaptureFromWidget`, it must first ensure the user returns to the active tracking screen before opening camera capture.

The navigation contract should be:

1. request the Start/Home tracking tab through the app flow coordinator
2. request resume of the active ongoing journey when needed
3. once the tracking screen is active, present camera capture directly

This keeps widget-triggered capture aligned with the user's currently active route even if they launched from another tab or deep subpage.

### Tracking Screen Integration

`StreetStamps/MapView.swift` currently handles `.openAddMemoryFromWidget` by showing the memory editor. Extend or replace that listener with a dedicated capture listener:

- guard that tracking is active and not paused if required by the existing capture rules
- dismiss any intermediate memory editing state
- set `showCamera = true` directly

The button path should bypass `showMemoryEditor = true`.

## Error Handling

- If there is no active journey, the app should safely ignore the capture trigger rather than presenting a broken camera flow.
- If tracking is paused and current app rules forbid capture, ignore the trigger or route to the safe fallback already used by the in-app capture button.
- Widget-trigger flags must be cleared after consumption to avoid duplicate launches.
- Navigation and capture should tolerate the app launching cold from the background.

## Testing Strategy

### Unit tests

- verify widget-action flag handling for the new capture intent
- verify `LiveActivityManager` emits the new capture notification
- verify navigation coordinator behavior needed to return to the tracking screen

### UI/build validation

- build the widget target and main app target after the refactor
- manually verify lock screen and Dynamic Island layout on a Live Activity-capable simulator/device
- manually verify tapping the button from another tab returns to tracking and opens camera

## Risks

- Widget target may not have direct access to the full avatar rendering stack
- Launch timing may require careful sequencing so the camera opens after the tracking screen is active
- Dynamic Island spacing is tighter than the lock screen card, so the unified composition may need a slightly reduced avatar treatment there

## Success Criteria

- Live Activity no longer visually distinguishes sport vs daily mode
- Lock screen card matches the requested left-avatar, center-stats, right-button structure
- Dynamic Island no longer branches by mode
- Tapping the right button always opens the app into the active tracking flow and launches camera capture directly
