# Postcard Inbox Self Reaction Design

## Goal

Make each received postcard show the current user's own reaction and comment beneath the card, using the same visual treatment already used for sent postcards.

## Current State

- `PostcardInboxView` renders a single `reaction` block beneath postcard cards.
- `BackendPostcardMessageDTO` currently carries one `reaction` field with no sender-role distinction.
- Sent and received boxes both map that same field through `PostcardInboxPresentation.cardReaction`.

## Desired Behavior

- Sent box continues to show the recipient's reaction/comment to postcards I sent.
- Received box shows my own reaction/comment to postcards I received.
- If both emoji and text comment exist, show both.
- If only one exists, show only that part.
- If neither exists, render no reaction block.

## Recommended Approach

Add explicit role-based reaction fields to the postcard message model:

- `myReaction`: the current user's reaction/comment on this postcard
- `peerReaction`: the other participant's reaction/comment on this postcard

Then map the card footer by box:

- `.sent` -> `peerReaction`
- `.received` -> `myReaction`

## Why This Approach

- Avoids ambiguous interpretation of a single `reaction` field.
- Keeps rendering logic simple and stable.
- Leaves room for future UI that shows both sides if needed.

## UI Rules

- Reuse the existing footer layout in `PostcardCardRow`.
- Preserve ordering: emoji first, then comment bubble.
- Do not introduce new controls or extra labels in the footer.
- The received-box composer controls stay as they are; this change only affects which stored reaction data is rendered underneath.

## Error Handling

- If backend payloads only contain the legacy `reaction` field, decode it as a fallback so existing data still renders.
- Prefer explicit role-based fields whenever present.

## Testing

- Add presentation tests to verify sent uses `peerReaction` and received uses `myReaction`.
- Add decode tests to verify new fields decode correctly and legacy `reaction` still works as fallback.
