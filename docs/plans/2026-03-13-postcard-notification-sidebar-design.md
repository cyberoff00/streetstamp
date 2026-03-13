# Postcard Notification Sidebar Routing Design

## Goal
- Make tapping a postcard notification open the sidebar postcard page immediately.
- Remove the extra dependency on dismissing the notification UI before the app shows the postcard inbox.

## Root Cause
- Notification taps currently call `UIApplication.shared.open(url)` from `UNUserNotificationCenterDelegate`.
- The app then waits for SwiftUI `onOpenURL` to run, switch context, and eventually show a postcard inbox elsewhere.
- That handoff depends on system dismissal and scene activation timing, so the inbox can appear only after the notification UI is gone.

## Recommended Approach
- Introduce an app-level postcard sidebar route in `AppFlowCoordinator`.
- Let notification taps request that route directly instead of re-opening the app through `UIApplication.shared.open(url)`.
- Update app URL handling so postcard deep links reuse the same route and open the sidebar postcard page as well.

## UI Behavior
- Tapping a postcard notification opens the existing sidebar postcard sheet.
- The sheet continues to render `PostcardInboxView`.
- If the deep link includes a `messageID`, the inbox opens with the existing focus behavior for the received postcard.

## Data Flow
1. A postcard notification tap reaches `AppNotificationDelegate`.
2. The delegate parses the notification deep link into a `PostcardInboxIntent`.
3. The delegate writes that intent into `AppFlowCoordinator`.
4. `MainTabView` observes the app-level route signal, opens the `.postcards` sidebar sheet, and passes the intent into `SidebarPostcardsEntryView`.
5. `PostcardInboxView` handles initial box selection and focused message rendering.

## Testing
- Add unit tests for postcard deep-link parsing.
- Add unit tests for the new app-level postcard sidebar routing signal and intent consumption.
- Run focused `xcodebuild test` coverage for the new tests before closing the task.
