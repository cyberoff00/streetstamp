# 2026-03-12 Settings Notifications Design

## Goal
- Remove duplicate live activity and stationary reminder toggles from the main settings page.
- Move both toggles into the notifications detail page.
- Keep Live Activity toggle disabled and greyed out when the system permission is off, with guidance to Settings -> Worldo -> Live Activities.

## UI changes
- Tracking Assist section keeps only the background mode card.
- Notifications page contains voice broadcast, live activity, and stationary reminder controls.
- Live Activity row shows support copy when available, and shows Settings guidance copy when the system permission is disabled.

## Behavior
- App-level Live Activity toggle still controls in-app preference.
- Turning the app-level toggle off ends any current live activity.
- When system permission is off, the toggle is disabled and not duplicated elsewhere.

## Tests
- Update settings presentation tests to assert the main settings page no longer includes the moved toggles.
- Add tests for notifications page toggle composition and Live Activity disabled guidance copy.
