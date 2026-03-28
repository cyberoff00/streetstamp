# Map Style Layer Design

## Goal

Add a first-pass map style selector to `MapView` so users can switch the live map between:

- `Default`
- `Blueprint`

The selector should live in the right-side floating controls, behave like a map layer picker, and persist the chosen style globally for future map surfaces.

This phase does not include a full settings-based map editor. It creates the shared style foundation that the future editor will build on.

## Scope

### In scope

- Add a blue layer button to `MapView`
- Show a compact style picker panel from that button
- Support two presets: `Default` and `Blueprint`
- Persist the selected preset in shared app state
- Apply the selected preset to the live `MapView`
- Keep existing route tracking, follow behavior, and annotations working

### Out of scope

- Globe / Mapbox surface updates
- Settings editor UI
- Arbitrary user-defined color editing
- ASCII / retro rendering
- Full rollout to `CityDeepView`, `JourneyRouteDetailView`, and `LifelogView`

## Product Intent

The feature should feel meaningfully different from a simple dark/light toggle. The first advanced style should make the map feel like a designed experience rather than a default system map.

`Blueprint` should aim for:

- cleaner base map
- reduced visual noise
- stronger route emphasis
- technical / diagram-like visual language

## UX

### Entry point

Add a new blue floating control on the right side of `MapView`, aligned with the existing action cluster.

### Interaction

- Tap opens a compact floating panel
- Panel shows two selectable options with a small visual preview tile
- Selecting an option applies it immediately
- Selected option is visibly highlighted
- Choice is saved and restored on next app launch

### First-pass options

- `Default`: current map behavior
- `Blueprint`: cleaner base map and blueprint-style route rendering

## Architecture

### New shared types

Add a shared preset model instead of extending the existing dark/light-only enum directly.

Suggested structure:

- `MapStylePreset`
- `MapStyleConfig`
- `MapStyleSettings`

### Responsibilities

`MapStylePreset`

- defines supported named presets
- first phase contains `default` and `blueprint`

`MapStyleConfig`

- defines concrete rendering tokens consumed by map surfaces
- should include only fields needed now, but be shaped for future editor growth

Suggested first fields:

- `interfaceStyle`
- `mapType`
- `showsBuildings`
- `showsPointsOfInterest`
- `showsTraffic`
- `usesMutedEmphasis`
- `routeBaseColor`
- `routeGlowColor`
- `routeHighlightColor`

`MapStyleSettings`

- stores selected preset in `UserDefaults`
- exposes current preset
- resolves preset into `MapStyleConfig`

This keeps page code independent from preset naming and makes later editor work additive instead of invasive.

## MapView Integration

### UI layer

Add:

- a right-side layer button
- a local disclosure state for panel visibility
- a compact panel view for preset selection

The panel should be owned by `MapView` UI state, while the selected preset should be global.

### Rendering layer

Update `JourneyMKMapView` to consume `MapStyleConfig` instead of relying only on the existing dark/light appearance helpers.

`Default` should map to current behavior.

`Blueprint` should update:

- map base type / interface style
- POI visibility
- traffic visibility
- buildings visibility if supported on the current surface
- route line palette and highlight treatment

## Blueprint Visual Rules

The first version should stay feasible within the current `MapKit` stack.

### Base map

- use a clean, low-noise map base
- suppress non-essential map detail
- avoid looking like a simple recolor

### Route

- make the route the focal layer
- use a blueprint-like accent such as blue / cyan ink
- keep the existing layered route renderer structure, but swap tokens for blueprint-specific values

### Annotations

Do not redesign all annotations in phase one.

Only do lightweight compatibility adjustments where needed so robot and memory markers still read cleanly against the new base.

## Persistence

Store the selected preset globally in `UserDefaults`.

Even though phase one only exposes the picker from `MapView`, the state should be shared so future map pages can adopt it without redesigning persistence.

## Rollout Plan

### Phase 1

- shared preset/config model
- `MapView` layer button and picker
- `Default` and `Blueprint`
- live `MapView` rendering support

### Phase 2

- apply shared presets to `CityDeepView`
- apply shared presets to `JourneyRouteDetailView`
- apply shared presets to `LifelogView`

### Phase 3

- settings-based map editor
- more advanced presets
- possible experimental styles such as retro / ASCII

## Risks

### Visual risk

If `Blueprint` only changes a few colors, users will not feel enough value. The preset must create obvious contrast from `Default`.

### Technical risk

`MapKit` has limited control over true base-map styling. The first version should focus on what is feasible now:

- system map selection
- overlay tokens
- feature visibility toggles

### Regression risk

Changes must not break:

- follow user behavior
- route overlay updates
- memory selection
- camera transitions

## Verification

Manual verification for phase one should confirm:

- layer button appears on `MapView`
- panel opens and closes reliably
- switching between `Default` and `Blueprint` changes the live map immediately
- selected style persists after app relaunch
- route rendering remains correct while tracking and while viewing existing journeys
- annotations remain legible in both presets

## Recommendation

Implement phase one using a shared preset/config layer rather than adding more branches to the current `MapAppearanceSettings`.

This keeps the first release small while giving the later settings editor a clean foundation.
