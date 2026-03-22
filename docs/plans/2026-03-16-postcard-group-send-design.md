# Postcard Group Send Design

Date: 2026-03-16
Status: Approved in chat

## Goal

Extend the existing postcard compose flow so users can send one postcard to up to three friends at once. The inbox/sent page gets a new envelope icon entry for free-form compose, while the existing friend-profile entry remains available and can be upgraded from 1:1 to group send inside the same composer.

## Entry Points

- Friend profile entry:
  - Opens the existing postcard composer.
  - Prefills the selected friend as the first recipient.
  - Allows adding up to two more recipients.
- Postcard inbox/sent entry:
  - Adds a top-right envelope icon on the postcard page header.
  - Opens the same postcard composer with no prefilled recipient.
  - The top module starts in an "Add recipients" state.

## Compose UX

- Reuse the existing `PostcardComposerView` layout and keep city, photo, message, preview, and send steps unchanged below the recipient module.
- Replace the single-recipient card with a recipient management section at the top.
- Support 1 to 3 recipients.
- Selecting recipients is done from the friend list.
- The picker excludes the current user and already selected friends.
- Users can remove recipients before sending.
- Preview remains a single postcard preview, but the recipient label shows multiple names.

## Data Model

Treat one group send as one logical draft/batch.

- Introduce a local recipient model for postcard drafts and previews.
- Store one draft with shared city/photo/message data plus a recipient list.
- Generate a shared `groupSendID` for the batch.
- If the backend only supports single-recipient send today, the client sends one request per recipient while attaching the shared batch identifier.

This keeps the UI aligned with user intent: "I sent one postcard to several people."

## Sent Box Rendering

- A group send appears as one card in Sent.
- The card content uses the shared postcard payload: city, image, message, sent date.
- The recipient label renders multiple display names on one line, truncated if necessary.
- Sent items are grouped by `groupSendID`.
- 1:1 sends also participate in the same grouping model, with a single recipient.

## Send Status

Status is presented per batch, not per individual message.

- All successful: normal sent card.
- Partially successful: show a compact partial-success badge such as `2/3 sent`.
- All failed: show failed state and a retry action.

Retry should re-attempt only the unsent recipients while keeping the batch card stable in Sent.

## Received Box Rules

- No aggregation is needed in Received.
- Each recipient sees only their own postcard as a normal received item.
- Group-send logic mainly affects compose, local draft state, batch sending, and the sender's Sent view.

## Implementation Scope

- Add the top-right envelope action in postcard inbox/sent.
- Expand the composer to manage multiple recipients.
- Expand postcard draft and request models to carry recipient lists and group-send metadata.
- Teach `PostcardCenter` to send a batch and track per-recipient outcomes.
- Aggregate sent records into one visual row for the sender.
- Keep current 1:1 flows working without behavioral regressions.

## Testing Focus

- Composer presentation with empty and prefilled recipient states.
- Recipient selection limit of three.
- Draft persistence for group recipients.
- Batch status presentation for full success, partial success, and failure.
- Sent-box aggregation of multiple backend records into one card.
