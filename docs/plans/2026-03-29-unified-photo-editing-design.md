# Unified Photo Editing Design

**Date:** 2026-03-29

## Goal

Replace the current fragmented image attach flow with a single, product-grade editing flow that is used everywhere the app captures or imports photos. Every newly captured or selected image should enter the editor before the host feature receives the final image.

## Problem Summary

The current app flow is inconsistent:

- `MemoryEditor` receives photos directly after capture or library selection.
- Some views persist images immediately with `PhotoStore.saveJPEG(...)`.
- The existing `PhotoCropRotateView.swift` file is not wired into the main flows.
- Text placement does not match the intended interaction. It prompts first and inserts in the center, instead of tapping a position on the image.
- Cropping is effectively driven by viewport state rather than an explicit crop mode.

This leads to a poor editing experience and inconsistent behavior across `MemoryEditor`, `JourneyMemoryNew`, `SharingCard`, and other image entry points.

## Product Requirements

### Universal Entry Rule

All new images must go through the same editor before being accepted by the host screen:

- Camera capture -> editor -> host feature
- Photo library selection -> editor queue -> host feature

This rule applies to every in-app feature that lets the user upload or capture a photo.

### Multi-Select Behavior

For photo library selection:

- The user selects all desired images first.
- After selection completes, the app opens an edit queue.
- The user edits images one by one in order.
- The host feature receives the final set only after the queue completes.

### Required Editing Tools

The first release only includes:

- Rotate
- Add text
- Crop

Anything else, such as filters, stickers, or aspect-ratio presets, is intentionally out of scope for the first pass.

## UX Design

### Queue-Level Flow

1. User enters camera or photo library.
2. Camera returns one image, or photo library returns an ordered image array.
3. The app creates an editing queue.
4. The editor opens on the first item.
5. For each image, the user may:
   - complete the edit
   - skip editing and keep the original
   - discard the image
6. After the last image is processed, the app returns the finalized image array to the originating screen.

### Editor Layout

The editor is a full-screen experience with three sections:

- Top bar
  - left: `Cancel`
  - center: queue progress such as `2/5`
  - right: `Skip` or `Done`, with the last item using `Done All`
- Canvas
  - large editable photo surface
  - supports pan/zoom while preserving tool behavior
- Bottom toolbar
  - `Rotate`
  - `Text`
  - `Crop`

This layout should visually align with the reference direction the user provided: a dedicated editing screen, not an attachment manager.

### Text Interaction

Text behavior must change from the current implementation:

1. User taps the `Text` tool.
2. The editor enters text-placement mode.
3. User taps any point on the image.
4. A text input starts at that position.
5. Confirming creates a text overlay at the tapped point.
6. Existing overlays can be:
   - dragged
   - selected
   - edited
   - deleted

Delete must be obvious and one step away after selecting a text overlay.

### Crop Interaction

Cropping must become an explicit mode:

- entering crop mode reveals a crop frame and dimmed outside area
- users can drag the frame and reposition/zoom the image behind it
- confirming applies the crop to the output image

The first version should support free cropping only. Fixed ratios can be added later without blocking this redesign.

## Technical Design

### New Shared Flow

Create a shared editing pipeline used by all feature surfaces:

1. media acquisition
2. edit queue orchestration
3. single-image editing
4. result handoff

### Shared Components

#### `UnifiedPhotoEditingFlow`

This is the public entry point used by feature screens. It should:

- accept a source result from camera or library
- normalize that result into an editing queue
- present the editor queue
- return the finalized images

#### `PhotoEditingQueueController`

This owns queue state:

- source items
- current index
- edited outputs
- skipped originals
- discarded items
- cancellation behavior

It is responsible for advancing to the next image and deciding when the whole flow is complete.

#### `UnifiedPhotoEditorViewController`

This is the reusable single-image editor. It should evolve from the current `PhotoEditViewController` in `PhotoCropRotateView.swift`, but with a cleaner state model and the required interaction changes.

#### `PhotoEditingResult`

This is the host-facing output model. Host views should receive finalized images or stored filenames only after editing completes. They should not know about queue internals or editor overlays.

## Integration Strategy

### First-Round Integration Targets

The first rollout should cover all currently identified custom image entry points:

- `StreetStamps/MapView.swift`
- `StreetStamps/JourneyMemoryNew.swift`
- `StreetStamps/SharingCard.swift`
- `StreetStamps/PostcardComposerView.swift`

### Host Responsibility After Adoption

Once a host adopts the shared flow, it should only:

- trigger camera or library entry
- wait for finalized images
- store or assign results for its own business logic

It should not:

- save raw images before editing
- implement its own edit state
- diverge from the shared toolbar or screen structure

## Data and Persistence Rules

- Newly edited images are persisted only after the user completes editing for that item.
- Queue cancellation should drop all newly selected items from that session.
- Existing feature models continue to store finalized image output, not editing metadata.
- The first version does not need a persistent project-style editing document for text layers or crop settings.

This keeps the implementation compatible with the current `PhotoStore`-based persistence model.

## Error Handling

- If editor presentation fails for an image, the flow should surface a recoverable error and let the user discard that item.
- If saving the finalized image fails, the host flow should stop and present a save failure message instead of silently losing the item.
- Cancelling the queue should require confirmation when there are uncommitted selected items.

## Testing Strategy

Add focused tests around the shared orchestration instead of trying to fully snapshot the editor UI:

- queue progression from first item to last item
- completion behavior for edited, skipped, and discarded items
- final host callback receives only retained items
- last item changes CTA semantics from `Done` to `Done All`
- cancellation drops the temporary queue

UI-level manual verification is also required for:

- tap-to-place text
- text delete behavior
- crop mode
- rotation interaction
- multi-image queue progression

## Non-Goals

These are explicitly excluded from the first implementation:

- filters
- stickers or emoji overlays
- text style palettes
- persistent non-destructive edit history across launches
- arbitrary reordering of selected images inside the queue

## Recommendation

Use the existing UIKit editor foundation in `PhotoCropRotateView.swift` as the starting point, but refactor it into a proper shared editor and queue flow. This gives the fastest path to a polished result while preserving compatibility with the current media capture and storage stack.
