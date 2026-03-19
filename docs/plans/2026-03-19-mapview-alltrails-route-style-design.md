# MapView AllTrails Route Style Design

**Goal:** Upgrade the live tracking `MapView` to feel closer to AllTrails by adding a stronger outlined route treatment and an in-map 3-mode basemap switcher, without expanding the first pass to every other map surface.

## Current State

The live tracking map in [`StreetStamps/MapView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/MapView.swift) already renders layered polylines through `MultiPolylineRenderer`, and map appearance is centralized in [`StreetStamps/ThemeManager.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/ThemeManager.swift) via `MapAppearanceSettings`.

Today that structure is close to what we need, but two things are missing:

- the route reads more like a soft glow than a clear AllTrails-style outlined trail
- map appearance only supports a combined dark/light concept, not an in-map 3-way surface mode switch

## Problem

On the live tracking screen, the route needs to remain readable across standard, muted, and satellite basemaps. Right now the visual system does not separate these concerns cleanly:

- basemap choice and UI dark/light treatment are coupled too tightly
- route styling is not tuned differently for dense vector maps versus satellite imagery
- users cannot change map rendering mode directly inside `MapView`

This makes the tracking screen feel less intentional than outdoor fitness apps where the route is always legible and the basemap can be switched in place.

## Recommended Approach

Split map presentation into two independent dimensions:

1. `MapSurfaceMode`
   Controls the basemap content: `standard`, `outdoor`, `satellite`
2. Existing dark/light appearance
   Continues to control overlay UI styling and route token fine-tuning

Then upgrade the route renderer in `MapView` from a softer 3-layer treatment to a clearer AllTrails-style stack:

1. `outline`
2. `glow`
3. `core`
4. emphasized `live tail`

This keeps the current renderer architecture intact while making the route much more readable on every basemap.

## Design

### 1. Keep dark/light and map mode separate

Do not fold surface mode into the existing dark/light enum. That would create a brittle combined state such as `darkSatellite` or `lightMuted`, which scales poorly.

Instead:

- keep the current light/dark appearance concept for UI chrome
- add a separate `MapSurfaceMode` preference
- compute route palette tokens from both values together

That gives us clean responsibility boundaries:

- map mode picks `MKMapType`
- UI appearance picks interface style
- route tokens adapt to both

### 2. Add three live map surface modes

The first pass should support:

- `standard` -> `MKMapType.standard`
- `outdoor` -> `MKMapType.mutedStandard`
- `satellite` -> `MKMapType.hybrid`

`outdoor` should become the default because it best supports the intended AllTrails-like route emphasis.

### 3. Upgrade the route stack to a classic outlined trail

The live route should render with explicit layer meaning rather than a generic glow:

- `outline`: strongest separation layer, especially important on satellite
- `glow`: colored softness around the route
- `core`: the sharp, saturated route centerline
- `live tail`: the most recent segment rendered brighter and slightly more prominent

The renderer should still respect existing dashed-gap semantics. Dashed segments should keep the same structural meaning, but use the new outlined stack so they remain readable over all basemaps.

### 4. Tune tokens by surface mode

Each surface mode should provide a different route token set.

#### `standard`

- balanced outline strength
- clear core stroke
- moderate glow

#### `outdoor`

- most attractive default look
- slightly softer outline than satellite
- strongest color richness

#### `satellite`

- strongest outline contrast
- slightly reduced glow bloom
- highest emphasis on crisp legibility over imagery

Dark/light appearance should still be allowed to nudge alpha and contrast, but surface mode is the primary driver.

### 5. Add a MapView-local surface mode switcher

The 3-way mode picker should live directly on the `MapView` screen as a lightweight floating control near the existing map tools area.

Interaction rules:

- switching mode updates the map immediately
- the choice persists with `UserDefaults` / `@AppStorage`
- no modal sheet or trip to Settings is required

Recommended labels:

- `Std`
- `Outdoor`
- `Sat`

### 6. Limit first-pass scope to the live tracking map

This change should modify only:

- [`StreetStamps/ThemeManager.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/ThemeManager.swift)
- [`StreetStamps/MapView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/MapView.swift)

Do not update in this pass:

- [`StreetStamps/JourneyRouteDetailView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/JourneyRouteDetailView.swift)
- [`StreetStamps/CityDeepView.swift`](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/CityDeepView.swift)
- sharing cards, thumbnails, or snapshot renderers

Once the live map tokens feel right, the same palette model can be propagated elsewhere.

## Testing Strategy

Verify:

- `MapView` surface mode changes immediately update the basemap
- the selected mode persists across relaunches
- route outline remains legible on `standard`, `outdoor`, and `satellite`
- the live tail remains visually above the main route after incremental overlay updates
- dashed segments stay readable and distinct after the renderer refactor

## Risks

- If outline alpha is too weak, the route will still disappear into satellite imagery.
- If outline alpha is too strong, the route may look heavy or cartoonish on standard maps.
- If dark/light and surface mode responsibilities are not separated cleanly, future map surfaces will become harder to maintain.

The implementation should therefore keep configuration centralized and bias toward tokenized styling instead of inlined renderer constants.
