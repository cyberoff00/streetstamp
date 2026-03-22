# Journey List Breathing Room Design

**Problem:** The journey list feels visually crowded, route thumbnails blend together, and some thumbnails frame only a small fragment of the route instead of the full journey.

**Goals:**
- Separate adjacent journey cards with more visual breathing room.
- Make map thumbnails feel quieter by muting the base map.
- Ensure each thumbnail shows the full journey route without excessive empty map space.

**Design:**
- Increase list spacing and card internal padding so each journey reads as a distinct section.
- Switch the thumbnail presentation away from cropping behavior. The rendered snapshot should preserve its full frame in the card.
- Replace city-focused snapshot framing with route-focused framing for journey thumbnails. The framing should fit the whole route, add a light safety margin, and then expand only as much as needed to satisfy the thumbnail aspect ratio.
- Post-process the snapshot base map with lower saturation and slightly darker brightness before drawing the highlighted route, so the route remains prominent while the map recedes.

**Testing:**
- Add unit tests for the route-focused framing helper to verify full-route inclusion and bounded padding.
