# Map Style Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `MapView` layer picker that lets users switch the live map between `Default` and `Blueprint`, with the choice persisted globally for later reuse by other map surfaces.

**Architecture:** Introduce a new shared map style preset/config layer that is independent from page-specific UI, then wire `MapView` to both present the picker and consume the resolved rendering config. Keep phase one scoped to `MapView`, but shape the persistence and config APIs so `CityDeepView`, `JourneyRouteDetailView`, and `LifelogView` can adopt them later without changing the data model.

**Tech Stack:** SwiftUI, UIKit `MKMapView`, `UserDefaults`, existing route renderer and map overlay pipeline

---

### Task 1: Define Shared Map Style Presets

**Files:**
- Modify: `StreetStamps/ThemeManager.swift`
- Test: manual verification in app

**Step 1: Add preset enum**

Add a new enum alongside the existing map appearance helpers:

```swift
enum MapStylePreset: String, CaseIterable, Identifiable {
    case `default`
    case blueprint

    var id: String { rawValue }
}
```

**Step 2: Add config model**

Add a lightweight config type that contains only phase-one tokens:

```swift
struct MapStyleConfig {
    let interfaceStyle: UIUserInterfaceStyle
    let mapType: MKMapType
    let showsBuildings: Bool
    let showsPointsOfInterest: Bool
    let showsTraffic: Bool
    let routeBaseColor: UIColor
    let routeGlowColor: UIColor
    let routeHighlightColor: UIColor
    let usesMutedEmphasis: Bool
}
```

**Step 3: Add settings namespace**

Create shared storage and resolution helpers:

```swift
enum MapStyleSettings {
    static let presetStorageKey = "streetstamps.map.style.preset"

    static var currentPreset: MapStylePreset { ... }
    static func apply(_ preset: MapStylePreset) { ... }
    static func config(for preset: MapStylePreset) -> MapStyleConfig { ... }
    static var currentConfig: MapStyleConfig { ... }
}
```

`default` should resolve close to the current map behavior. `blueprint` should resolve to a low-noise map with blueprint route colors.

**Step 4: Preserve compatibility**

Keep the existing `MapAppearanceSettings` APIs intact for now so non-`MapView` screens do not regress during phase one.

**Step 5: Build the app**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`

Expected: build succeeds with the new preset/config types available.

### Task 2: Add MapView Layer Picker UI

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: manual verification in app

**Step 1: Locate the existing right-side floating controls**

Read the action cluster code in `MapView.swift` and identify the container that already renders the floating action buttons.

**Step 2: Add local picker state**

Add view state for:

```swift
@State private var isMapStylePanelVisible = false
@AppStorage(MapStyleSettings.presetStorageKey) private var mapStylePresetRaw = MapStyleSettings.currentPreset.rawValue
```

If direct `@AppStorage` on the new key becomes awkward, use a computed preset derived from the stored raw value.

**Step 3: Add a new floating layer button**

Add a blue floating button in the same visual family as the other right-side actions. The icon should communicate map layers, such as `square.3.layers.3d` or a similar system symbol already used by the app.

**Step 4: Add a compact picker panel**

Render a small floating panel next to the button when visible. Each option should include:

- preset name
- short subtitle if space allows
- tiny visual preview tile
- selected state

**Step 5: Apply changes immediately**

On tap of an option:

- update the stored preset
- close the panel if that feels better in testing
- allow `MapView` to refresh immediately

**Step 6: Build and smoke test**

Run the same `xcodebuild ... build` command.

Expected: build succeeds and the `MapView` UI contains the layer entry point.

### Task 3: Pipe Shared Config Into JourneyMKMapView

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: manual verification in app

**Step 1: Thread preset/config through MapView**

At the SwiftUI `MapView` layer, resolve:

```swift
let mapStylePreset = MapStylePreset(rawValue: mapStylePresetRaw) ?? .default
let mapStyleConfig = MapStyleSettings.config(for: mapStylePreset)
```

Pass the resolved config into `JourneyMKMapView`.

**Step 2: Update JourneyMKMapView API**

Add a new input:

```swift
let mapStyleConfig: MapStyleConfig
let mapStylePreset: MapStylePreset
```

Pass both if preset identity is useful for branch decisions; otherwise pass only the config.

**Step 3: Replace direct appearance usage where needed**

Inside `JourneyMKMapView`, use `mapStyleConfig` instead of only `MapAppearanceSettings` for:

- `overrideUserInterfaceStyle`
- `mapType`
- `showsTraffic`
- `pointOfInterestFilter`
- any building visibility supported by this surface

**Step 4: Keep follow/camera logic untouched**

Do not mix map style work with gesture handling, follow-user state, or camera command logic.

**Step 5: Build and verify**

Run the same `xcodebuild ... build` command.

Expected: build succeeds and the map still behaves the same under the `Default` preset.

### Task 4: Implement Blueprint Route Tokens

**Files:**
- Modify: `StreetStamps/ThemeManager.swift`
- Modify: `StreetStamps/MapView.swift`
- Test: manual verification in app

**Step 1: Define blueprint palette**

Pick concrete blueprint colors in `MapStyleSettings.config(for:)`, for example:

```swift
routeBaseColor: UIColor(red: 0.22, green: 0.67, blue: 1.00, alpha: 1.0)
routeGlowColor: UIColor(red: 0.52, green: 0.84, blue: 1.00, alpha: 1.0)
routeHighlightColor: UIColor.white.withAlphaComponent(0.55)
```

Tune the exact values during visual testing.

**Step 2: Update route renderer to read from config**

Find the route overlay rendering logic in `JourneyMKMapView.Coordinator` and replace references to the old dark/light route colors with `mapStyleConfig`.

**Step 3: Keep line layering structure**

Do not redesign the renderer. Reuse the current glow / main / highlight layered approach and swap token values only.

**Step 4: Verify dashed segments still read well**

Make sure gaps and dashed segments remain legible against the blueprint base map.

**Step 5: Build and visually compare**

Run the same `xcodebuild ... build` command.

Expected: route overlays remain correct in both presets, with `Blueprint` visibly distinct from `Default`.

### Task 5: Tune Marker and Annotation Readability

**Files:**
- Modify: `StreetStamps/MapView.swift`
- Test: manual verification in app

**Step 1: Inspect robot and memory marker contrast**

Check the robot marker, memory groups, and any active route-tail visuals against the blueprint base.

**Step 2: Apply minimal compatibility tweaks**

Only if necessary, adjust:

- annotation background contrast
- border or shadow intensity
- small accent colors that disappear on the blueprint base

Do not redesign the marker visuals in phase one.

**Step 3: Rebuild**

Run the same `xcodebuild ... build` command.

Expected: annotations stay readable in both presets.

### Task 6: Manual Verification and Cleanup

**Files:**
- Modify: `StreetStamps/MapView.swift` if cleanup is needed
- Test: manual verification in app

**Step 1: Verify live switching**

Open `MapView` and confirm:

- layer button appears
- picker opens and closes
- selecting `Default` applies current behavior
- selecting `Blueprint` updates the live map immediately

**Step 2: Verify persistence**

Terminate and relaunch the app, then return to `MapView`.

Expected: the previously selected preset is still active.

**Step 3: Verify route/map behavior**

Check:

- current tracking map
- existing journey map
- follow-user behavior
- camera changes
- memory selection

Expected: no regressions in core map interaction.

**Step 4: Final cleanup**

Remove temporary debug logging introduced for development if any was added.

**Step 5: Commit**

```bash
git add StreetStamps/ThemeManager.swift StreetStamps/MapView.swift
git commit -m "feat: add map style layer picker"
```
