# Six Equipment Assets Design

**Goal:** Import the 6 provided avatar equipment images into the existing equipment area and append them to the matching asset/catalog sequences without changing the current equipment category structure.

**Design:**
- Keep the current data-driven equipment architecture: `StreetStamps/AvatarCatalog.json` remains the source of truth for the equipment UI, and `StreetStamps/Assets.xcassets/人物装备/` stores the rendered images.
- Map the provided files into the existing categories only:
  - `front_ac.png` -> `accessory` as `front_ac012`
  - `front_ac1.png` -> `accessory` as `front_ac013`
  - `front_pat005.png`, `front_pat006.png`, `front_pat007.png` -> `pat`
  - `front_suit.png` -> `suit` as `front_suit010`
- Follow the user-approved numbering rule: continue appending from the current highest asset number instead of filling missing gaps such as `front_ac006`.
- Update both the bundled JSON catalog and the Swift fallback catalog so the equipment area still works even if JSON loading fails.

**Testing:**
- Extend the equipment catalog tests to assert the newly imported accessory, pat, and suit assets appear in the expected categories.
- Run the targeted `EquipmentCatalogSplitTests` suite before and after implementation.
