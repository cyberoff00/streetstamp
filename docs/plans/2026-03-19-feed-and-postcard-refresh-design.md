# Feed And Postcard Refresh Design

**Date:** 2026-03-19

## Goal

Unify `FriendsHubView` feed and `PostcardInboxView` refresh behavior so both surfaces feel stable, preserve reading position, and only update visible content when the user explicitly asks for it.

## Problem

The current frontend mixes multiple refresh triggers:

- `PostcardInboxView` performs automatic polling while the user is reading.
- Feed-related screens already lean toward a softer "new content available" prompt, but the overall refresh model is still inconsistent.
- Returning from background can cause data changes to land immediately in a visible list, which makes the UI feel unstable.

This is the opposite of the behavior used by mature social and messaging apps. Those apps usually separate:

- "there is something new"
- "replace what the user is currently looking at"

That separation is what prevents the feeling that content is moving underneath the user.

## Product Decision

Use the current feed prompt pattern as the shared interaction model.

- Keep the existing feed "new content available" style.
- Reuse that same top lightweight prompt pattern for `PostcardInboxView`.
- Do not auto-insert or auto-reorder visible rows while the user is on the page.
- Let the user decide when to refresh by:
  - pull to refresh
  - tapping the lightweight prompt
  - entering via a deep link or notification that targets a specific item

## User Experience Rules

### Feed

- Initial entry: perform one load.
- While visible: do not auto-refresh the visible list.
- New remote content discovered while visible: show the existing lightweight prompt instead of mutating the list.
- Pull to refresh: fetch and apply immediately.
- Tapping the existing prompt: fetch and apply immediately.
- Returning from background: run a lightweight check only, then show the prompt if there is new content.

### Postcard Inbox

- Initial entry: perform one load.
- While visible: no polling.
- Pull to refresh: fetch and apply immediately.
- Returning from background: run a lightweight check only, then show a feed-style lightweight prompt if new postcards are available.
- If the user opens the inbox from a postcard-related deep link or notification: allow a targeted refresh so routing remains reliable.
- If the user is composing or reading the inbox already: do not insert rows until the user refreshes or taps the prompt.

## Background And Foreground Rules

- Background stay shorter than 30 seconds: do nothing on foreground re-entry.
- Background stay 30 seconds or longer: allow one lightweight freshness check.
- Lightweight freshness checks must not replace visible lists.
- Background freshness checks should be throttled with a 5 minute cooldown.
- Prompt display should have a 90 second cooldown so repeated app switches do not spam the user.

## Freshness Model

Introduce a two-step refresh model on both surfaces.

### Step 1: Lightweight freshness check

Used for foreground re-entry or background-driven updates.

Expected output:

- whether new content exists
- the newest item identifier or timestamp
- optional count of unseen items

Expected behavior:

- update badge/red-dot/prompt state only
- do not replace the currently rendered array

### Step 2: User-applied refresh

Used for pull to refresh, prompt tap, or targeted routing.

Expected behavior:

- perform the full remote fetch
- replace local list state
- clear pending new-content prompt state

## Parameter Defaults

- Foreground re-entry threshold: `30s`
- Lightweight check cooldown: `5m`
- Prompt cooldown: `90s`
- Initial load mode: full fetch
- Pull to refresh mode: full fetch
- Prompt tap mode: full fetch
- Deep link / notification route mode: targeted fetch allowed

## Implementation Notes

### Friends feed

- Preserve the current prompt UI and wording.
- Refactor refresh code so "check for new feed content" is distinct from "apply feed refresh".
- Keep scroll position stable until the user accepts the refresh.

### Postcard inbox

- Remove the 8 second polling task.
- Add inbox-level pending freshness state:
  - `hasPendingInboxRefresh`
  - optional `pendingInboxNewCount`
- Add a top prompt matching the feed interaction model.
- Reuse the existing full refresh path for pull to refresh and prompt taps.

## Non-Goals

- No live-updating list while the user is staring at the page.
- No silent row insertion animation.
- No aggressive auto-refresh timer in foreground.
- No new modal or banner system beyond the existing feed-style prompt.

## Testing Strategy

- Verify first entry still loads content.
- Verify pull to refresh still works on both feed and inbox.
- Verify returning from background after 30 seconds does not reorder visible content.
- Verify new-content prompt appears instead of mutating the list.
- Verify tapping the prompt applies the refresh and clears prompt state.
- Verify postcard deep links still focus the target message reliably.

## Open Assumptions

- The existing feed prompt is acceptable as the visual pattern for inbox.
- Backend or existing stores can support a lightweight freshness signal using timestamps, ids, or unread counts without requiring a full visible-list rewrite.
