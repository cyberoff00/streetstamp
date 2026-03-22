# Device-Wide Manual Repair Design

**Goal:** Keep normal app startup/login flows completely clean while moving all legacy and historical local data recovery into the existing Settings data-repair entrypoint.

## Approved Rules

- Remove all automatic local recovery.
- Remove all automatic restore calls from startup/login/switch-user flows.
- Keep normal cloud sync behavior.
- Make the existing Settings repair action the only place allowed to recover historical local data.
- Manual repair scans all user roots on this device (`legacy_*`, `guest_*`, `account_*`, `local_*`, plus any other local app roots found on disk).
- Manual repair deduplicates by `journeyID`.
- Deleted journeys must never be restored again.
- After import, city-card state is rebuilt from the repaired journey set using the current journey-driven flow.

## Architecture

Normal runtime becomes strict:

- bootstrap filesystem only creates directories and runs one-time migrations
- startup loads the active local profile only
- startup/login/switch-user do not import historical roots
- startup/login/switch-user do not auto-restore cloud backups

Manual repair becomes explicit:

1. Discover every on-device user root under Application Support.
2. Load all journey IDs that still have real files.
3. Exclude IDs already present in the active profile.
4. Exclude IDs recorded in a local deleted-journey tombstone list.
5. Import remaining sources into the active profile.
6. Rebuild ordered journey index.
7. Rebuild city cache from the repaired journey set.

## Data Protection Rule

Deleting a journey writes its `journeyID` into a persistent local tombstone file for the active profile.

Repair logic must consult this tombstone file and skip those IDs even if they still exist in another source root on disk.
