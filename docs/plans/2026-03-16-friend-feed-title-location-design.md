# Friend Feed Title And Location Design

**Problem:** The friend feed currently mixes journey titles into the location line, and its event title logic cannot prioritize a custom journey title over the generic event copy.

**Validated rules:**
- The feed card keeps three pieces of information: friend nickname, event title, and city location.
- The city location line must always come from the existing `cityID` resolution path.
- If the city cannot be resolved from `cityID`, the location line should be hidden instead of falling back to the journey title.
- The event title should prioritize a true custom journey title for `journey` and `memory` events.
- If a journey does not have a true custom title, the event title should fall back to the existing generic event copy:
  - `visited a city`
  - `completed a journey`
  - `added memory`
- `city` events keep their current city-based title logic and do not use the custom-title override.

**Design:**
- Keep `resolvedFriendCityID(...)` unchanged so unlock-city detection still works exactly as it does now.
- Split feed presentation rules into two concerns:
  - `FriendFeedLogic.eventTitle(...)` decides the headline text.
  - A location helper returns a city-only display string for the location row.
- Add a small helper that treats a journey title as custom only when it is non-empty and not equivalent to the resolved city title.
- Use that helper only for `journey` and `memory` cards.

**Testing approach:**
- Extend `FriendFeedLogicTests` to cover:
  - custom-title override for `journey`
  - custom-title override for `memory`
  - generic fallback when title matches the city name
  - location suppression when no city can be resolved
