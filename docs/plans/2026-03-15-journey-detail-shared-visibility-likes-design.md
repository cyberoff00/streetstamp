# Journey Detail Shared Visibility Likes Design

**Problem:** `JourneyMemoryNew.swift` currently has its own custom visibility sheet, while `MyJourneysView.swift` already contains the production visibility and likes sheets. The duplicate implementation has already drifted in styling and behavior, and the detail page still cannot present the original likers list flow.

**Goal:** Reuse the existing journey visibility and likes experience on the journey memory detail page without breaking the current My Journeys and friend-journeys flows.

## Approach Options

### Option 1: Keep two separate implementations

Keep the custom detail-page sheet in `JourneyMemoryNew.swift` and continue evolving it independently.

**Trade-offs:** Fastest short-term, but it guarantees more UI drift and duplicate state/network logic. It also means any future visibility or likes changes must be implemented twice.

### Option 2: Extract the original sheets into shared components

Move the original journey visibility sheet, journey likes sheet, and small presentation helpers into a shared file. Then make both `MyJourneysView.swift` and `JourneyMemoryNew.swift` consume those shared types.

**Trade-offs:** Slightly more refactor work now, but it keeps one source of truth for behavior, styling, copy, and likers presentation. This is the recommended option.

### Option 3: Inline-copy the original UI into the detail page

Copy the current `MyJourneysView` sheet UI and likers list into `JourneyMemoryNew.swift`.

**Trade-offs:** This looks correct initially, but it still creates a second maintenance path and repeats the networking and state logic. Better than the current simplified sheet, but still not the right long-term shape.

## Approved Design

We will use Option 2.

### Shared components

Create a shared Swift file for:
- `JourneyVisibilitySheetAccentStyle`
- `JourneyVisibilitySheetOptionPresentation`
- `JourneyVisibilitySheetPresentation`
- `JourneyLiker`
- `JourneyLikesSheet`
- `JourneySheetScaffold`
- a tiny presentation helper for detail-page primary action routing

`JourneyVisibilitySheet` itself will also move into the shared file so the original styling remains unchanged.

### Detail-page behavior

The status chip in `JourneyMemoryNew.swift` will use this rule:
- if the journey has one or more likes, tapping opens the likers sheet first
- otherwise, tapping opens the visibility sheet

Inside the likers sheet, the existing “change permission” action will open the shared visibility sheet, matching the flow already used in `MyJourneysView`.

### Data flow

`JourneyMemoryNew.swift` will keep page-local state for:
- likes count
- likers list
- loading/error states
- which shared sheet is currently presented

The detail page will reuse the existing backend calls already used elsewhere:
- like stats via `BackendAPIClient.fetchJourneyLikeStats`
- liker identities from `BackendAPIClient.fetchNotifications`
- visibility updates via `JourneyCloudMigrationService.syncJourneyVisibilityChange`

### Error handling

- visibility-denial behavior will continue using `JourneyVisibilityPolicy`
- likes loading errors will surface in the shared likes sheet via its existing error card and retry action
- if the user is not logged in, the detail page will preserve the current guard behavior and not attempt remote liker loading

### Testing

Add a focused presentation test around the detail-page sheet-routing helper so the new reuse path is covered by TDD without requiring SwiftUI snapshot infrastructure.

