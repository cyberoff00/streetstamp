# Equipment Shoes Design

**Goal:** Import all new `front_*` avatar assets from the provided folder into the existing equipment catalog, grouped into their matching equipment zones, and add a new `shoes` zone as the last category in the equipment UI.

**Design:**
- Extend the avatar catalog with the newly delivered assets for `accessory`, `expression`, `glass`, `hair`, `hat`, `suit`, `under`, and `upper`.
- Add a new `shoes` category with its own catalog entries, selection key, and rendered preview layer so shoes can be equipped instead of only listed.
- Keep the current equipment behavior model: `shoes` behaves like a single-select wearable category similar to `under`, while `accessory` and `pat` keep their existing multi-select/special handling.
- Show the new category as the last icon in the equipment category row and provide a dedicated localized label.

**Testing:**
- Add catalog tests that prove the new front assets land in the expected categories.
- Add loadout codable coverage for `shoesId`.
- Run targeted equipment tests after the asset catalog and rendering changes land.
