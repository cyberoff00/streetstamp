# Memory Location And Friend Memory Design

**Problem**

Local journey memories currently depend too heavily on transient foreground location state. In weak GPS conditions this can produce stale or missing memory coordinates, block user flows like ending a journey, and degrade downstream map/share experiences. Separately, shared/friend journeys do not carry explicit memory coordinates through backend sync, and friend memory pins do not open a photo-capable detail view.

**Goals**

- Memory records must own durable location data instead of depending on cached foreground state.
- Weak GPS must never block saving a memory or ending a journey.
- Shared journey payloads should include explicit memory coordinate fields for future friend-visible memory maps.
- Friend memory pins should open read-only memory details with remote photos.
- Share cards and journey summaries should degrade gracefully instead of rendering a broken placeholder when memory/journey location completeness is partial.

**Non-Goals**

- Frontend manual drag-to-edit memory location.
- New privacy controls for public memory coordinate sharing.
- Backend-only migration that rewrites all previously uploaded memory records.

**Recommended Approach**

Introduce explicit memory location resolution states and decouple "content saved" from "location finalized". New memories always save their content immediately. Their location is resolved from the best available source at save time, or marked pending if no reliable source exists. Pending memories are opportunistically backfilled later and are finalized during journey end without blocking completion. Backend sync is extended to upload memory latitude/longitude plus optional status metadata, and friend read paths are updated to consume these fields. Friend memory pin interactions are routed to the same read-only memory detail experience used locally, with remote image URLs supported.

**Local Memory Location Rules**

- On create, the app attempts to resolve a coordinate in this order:
  1. Fresh and accurate `TrackingService.userLocation`
  2. Nearest journey track point by timestamp
  3. Last known valid location
  4. Mark as `pending`
- Save of text/photo content always succeeds.
- Once a memory gains a resolved coordinate, later automatic updates do not overwrite it.
- When ending a journey, all pending memories are finalized best-effort using:
  1. Nearest journey track point by timestamp
  2. Last known valid location
  3. Remain pending if neither exists
- Ending a journey never blocks on GPS.

**Data Model**

Extend `JourneyMemory` with:

- `locationStatus`
  - `resolved`
  - `fallback`
  - `pending`
- `locationSource`
  - `liveGPS`
  - `trackNearestByTime`
  - `lastKnownLocation`
  - `pending`

The existing `coordinate` field remains the canonical stored coordinate, but its semantics change from "best effort immediate point" to "memory-owned location value with status metadata". Pending memories may temporarily carry a placeholder coordinate, but the UI must respect the status and avoid implying a verified exact point when status is pending.

**Backend Sync**

Extend uploaded memory DTOs with:

- `latitude: Double?`
- `longitude: Double?`
- `locationStatus: String?`

Download paths should prefer explicit remote memory coordinates when present. Old payloads without coordinates remain supported through optional decoding.

**Friend Memory UX**

- Friend/shared memory pins should open a read-only memory detail surface.
- The detail surface must display `remoteImageURLs` photos and text content.
- No editing or deletion controls are shown for shared memories.

**Share Card Fallback**

Share/journey card generation should no longer treat incomplete memory location state as a hard failure. Rendering tiers:

- Full map when route and memory coordinates are available.
- Partial map when only route or partial memory coordinates are available.
- Non-map summary card when route data is insufficient.

This avoids user-visible broken placeholders.

**Testing Strategy**

- Unit tests for location resolution priority and nearest-track fallback.
- Unit tests for journey end finalizing pending memories without blocking completion.
- Codable tests for new memory location fields.
- Backend DTO encode/decode tests for new memory coordinate fields.
- Friend read-path tests ensuring explicit remote memory coordinates are preserved.
- UI interaction test or focused view-model test for friend memory pin opening read-only detail with remote photos.

**Risks**

- Pending-memory placeholder handling must not accidentally cluster unrelated pins.
- Backend compatibility must remain optional until all clients send the new fields.
- Share-card fallback logic should avoid regressing current successful full-map renders.
