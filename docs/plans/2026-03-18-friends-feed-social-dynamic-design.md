# Friends Feed Social Dynamic Design

**Problem:** The current friends feed is clearer than before, but it still reads more like a structured activity log than a social dynamic stream. Cards are informative, yet the visual hierarchy and copy do not create enough "someone just did something" energy.

**Goal:** Reframe the activity feed so it feels closer to a lightweight Instagram-style social stream without introducing photo previews. The feed should emphasize people, actions, recency, and feedback while preserving the existing backend model and navigation behavior.

**Non-goals:**
- Do not add image thumbnails or new media storage requirements.
- Do not change feed ordering or event eligibility rules.
- Do not introduce comments, reposts, or new backend endpoints.

## Product direction

- The feed should feel like a stream of friend updates, not a dashboard of journey records.
- Each card should read as a single social event with a clear actor and action.
- Social proof should be visible, but still lightweight enough to match the current app scope.
- The redesign should stay compatible with the existing `journey`, `memory`, and `city` event model.

## Chosen approach

Use a "dynamic stream" card structure:

- Header: avatar, display name, recency
- Body: one primary social sentence
- Secondary context: city or supporting detail in smaller type
- Footer: lightweight engagement row with likes and event-specific metadata

This keeps the current data model intact while materially changing the reading experience.

## Alternatives considered

### A. Light social polish

Keep the current layout and mostly rewrite the copy. This is lower risk, but it would still feel like an activity card with minor cosmetics.

### B. Dynamic stream re-layout

Recompose cards around people, actions, and engagement while keeping the same event set and navigation. This gives a clearly social result without needing images or backend changes.

**Chosen because:** it is the strongest visual/product shift available within the current architecture.

### C. High-experiment social feed

Introduce large color blocks, bigger avatar framing, and more radical card differentiation. This could be memorable, but it risks drifting away from the existing StreetStamps visual language.

## Card behavior

### Shared card structure

- Display name becomes the strongest text in the header.
- Timestamp stays top-right and remains easy to scan.
- The main sentence becomes the primary content, replacing the current "title then location" emphasis.
- The city line moves to a secondary support role instead of functioning like a second title.
- Likes are presented as social response, not a utility chip.

### Event-specific presentation

**Journey**
- Primary sentence should feel like a completed update, such as "completed a journey" or a custom journey-title-driven action sentence.
- Distance and duration move into a quieter supporting row.

**Memory**
- Primary sentence should feel like a share/update, such as "added new memories".
- The memory/photo count becomes a visible piece of support context to imply content richness even without images.

**City**
- Primary sentence should feel celebratory, such as "unlocked a new city".
- The city name should be visually emphasized within the event body to create a milestone feel.

## Copy direction

- Prefer social verb phrases over noun labels.
- Sentences should be understandable when skimmed in isolation.
- The first line should always communicate: who, what, and optionally where.
- Badge labels should either be demoted or removed when they duplicate the social sentence.

Examples:

- "`DisplayName` completed a journey"
- "`DisplayName` added 3 new memories"
- "`DisplayName` unlocked a new city"

The actual implementation can still use localized fragments rather than hard-coded English sentences, but the copy should follow this pattern.

## Social signal upgrades

- Likes remain the primary engagement control.
- The like row should visually read as "people reacted to this" rather than "here is a button."
- Current-user posts should continue to support the "show likers" mode instead of self-like toggling.
- If a card has zero likes, the affordance should still feel tappable and socially meaningful.

## Interaction and state

- Keep the current refresh prompt model that detects unseen events and lets the user choose when to refresh.
- Keep the current scroll-restore behavior when navigating into and back from a feed item.
- Keep the current navigation policy for self-profile versus friend-profile and self-journey versus friend-journey.

## Implementation shape

- Add a feed presentation helper dedicated to social-dynamic copy and card styling decisions.
- Rework `FriendActivityCard` to prioritize social sentence composition and a more feed-like footer.
- Keep `buildFeedEvents(...)` as the source of normalized event data, but allow it to pass richer presentation fields needed by the new card.

## Testing approach

- Add focused unit tests for the new social sentence helper.
- Extend source-parity/style-level tests only where they prove key structural changes.
- Preserve existing tests for refresh prompt, like action policy, and scroll restoration.

## Success criteria

- The feed reads like a stream of friend updates instead of a journey ledger.
- Users can skim actor, action, and recency in under a second per card.
- `city`, `memory`, and `journey` cards feel related but distinct.
- No regression to refresh stability, like interactions, or navigation return position.
