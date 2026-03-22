# Save Journey Friends Visibility Design

**Goal:** Tighten the save-journey flow so switching to friends visibility is only allowed for signed-in users whose journey is at least 2km or already has memories, and extend the overall-memory input with the same photo capture/library affordances as the memory editor.

## Scope

- Validate the `friendsOnly` visibility option inside the save-journey sheet before save.
- Keep the current visibility when validation fails and surface a clear user-facing reason.
- Widen the save button in the save-journey sheet.
- Add camera and photo-library actions to the overall-memory section with the same icons and a 3-photo cap.
- Persist the overall-memory photos on `JourneyRoute` so the save flow is not transient.

## Design

- Move friends-visibility gating into `JourneyVisibilityPolicy` and return a structured result with a denial reason instead of a bare boolean.
- Reuse the existing `SystemCameraPicker`, `PhotoLibraryPicker`, `PhotoThumb`, and `PhotoStore` patterns from `MemoryEditorSheet` rather than creating a second media path.
- Store overall-memory photos in a new `JourneyRoute.overallMemoryImagePaths` array with Codable support and merge behavior.
- Add dedicated localized strings for the two denial reasons so the save sheet can explain exactly why the toggle was blocked.

## Validation

- Unit test the visibility-policy result for login and journey-eligibility scenarios.
- Unit test `JourneyRoute` Codable round-trip for overall-memory photos.
- Run the targeted XCTest suite covering the new tests and localization coverage.
