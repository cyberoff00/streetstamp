## Goal

Make city-facing UI obey the device language consistently:

- Chinese device language: city cards, deep-view title, and level labels display in Chinese
- English device language: the same UI displays in English
- Avoid mixed-language combinations caused by stale cached display strings from a different locale

## Design

Use the current locale as the only display truth for city names.

1. `CityPlacemarkResolver.displayTitle(...)` should only trust persisted localized titles when they look compatible with the current locale.
2. Stored `reservedAvailableLevelNames` should only be used for display if the whole label set looks compatible with the current locale.
3. If stored level labels are incompatible, `CityDeepView` should treat them as unavailable and refresh from `ReverseGeocodeService.localizedHierarchy(...)`, which is already locale-aware.

## Scope

- Do not change canonical city keys or reassignment mechanics
- Do not add per-field defensive exceptions
- Keep the fix centered in resolver/display selection logic and deep-view label loading

## Verification

- Add unit tests for locale-mismatched cached titles
- Add unit tests for rejecting stale stored level labels from the wrong locale
- Run focused `CityDisplayNameResolverTests`
