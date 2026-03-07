# Local Profile and Auth Decoupling Design

Date: 2026-03-07
Status: Approved
Owner: Codex + liuyang

## Background

`StreetStamps` currently binds local on-device storage to the current session identity:

- guest mode uses `guest_<guestID>`
- account mode uses `account_<appUserID>`

When the user logs out, the app switches from the account-scoped storage root back to the guest-scoped root and rebinds all major local stores. This makes it appear that local data has disappeared, even though the account-scoped files still exist on disk. The problem becomes worse when auth migrations or account-unification issues produce a new backend `appUserID`, because the app then treats the same person as a completely different local storage bucket.

The product requirement is now different:

- a user who logs out should still see the full local data on that device
- a user who temporarily cannot log in should still see the full local data on that device
- a user who signs in on a new device should be able to restore synced account data there

## Goal

Decouple local storage ownership from authentication state so the device has one stable local profile, while account login only controls cloud identity and sync permissions.

## Non-Goals

- no automatic multi-profile local switching UI in this change
- no deletion of existing `guest_*` or `account_*` roots during the initial rollout
- no silent merge of unrelated cloud accounts into one local profile
- no redefinition of what data is eligible for cloud sync

## Product Rules

### 1. Local Data Belongs to the Device Profile

The current device should have one stable local profile ID:

- `local_<deviceProfileID>`

That local profile owns the on-device copies of journeys, lifelog data, caches, photos, thumbnails, profile display state, and other local artifacts.

### 2. Authentication Only Controls Cloud Identity

Authentication should no longer determine which local root is visible. Instead:

- `authenticatedAccountUserID` is the current cloud identity, if any
- `activeLocalProfileID` is the current local storage root

The app must continue to show the same local data when:

- the user logs out
- login fails
- email is unverified
- backend auth is temporarily unavailable

### 3. New Device Login Restores Cloud Data into the Local Profile

On a new device:

- create a fresh `local_<deviceProfileID>`
- after successful login, fetch the account's cloud-backed data
- merge that cloud data into the local profile on that device

This is a cloud restore into `local_*`, not a switch into an `account_*` local directory.

### 4. Existing Account-Scoped and Guest-Scoped Roots Are Legacy

Existing roots such as:

- `guest_<guestID>`
- `account_<appUserID>`

should be treated as legacy migration sources. They should not remain the primary long-term runtime model.

## Proposed Architecture

### 1. Split Local Identity from Session Identity

Replace the current one-axis identity model with two axes:

- local identity: `activeLocalProfileID`
- auth identity: `authenticatedAccountUserID`

`StoragePath` for runtime local stores should be created from `activeLocalProfileID`, not from the auth session.

### 2. Local Stores Bind Only to `activeLocalProfileID`

The following stores should use the active local profile only:

- `JourneyStore`
- `LifelogStore`
- `CityCache`
- `TrackTileStore`
- render caches and related derived artifacts
- local photos and thumbnails

Changing auth state must not rebind those stores.

### 3. Cloud Sync Uses Account Identity Separately

Cloud sync, profile fetch, upload, and restore flows should use `authenticatedAccountUserID` and the account token state. The sync layer may read and write data from the current local profile, but it must not redefine which local root is active.

### 4. Upgrade Migration Creates a Stable `local_*` Root

On first launch after this change:

- if `local_*` already exists, use it
- otherwise create one and migrate into it from the best legacy source roots

Legacy roots remain as backup for safety during rollout.

## Data Model

### Session State

Introduce explicit separation in session/runtime state:

- `activeLocalProfileID: String`
- `authenticatedAccountUserID: String?`
- auth credentials and verification state

The old `currentUserID` concept should no longer be the source of truth for local storage binding.

### Local Metadata

Add lightweight metadata for the local profile, for example:

- current local profile ID
- migration completion markers
- legacy source roots already imported
- last successful cloud restore marker

### Legacy Mapping Metadata

Keep enough metadata to explain how a device arrived at the local profile:

- imported from which `guest_*`
- imported from which `account_*`
- last import time

This is mainly for safety and diagnostics.

## Migration Strategy

### 1. New Install

For new installs:

- create `local_<deviceProfileID>`
- use it immediately
- no guest/account local roots should be created as primary storage

### 2. Existing Install Upgrade

For existing installs:

- detect whether a `local_*` root already exists
- if not, inspect legacy `guest_*` and `account_*` roots
- choose the most complete and recently active root as the base
- merge unique data from the remaining roots into the new `local_*`
- write a migration-complete marker

### 3. Merge Rules by Data Type

Use data-aware merging instead of directory overwrite:

- journeys: merge by journey ID
- lifelog and mood data: merge by day/event identity
- photos and thumbnails: merge by filename or stable dedupe key
- user-scoped profile state in defaults: prefer the most recently active source
- caches and derived render artifacts: rebuild instead of migrate where practical

### 4. Safety Rules

Migration must follow conservative rules:

- never replace non-empty data with empty data
- never delete legacy roots in the first migration pass
- never trigger legacy migration because of logout or login failure
- never rerun a completed migration without an explicit recovery path

## Runtime Behavior

### Login

On login:

- keep `activeLocalProfileID` unchanged
- attach `authenticatedAccountUserID`
- enable cloud fetch/upload
- optionally restore cloud data into the current `local_*`

### Logout

On logout:

- keep `activeLocalProfileID` unchanged
- clear `authenticatedAccountUserID`
- disable cloud operations
- continue showing the same local data

### Login Failure / Email Unverified

When login fails or email is unverified:

- keep `activeLocalProfileID` unchanged
- keep local data visible
- surface auth state only as a cloud capability limitation

### New Device Sign-In

On a new device:

- create or load that device's `local_*`
- after login, restore account-backed cloud data into that local profile
- do not create or switch into `account_<appUserID>` as the primary runtime root

## Risks

### 1. Duplicate or Conflicting Legacy Data

Some devices may contain both old guest and old account roots with overlapping journeys or cached lifelog state. Migration must dedupe conservatively and avoid destructive overwrites.

### 2. Account Unification Bugs Still Matter

Even after local/auth decoupling, backend identity resolution must still unify the same person back to the same account for cloud continuity. This change reduces local data disappearance but does not remove the need for correct backend account mapping.

### 3. Sync Merge Semantics Need Clear Boundaries

Cloud restore into the current local profile must avoid overwriting newer unsynced local data. Restore should prefer merge semantics rather than blind replacement.

## Acceptance Criteria

- logging out does not change the visible local data on the device
- failed login does not change the visible local data on the device
- email-unverified state does not change the visible local data on the device
- runtime local stores bind to `local_*`, not `guest_*` or `account_*`
- upgrading from a legacy install preserves the device's existing local data in the new `local_*`
- signing into the same account on a new device restores cloud-backed data into that device's `local_*`
