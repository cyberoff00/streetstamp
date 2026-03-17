# App Idle Location Lifecycle Design

## Background
The current app startup path eagerly enables passive location tracking whenever no Journey is running. That makes the app behave as if passive Lifelog is always on, which increases background battery drain and makes the in-app passive toggle feel misleading.

The desired behavior is narrower:
- App launch may fetch one location for bootstrap needs such as `cityKey`.
- App foreground re-entry may fetch one fresh location again.
- Continuous location updates should only exist while an active Journey is running, or while the user has explicitly enabled passive Lifelog and granted `Always` authorization.

## Goals
- Stop continuous idle location tracking when both Journey and passive Lifelog are off.
- Keep a single-shot location fetch on cold launch and each foreground re-entry.
- Make passive Lifelog startup depend on both user intent and `authorizedAlways`.
- Reduce passive sampling density to:
  - high precision: `35m`
  - low precision: `70m`
- Reduce daily Journey base location density at the Core Location layer to:
  - `desiredAccuracy = kCLLocationAccuracyNearestTenMeters`
  - `distanceFilter = 15`
- Preserve Journey tracking behavior and ownership.

## Non-Goals
- Do not redesign Journey sport/daily tracking policies in this change.
- Do not redesign map rendering, tile rebuilds, or Lifelog UI layout.
- Do not attempt to bypass iOS force-quit background limitations.

## Agreed Product Rules
### 1) Bootstrap location
- On cold app launch, request one location sample.
- Use it for bootstrap needs such as city resolution and initial UI positioning.
- Do not keep continuous updates alive after that sample if Journey and passive Lifelog are both off.

### 2) Foreground refresh
- Each time the app returns to foreground, request one location sample again.
- This keeps `cityKey` and current-position affordances reasonably fresh without continuous idle tracking.

### 3) Journey ownership
- Journey start still switches `LocationHub` into the existing active tracking modes.
- Journey stop returns the app to non-continuous idle behavior unless passive Lifelog should be running.
- Passive Lifelog must never override an active Journey policy.

### 4) Passive ownership
- Passive Lifelog only starts when:
  - the user has enabled passive recording, and
  - authorization is `authorizedAlways`.
- If the user disables passive recording, continuous passive tracking stops.
- If the user enables passive recording without `Always` permission, the app should not start passive background tracking.

## Approach Comparison
### A. Separate bootstrap and passive lifecycles (selected)
- Add a single-shot bootstrap/foreground refresh path.
- Keep passive and Journey as explicit continuous modes.
- Pros: clean ownership, matches product language, easiest to reason about.
- Cons: requires touching app lifecycle and passive toggle semantics together.

### B. Keep one lifecycle and layer many guards on top
- Reuse the current passive startup path with more conditions.
- Pros: fewer API additions.
- Cons: harder to reason about, higher risk of future regressions, state becomes implicit.

### C. Leave GPS running but drop more points in stores
- Reduce persistence and rendering work only.
- Pros: smallest code diff.
- Cons: does not solve the real battery issue because Core Location still runs continuously.

## Architecture Design
### 1) Add an explicit single-shot API in `LocationHub`
`LocationHub` should expose a dedicated one-time refresh path backed by `CLLocationManager.requestLocation()`.

This path should:
- request permission if needed,
- issue a one-shot sample when authorized,
- avoid enabling background updates,
- avoid starting heading updates,
- leave the manager idle after completion.

### 2) Stop auto-starting passive tracking from app lifecycle
`StreetStampsApp.ensurePassiveLocationTrackingIfNeeded()` should no longer mean "start passive whenever no Journey is active."

It should instead mean:
- if Journey is active: do nothing,
- else if passive is enabled and authorization is `authorizedAlways`: start passive mode,
- else: keep location idle.

Cold launch and foreground entry should separately call the one-shot refresh API.

### 3) Make passive toggle represent actual passive runtime
The Lifelog passive toggle should no longer only gate writes in `LifelogStore`.

It should represent whether passive recording is actually intended to run:
- turning it off stops passive mode and prevents point ingestion,
- turning it on starts passive mode only if `Always` authorization is present,
- missing `Always` permission keeps the toggle in a blocked/not-armed state rather than silently running no-op behavior.

### 4) Simplify passive Core Location profiles
`SystemLocationSource` passive modes should become coarse continuous profiles:
- high precision passive:
  - `desiredAccuracy = kCLLocationAccuracyNearestTenMeters`
  - `distanceFilter = 50`
- low precision passive:
  - `desiredAccuracy = kCLLocationAccuracyHundredMeters` or nearest practical coarse equivalent
  - `distanceFilter = 100`

This change intentionally trades route detail for battery savings.

### 5) Keep Journey modes unchanged
Journey ownership and sport-mode behavior remain unchanged in this scope. For daily Journey mode, only the base Core Location profile is relaxed to a lower-power setting:
- `desiredAccuracy = kCLLocationAccuracyNearestTenMeters`
- `distanceFilter = 15`

The only other Journey-adjacent change is what happens after Journey ends: the app should either return to passive mode if eligible, or remain idle except for future single-shot refreshes.

## Expected UX Changes
- Entering the app no longer silently starts continuous passive tracking.
- Returning to foreground refreshes location once, then stops again.
- Passive Lifelog only runs when the user explicitly armed it and granted `Always`.
- Lifelog passive tracks become sparser and less detailed than before.

## Risks And Mitigations
- Risk: some views may assume `currentLocation` keeps streaming while idle.
  - Mitigation: rely on last-known location for fallback UI and refresh once on foreground entry.
- Risk: first bootstrap `requestLocation()` may be slow or fail indoors.
  - Mitigation: tolerate missing bootstrap location and retry on next foreground entry.
- Risk: passive tracks lose small turns and short walks with 35m/70m filters, and daily Journey may soften some fine-grained path detail with the lower-power base location profile.
  - Mitigation: accept this as an explicit battery-saving tradeoff and scope change.
- Risk: the current Lifelog toggle semantics change.
  - Mitigation: align UI behavior and permission prompts so the toggle clearly represents actual passive runtime state.

## Acceptance Criteria
- Cold launch performs at most one bootstrap location fetch when idle.
- Foreground re-entry performs one fresh location fetch when idle.
- If Journey is off and passive is off, continuous location updates are not running.
- If passive is on but authorization is not `authorizedAlways`, passive background tracking does not start.
- Passive high precision uses `35m` distance filtering.
- Passive low precision uses `70m` distance filtering.
- Daily Journey base location uses `nearestTenMeters` accuracy with `15m` distance filtering.
- Journey start and stop still preserve existing Journey tracking behavior.
