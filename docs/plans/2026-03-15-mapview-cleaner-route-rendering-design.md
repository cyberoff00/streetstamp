# MapView Cleaner Route Rendering Design

**Problem:** The active journey route in `MapView` reads heavier than the cleaner route treatments used in polished map and fitness apps. The line also does not visually slim down while zooming because the overlay renderer widths are only decided when overlays are created.

**Goals:**
- Keep the current route color palette.
- Make the route read as cleaner and more refined without becoming hairline-thin.
- Preserve a visible outline around the route so it feels polished and legible.
- Make zoom changes visibly affect route thickness.

**Design:**
- Keep the existing segment pipeline and color source unchanged so route meaning and theme consistency stay intact.
- Replace the current heavy three-layer feel with a cleaner but still outlined treatment: a medium-thin core line, a close-fitting low-alpha outline, and only a very weak frequency layer.
- Avoid the previous over-correction toward hairline strokes. The core should still feel present at default zoom, more like polished consumer map apps than debug geometry.
- Recompute or refresh overlay renderers when the map camera altitude changes enough to warrant a width update, so zooming out makes the line feel slimmer while preserving the outline relationship.

**Testing:**
- Add focused tests for the line-width policy so the rendering math trends thinner as altitude increases while keeping the outline slightly wider than the core.
- Manually verify on device or simulator that pinch zoom updates route thickness and the route still feels outlined rather than flat or overly thin.
