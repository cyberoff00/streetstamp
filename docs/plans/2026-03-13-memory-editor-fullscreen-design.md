# Memory Editor Fullscreen Design

**Goal:** Make the memory editor feel meaningfully expanded in full-screen mode by increasing the notes area height and removing the heavy boxed text-field treatment, while keeping the compact sheet editor familiar.

**Context:** The current sheet and full-screen experiences both reuse the same nested card layout. In practice, the full-screen editor still looks like a small modal scaled up because the notes area keeps the same white rounded container and the text editor height remains capped at a compact size.

## Decision

Use a split treatment:

- Keep `MemoryEditorSheet` as the compact floating card editor.
- Restyle `MemoryEditorPage` as a page-like editor with a lighter content surface.
- Increase the visible notes area height in full-screen mode so it uses more vertical space before scrolling.

## Layout Changes

- Preserve the existing full-screen header and footer actions.
- Remove the strong inner white rounded card from the full-screen notes area.
- Reduce the sense of a framed text box by using lighter spacing and a softer background treatment.
- Keep photos below the notes area, but allow the notes editor to own more of the page.

## Behavior

- Do not change draft persistence, save/delete flows, photo handling, or keyboard focus behavior.
- Do not change the compact sheet interaction model beyond any small visual adjustments needed to stay coherent with the full-screen page.

## Success Criteria

- Entering full-screen clearly gives the notes editor more height than the compact sheet.
- The full-screen editor no longer reads as a heavy nested modal-within-a-modal.
- Existing save, delete, camera, library, and draft-resume behaviors continue to work unchanged.
