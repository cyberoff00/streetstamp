# Social Notification Read Sync Design

## Goal
- Make the two in-app social notification entry points stay in sync.
- When a user marks one notification or all notifications as read in either entry point, the other entry point should update immediately.

## Root Cause
- `ProfileView` and `FriendsHubView` each keep their own `socialNotifications` array and `unreadSocialCount`.
- After a read action succeeds, each view only mutates its own local state.
- The other entry point does not learn about that change until it refreshes from the backend later.

## Recommended Approach
- Keep the existing backend API and per-screen local state.
- Add a lightweight in-app read-sync event over `NotificationCenter`.
- After either screen marks notifications as read successfully, it should broadcast which IDs changed, or that all loaded social notifications should be treated as read.
- Both screens should listen for that event and apply the same read-state update to their own local arrays and unread counts.

## Data Flow
1. A user taps a single social notification or the mark-all-read action in either entry point.
2. The active screen calls `BackendAPIClient.markNotificationsRead`.
3. On success, that screen updates its own local `socialNotifications`.
4. The screen posts a read-sync event with either the specific notification IDs or an `all` flag.
5. `ProfileView` and `FriendsHubView` both observe the event and update their loaded notification arrays in place.
6. Any unopened screen still gets the correct state later from its normal refresh path.

## Error Handling
- Only broadcast after the backend request succeeds.
- If a screen has not loaded notifications yet, applying the event should be a no-op.
- Existing polling and scene-activation refresh behavior remains unchanged as a backend-source-of-truth fallback.

## Testing
- Add unit tests for the sync helper that applies single-ID updates and mark-all updates.
- Run the focused test target after implementation.
