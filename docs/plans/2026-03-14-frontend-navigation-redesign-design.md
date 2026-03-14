# Frontend Navigation Redesign Design

## Summary

Refactor the app's primary navigation away from the mixed `TabView + sidebar` model into a fixed five-tab structure. The new bottom tab order is:

1. Home
2. Worldo
3. Footprints
4. Friends
5. My Profile

The sidebar is removed entirely. `Worldo` becomes a two-page horizontally swipeable container that hosts the existing city view and the existing memory view. The standalone "My Journeys" landing page is removed from primary navigation, and each memory gains a route-level entry point into its associated journey deep view. Child pages should prefer system push/pop navigation so interactive swipe-back works without relying on top-right custom back controls.

## Goals

- Remove all sidebar-driven primary navigation affordances.
- Preserve the existing five primary app areas using a pure bottom-tab model.
- Merge memories into `Worldo` as the second horizontally swipeable page.
- Remove the standalone journey landing page from top-level navigation.
- Keep the existing profile implementation and expose it as the last tab.
- Favor system navigation behavior so child screens can be dismissed with the standard edge-swipe back gesture.

## Non-Goals

- Redesigning the visual language of existing feature pages.
- Rebuilding the profile page.
- Reworking core `Lifelog`, `Friends`, `City`, or `Memory` business logic beyond what is needed for navigation.
- Replacing every custom header in the app in one pass.

## Current-State Notes

- `MainTabView` already uses `TabView`, but still owns sidebar state, sidebar gestures, sidebar sheets, and a hamburger launcher.
- `CollectionTabView` currently uses a segmented control for `cities` and `journeys`.
- `JourneyMemoryMainView` exists as a standalone tab page.
- `MyJourneysView` is a standalone top-level page and contains journey deepview behavior that should remain reachable.
- Several child pages hide the system back button and render custom dismiss controls, which can interfere with interactive pop.

## Approved Design

### 1. Primary Navigation

- Remove sidebar enum-driven destinations and sidebar presentation state from `MainTabView`.
- Convert `profile` into a first-class bottom tab.
- Remove `memory` from bottom tabs.
- Keep `start`, `cities` (Worldo), `lifelog`, `friends`, and `profile` as the only bottom tabs in that order.

### 2. Worldo Structure

- Replace the segmented `CollectionTabView` with a horizontally swipeable two-page container.
- Page 1 is the existing city content.
- Page 2 is the existing memory content.
- The two pages should feel like sibling surfaces, not drill-in routes.

### 3. Memory to Journey Flow

- Remove the standalone "My Journeys" entry point from top-level UI.
- Keep journey deepview reachable from each memory context.
- Add an entry card or clearly framed block above the overall memory content in memory detail so users can open the associated journey deepview from the memory they are currently viewing.

### 4. Back Navigation

- Prefer `NavigationStack` push/pop for child flows.
- Avoid right-top custom back controls as the primary way out of a child screen.
- Where a custom header must remain, preserve a left-leading dismiss affordance without disabling the system's interactive pop gesture.

## Risks

- Existing onboarding logic references the old `memory` tab and `CollectionTabView`'s journeys segment.
- Tests currently encode the old bottom-tab order.
- `MyJourneysView` and memory detail flows likely share view logic in a way that will require careful extraction or reuse.
- Some pages may still intentionally hide the system back button for styling; those need selective cleanup rather than blanket removal.

## Verification Strategy

- Update unit tests for tab order and tab render policy.
- Add or adjust tests around the new Worldo two-page structure if practical.
- Build and run focused test targets covering tab layout and affected navigation policies.
