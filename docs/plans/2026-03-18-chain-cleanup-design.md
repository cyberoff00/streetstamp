# Chain Cleanup Design

**Date:** 2026-03-18

**Scope:** Remove three fallback-driven behaviors that currently blur the main product logic:
- Lifelog render snapshots inventing dashed bridges between adjacent runs
- Journey deletion swallowing migration-sync failures
- Motion activity being controlled from multiple owners

## Problem

The current codebase has several places where "best effort" logic has crossed the line into changing product meaning.

In rendering, the app now draws dashed connectors between any two adjacent lifelog runs even when the product has no evidence that the user actually traveled that path.

In journey deletion, the app hides migration-sync failures with `try?`, so the local delete path can succeed while remote state silently diverges.

In motion activity lifecycle, both `StreetStampsApp` and `TrackingService` decide whether motion updates should run, and they do so from different state sources. That creates two writers for one decision.

These are not harmless safety nets. They make the chain of truth ambiguous.

## Goals

- Render only observed route structure. Do not synthesize path continuity from adjacency alone.
- Make journey deletion sync failures visible and explicitly tracked instead of silently ignored.
- Establish one owner for motion activity run policy and one state source for that decision.

## Non-Goals

- No new retry framework
- No new lifecycle coordinator abstraction
- No broad sync-system redesign
- No UI redesign for error surfacing beyond what is needed to make deletion-sync failure observable in app state

## Decision 1: Remove Adjacent Run Auto-Bridging

`LifelogRenderSnapshotBuilder` will stop appending synthetic dashed segments between adjacent runs.

The rendering layer must only transform recorded segments into displayable geometry. It must not infer travel continuity from timestamps, sort order, or segment adjacency. If a future product requirement needs inferred gaps, that logic must originate upstream as an explicit domain segment type with its own proof rules. It cannot be fabricated inside the snapshot builder.

### Resulting rule

- If the underlying run/segment does not contain a connection, the renderer does not draw one.

## Decision 2: Journey Deletion Sync Must Become Explicitly Observable

Deleting a journey remains a local-first action in `JourneyStore`, but remote migration deletion can no longer fail silently.

The deletion hook will still kick off asynchronous remote work, but any migration-sync failure must be captured in explicit app state instead of being discarded. The system should record which journey deletion failed migration sync and the associated error summary so the app can reason about it later.

The shortest-path implementation is to add a small store for pending deletion-sync failures and have `StreetStampsApp` write into it from the delete hook. This keeps local deletion behavior unchanged while removing the "pretend success" branch.

### Resulting rule

- Local deletion may complete before remote deletion.
- Remote deletion failure is not swallowed.
- Remote deletion failure must be recorded in a first-class state holder.

## Decision 3: `StreetStampsApp` Owns Motion Activity Policy

Motion activity run policy will have exactly one owner: `StreetStampsApp`.

`TrackingService` will no longer call `setShouldRun` or compute the policy. It can continue to consume `MotionActivityHub.snapshot`, but it cannot decide whether motion updates are active.

The policy inputs are:
- `TrackingService.shared.isTracking`
- `lifelogStore.isEnabled`
- `locationHub.authorizationStatus == .authorizedAlways`

Those inputs are already available in `StreetStampsApp`, which also already reacts to app lifecycle and settings changes. That makes it the narrowest correct owner.

### Resulting rule

- `MotionActivityHub.setShouldRun` is only called from `StreetStampsApp`.
- The source of truth for passive lifelog state is `lifelogStore.isEnabled`, not direct `AppSettings` reads inside unrelated services.

## Data Flow

### Lifelog rendering

1. Track/lifelog storage produces recorded segments.
2. Snapshot builder transforms recorded segments into display segments.
3. No synthetic adjacency bridge is inserted.

### Journey deletion

1. `JourneyStore` removes the journey locally.
2. Delete sync hook fires CloudKit deletion.
3. Delete sync hook fires migration deletion.
4. If migration deletion fails, the app records a failure entry.
5. Failure remains inspectable instead of disappearing.

### Motion activity

1. `StreetStampsApp` watches tracking state, lifelog enabled state, and authorization state.
2. `StreetStampsApp` computes `MotionActivityPolicy.shouldRun(...)`.
3. `StreetStampsApp` is the only caller of `MotionActivityHub.setShouldRun(...)`.

## Testing Strategy

- Add/extend snapshot tests proving adjacent runs remain disconnected unless the source segments already connect them.
- Add/extend deletion-sync tests proving migration failure is recorded rather than swallowed.
- Add/extend motion policy tests proving the policy still computes correctly, and add a structural test around the new single-owner sync path where practical.

## Acceptance Criteria

- No code path in `LifelogRenderSnapshotBuilder` creates adjacency-based dashed bridges.
- Journey deletion migration failures are no longer dropped via `try?`.
- A dedicated state holder records failed deletion sync attempts.
- `TrackingService` no longer owns motion activity run policy updates.
- `StreetStampsApp` is the only place that writes `MotionActivityHub.setShouldRun(...)`.
