# Guest Recovery Source Scope Design

Date: 2026-03-09
Status: Approved
Owner: Codex + liuyang

## Background

`UserSessionStore` currently scopes automatic local recovery sources by both `guestID` and `sourceDevice` for all source types. This is safe for legacy `account_*` buckets, but it is too restrictive for `guest_*` recovery on the current device because the device may still hold recoverable local guest data even when the saved binding metadata was written under a different `sourceDevice` value.

The current behavior can miss local guest data that physically exists on the device and should be merged into the active `local_*` profile.

## Goal

Broaden automatic recovery of local `guest_*` buckets that physically exist on the current device, while keeping legacy `account_*` recovery conservative and device-scoped.

## Non-Goals

- no change to cloud download and merge behavior
- no removal of `sourceDevice` restrictions for legacy `account_*` recovery
- no destructive overwrite of existing local data during automatic recovery
- no new semantic deduplication of journeys or photos beyond current file-level behavior

## Proposed Rule

Split automatic recovery source discovery into two classes:

### 1. Guest Recovery Sources

Automatic recovery may consider any `guest_*` directory that:

- physically exists in the current device's app sandbox
- is not the target `local_*` directory
- has recoverable data according to the existing `hasRecoverableData` checks

This discovery path must not require a matching `sourceDevice` value in binding metadata.

### 2. Legacy Account Recovery Sources

Automatic recovery may consider `account_*` directories only when they come from an explicit guest-to-account binding whose:

- `guestID` matches the current session guest
- `sourceDevice` matches the current device

This path remains unchanged and conservative.

## Recovery Behavior

Automatic recovery should continue to use `GuestRecoveryOptions.conservativeAuto`:

- do not replace existing journey files
- do not replace lifelog with a more complete source during automatic startup recovery
- copy only missing photos and thumbnails
- merge journey indexes by ID

This preserves the current safety posture:

- low risk of destructive overwrites
- possible retention of duplicate logical content when old buckets already diverged

## Rationale

This rule matches the product intent more closely:

- if guest data is already on the current device, startup recovery should be able to discover it
- legacy `account_*` data remains more sensitive and should still require device-local provenance

It also narrows the change to source discovery only. The merge semantics remain unchanged, reducing regression risk in startup flows.

## Edge Cases

### Multiple Guest Buckets On One Device

If the sandbox contains multiple recoverable `guest_*` directories, the recovery service should continue ordering candidates by modification date and applying existing idempotent recovery markers to avoid repeated work.

### Device Mismatch In Old Metadata

If binding metadata points at a different `sourceDevice`, local `guest_*` directories on the current device can still be recovered through the new guest discovery path. Legacy `account_*` directories still remain excluded in that case.

### Duplicate Logical Content

If two guest buckets contain semantically identical journeys or photos under different IDs or filenames, the current merge logic may preserve both. This is accepted for automatic recovery because the startup path favors non-destructive merge over aggressive cleanup.

## Acceptance Criteria

- startup recovery can discover local `guest_*` buckets on the current device even when old binding metadata has a mismatched `sourceDevice`
- startup recovery still limits legacy `account_*` sources to bindings that match both current `guestID` and current `sourceDevice`
- automatic recovery remains non-destructive under `GuestRecoveryOptions.conservativeAuto`
- already recovered sources are not reprocessed on every launch
