# Local Journey Isolation And Auth Resume Design

**Goal:** Fix two high-severity issues together: `collection_tab` must only show this device's local guest journeys plus the current account's journeys, and an in-progress journey must survive passive logout/login without resetting UI or freezing Live Activity.

**Status:** Approved design

---

## Problem Summary

Two failures are happening at the same time:

1. `collection_tab` can show the wrong cities, wrong memories, or even another person's public journeys.
2. When a user is passively logged out during an active journey, logging back in can make the app look like tracking restarted while the Live Activity remains stuck on screen.

These are both caused by state boundaries being too loose:

- local display data is rebuilt from overly broad recovery sources
- tracking state, auth state, and Live Activity state are not restored as one coherent session

---

## Product Rules

### Collection / Memory Rule

The visible collection data for the current app session must be:

- this device's current local journey data
- plus the currently logged-in account's journey data

The visible collection data must **not** automatically include:

- other historical `guest_*` roots on the device
- other accounts that were previously bound on the same device
- any unrelated public journeys

Historical roots may exist on disk, but they must only be surfaced through an explicit manual recovery flow, never silently merged into the current display state.

### Tracking / Auth Rule

Once a journey starts, tracking is local-first and independent of login state.

If passive logout happens during tracking:

- tracking continues locally
- the ongoing journey remains resumable
- Live Activity keeps updating
- auth loss only disables account-required features such as remote sync or publishing

If the user ends a journey while logged out and wants it public/friends-visible:

- save the journey locally
- mark it as pending visibility publication
- show a prompt telling the user to log in before publishing

---

## Current Root Causes

### Root Cause A: Over-Broad Auto Recovery

`UserSessionStore` currently treats multiple local roots as automatic recovery candidates.

Current behavior effectively allows:

- all discovered `guest_*` roots on the device
- all historically bound `account_*` roots for the same guest/device

to be merged into the current active local profile.

This is why another user's journeys can appear in the current device view.

### Root Cause B: Display State Is Backed By Mutable Merged Storage

`collection_tab` reads from the shared app stores (`JourneyStore`, `CityCache`) that are populated from the active local storage root.

Because recovery writes directly into that root, once bad data is merged, the display layer cannot distinguish:

- current-device guest journeys
- current-account journeys
- stale historical recovered content

### Root Cause C: Tracking/Auth/Live Activity Are Restored Separately

During passive logout:

- auth session changes
- tracking may still be alive
- ongoing journey data may still exist in `JourneyStore`
- Live Activity may still exist at the system level

But there is no single reattachment path that restores:

- ongoing journey snapshot
- tracking runtime state
- current Live Activity handle
- resume-first UI state

So the app can show a "start" feeling while a stale Live Activity remains on screen.

---

## Recommended Architecture

### 1. Separate Data Sources From Display State

Create a strict source model:

- `device_local_source`
  - the current `local_<guestID>` root only
- `account_remote_source`
  - only the currently logged-in account's synced journey cache
- `manual_recovery_candidates`
  - historical `guest_*` and `account_*` roots shown only in explicit recovery UI

Then create a derived display model:

- `display_journeys = merge(device_local_source, account_remote_source)`
- `display_city_cache = rebuild(display_journeys)`

The display model is a controlled projection, not an unbounded recovery target.

### 2. Narrow Automatic Recovery Scope

Automatic recovery should only pull from:

- the current device-local active guest/local state
- the currently authenticated account's data

Automatic recovery should never silently import:

- any other historical guest root
- any previously bound but currently inactive account root

Those remain manual-only recovery candidates.

### 3. Add Explicit Journey Source Metadata

Each displayable journey should carry lightweight source metadata, for example:

- `originKind`: `deviceGuest` or `accountRemote`
- `originGuestID`
- `originAccountID`
- `ownerAccountID`

This lets startup validation reject data that does not belong to the current display scope.

### 4. Persist Ongoing Tracking Session Independently

Add a dedicated local tracking session snapshot that stores:

- ongoing journey ID
- start time
- paused duration
- tracking mode
- pause state
- last sync timestamp

This snapshot must survive passive logout and app relaunch.

### 5. Reattach Live Activity Instead Of Assuming In-Memory Ownership

`LiveActivityManager` must be able to rebind to an already-running system activity by querying:

- `Activity<TrackingActivityAttributes>.activities`

On app foreground / relaunch / post-login recovery, the manager should:

- discover an existing tracking activity
- attach it as `currentActivity`
- restore timer-driven updates
- continue updating instead of starting a new activity

---

## Data Flow

### Collection Tab Startup Flow

1. Restore auth/session.
2. Load `device_local_source` from current `local_<guestID>`.
3. If logged in, load `account_remote_source` for current `accountUserID`.
4. Build `display_journeys` from exactly those two sources.
5. Rebuild city and memory grouping from `display_journeys`.
6. Reject any recovered journey whose source metadata is out of scope.

### Passive Logout During Tracking

1. Auth layer transitions to logged-out state.
2. Tracking runtime is left untouched.
3. Ongoing journey continues writing to local storage.
4. Live Activity continues updating from local tracking state.
5. UI shows the same ongoing journey.
6. Any action that requires auth is gated separately.

### Journey End While Logged Out

1. User ends journey.
2. Journey is finalized locally.
3. If selected visibility is public/friends-only and auth is absent:
   - save locally
   - mark a pending publish/visibility intent
   - present "saved locally, log in to publish"

---

## Migration / Cleanup

We need a one-time cleanup for already polluted users.

### Cleanup Strategy

For the current active profile:

1. Load current local data.
2. Load current account data if logged in.
3. Recompute the allowed display set from only those two sources.
4. Remove out-of-scope journeys from display storage/cache.
5. Rebuild `CityCache` from the cleaned journey set.

Historical roots must not be deleted automatically; only excluded from display and recovery unless manually chosen.

---

## UX Changes

### Collection Issue UX

No visible UI change is required except more reliable content.

Optional debug logging can help validate:

- how many local journeys were loaded
- how many account journeys were loaded
- how many out-of-scope journeys were rejected

### Tracking/Auth UX

If passive logout occurs during tracking:

- do not interrupt the tracking screen
- optionally show a lightweight banner: "You're logged out. Tracking continues locally."

If ending a journey while logged out but public sharing was requested:

- show: "Journey saved locally. Log in to publish it publicly."

---

## Testing Strategy

### Collection Isolation Tests

- active display only includes current local guest journeys
- active display only includes current logged-in account journeys
- historical guest roots are excluded from automatic display merge
- previously bound inactive account roots are excluded from automatic display merge
- polluted cache cleanup rebuilds the correct city and memory groupings

### Tracking/Auth Resume Tests

- passive logout during active tracking does not clear ongoing journey
- relaunch/login restores ongoing journey UI from local snapshot
- Live Activity manager reattaches to existing system activity
- ending a journey while logged out stores a pending publish intent instead of failing

---

## Rollout Notes

This should land in two stages:

1. stop future corruption
   - narrow automatic recovery
   - separate display state from recovery candidates
   - reattach Live Activity

2. repair existing corrupted states
   - one-time cleanup/rebuild for active local display data

This ordering minimizes further user-facing damage while making cleanup deterministic.
