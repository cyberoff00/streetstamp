# CLAUDE.md

## Team Shared Memory

### Project Shape
- This repository contains a SwiftUI iOS app, a watchOS app, a widget/live activity extension, and a Node backend.
- Main app target: `StreetStamps`
- Test target: `StreetStampsTests`
- Watch target: `StreetStampsWatch`
- Widget/live activity target: `TrackingWidgeExtension`
- Backend lives in `backend-node-v1`

### Core Architecture Patterns
- The iOS app entry point is `StreetStamps/StreetStampsApp.swift`.
- App state is organized around shared stores and services such as `UserSessionStore`, `JourneyStore`, `CityCache`, `LifelogStore`, `TrackTileStore`, `SocialGraphStore`, and `PostcardCenter`.
- Business logic is often extracted into small pure helpers or policy/presentation types, then covered with focused XCTest files.
- Common naming patterns in the app:
  - `*Store` for persisted/shared state or coordination
  - `*Service` for side-effectful operations
  - `*Policy` / `*Presentation` / `*Resolver` for pure logic
  - `*View` for SwiftUI screens/components
- Cloud sync work is centered around CloudKit-related services in `StreetStamps/`, and the backend is currently in a migration phase away from Firebase-first auth toward backend-owned auth.
、
### Identity And Ownership Model
- The most important boundary in this app is the difference between local storage ownership and account/cloud identity.
- `UserSessionStore` is the source of truth for session mode and identity boundaries.
- `activeLocalProfileID` is the real local storage owner. It determines which on-disk user directory is active.
- `currentUserID` currently resolves to `activeLocalProfileID`. In app code, this usually means "the active local data scope".
- `accountUserID` is the signed-in backend/cloud account identity. It is the account owner for cloud-facing features, but it is not always the same thing as the active local storage directory.
- `guestID` is a stable device-side guest identity used to preserve guest continuity and later bind guest data to an account.
- The app deliberately keeps local profile scope and cloud/account scope as separate concepts. Do not collapse them mentally into one `userID`.

### Local Storage Ownership
- `StoragePath(userID:)` is the single source of truth for local on-disk ownership.
- All user-scoped local files live under:
  - `Application Support/StreetStamps/<userID>/`
- Important subdirectories/files under a user scope:
  - `Journeys/`
  - `Caches/`
  - `Photos/`
  - `Thumbnails/`
  - `Caches/lifelog_passive_route.json`
  - `Caches/lifelog_mood.json`
  - `Caches/city_cache.json`
  - `Caches/track_tiles/`
- If a feature persists files through `StoragePath(userID: ...)`, that data belongs to the local profile scope passed into `StoragePath`, not automatically to the logged-in cloud account.

### Session Lifecycle And Scope Rebinding
- `StreetStampsApp` initializes stores using `StoragePath(userID: session.activeLocalProfileID)`.
- The app listens to `sessionStore.activeLocalProfileID` changes and then rebinds the major stores to the new storage scope.
- On `activeLocalProfileID` change, the app rebinds and reloads at least:
  - `JourneyStore`
  - `CityCache`
  - `LifelogStore`
  - `CityRenderCacheStore`
  - `TrackTileStore`
  - `SocialGraphStore`
  - `PostcardCenter`
- This means a profile switch is not just an auth change. It is a storage-root switch followed by data reload and derived-cache rebuild.

### Journey Data Chain
- `JourneyStore` is the primary owner of local journey persistence for the active storage scope.
- Journey data is stored under the active user's `Journeys/` directory.
- The store keeps:
  - a lightweight `index.json`
  - per-journey files
  - delta/meta persistence for active tracking
- `JourneyStore` loads ordered IDs first, then loads the actual routes. This keeps list screens cheap.
- During tracking, `JourneyStore.upsertSnapshotThrottled(...)` updates in-memory state and persists incrementally.
- When a journey completes, persistence is flushed immediately.
- Journey-derived state such as city caches, track tiles, preview render inputs, and some UI snapshots are downstream of `JourneyStore`; they should be treated as derived state, not the canonical source.

### Lifelog Data Chain
- `LifelogStore` is the primary owner of passive movement history for the active storage scope.
- Lifelog is stored per active local profile under `StoragePath(userID: activeLocalProfileID)`.
- Canonical local lifelog state includes:
  - passive route points
  - archived journey point imports
  - mood-by-day
  - archived journey IDs
  - country attribution data
- Lifelog is not just "current GPS history". It also absorbs completed journey coordinates through `archiveJourneyPointsIfNeeded(...)`.
- This means completed journey geometry can be copied into the passive lifelog timeline for historical/coverage use, while `JourneyStore` remains the canonical source for the journey entity itself.
- `LifelogStore` also feeds track tiles, recent-day rendering, availability-by-day, and country/cell attribution logic.

### Journey vs Lifelog Ownership Rule
- `JourneyStore` owns journey entities, journey metadata, journey memories, and the canonical journey timeline for that trip.
- `LifelogStore` owns passive background history and archived coverage-oriented point history.
- If a completed journey's coordinates are copied into lifelog, that does not transfer entity ownership away from `JourneyStore`.
- If a bug touches both journey completion and passive coverage, inspect both stores before changing either persistence format.

### Guest vs Account Semantics
- Guest mode and account mode share a device, but they must not be treated as the same ownership layer.
- A guest session is still backed by a stable local profile and local filesystem scope.
- Logging into an account updates session/account state and creates a guest-to-account binding, but local data migration/rebinding is a separate concern from token acquisition.
- `UserSessionStore` records guest/account bindings so the app can recover or reconcile prior local guest data with a later account identity.
- `pendingMigrationFromGuestUserID` exists specifically because guest-to-account reconciliation may need to happen explicitly instead of being assumed complete.

### Guest Recovery And Device Repair
- `GuestDataRecoveryService` is the main local merge path for bringing guest-scoped data into another local scope.
- It operates on user-scoped storage directories, not on backend records.
- Recovery can merge:
  - journey files and journey indexes
  - photos
  - thumbnails
  - lifelog route data
  - lifelog mood data
- Imported journeys can be tagged in `JourneyRepairSourceStore` so later repair logic knows where the data came from.
- This repair/recovery path is about local filesystem ownership and provenance, not just login state.

### Cloud And Account Ownership
- Cloud-facing ownership is usually keyed by `accountUserID` when available.
- In Settings, iCloud sync and manual restore explicitly use:
  - `localUserID = sessionStore.activeLocalProfileID`
  - `accountID = sessionStore.accountUserID ?? localUserID`
- This is an important pattern:
  - local stores still operate on the active local profile
  - CloudKit status/sync identity prefers the signed-in account ID when one exists
- Do not assume CloudKit sync automatically changes the local storage root. Sync identity and local directory identity are related but separate.

### CloudKit Sync Chain
- `CloudKitSyncService` is the sole high-level coordinator for CloudKit sync.
- CloudKit domains currently include:
  - journeys
  - journey memories/photos
  - passive lifelog batches
  - lifelog mood
  - settings
- `syncCurrentState(...)` uploads snapshots from the currently bound local stores.
- `restoreAllData(...)` restores into the currently bound local stores and then rebuilds derived city state if journeys changed.
- For lifelog, CloudKit sync is day-batch based rather than one giant monolithic dump.
- For journeys, restore merges upserts and deletions into `JourneyStore`, instead of blindly overwriting everything.

### Practical Data Flow Summary
- Startup:
  - `UserSessionStore` determines the active local profile
  - stores are created with `StoragePath(userID: activeLocalProfileID)`
- Profile change:
  - `StreetStampsApp` rebinds stores to the new local scope and reloads data
- Active journey tracking:
  - tracking updates `JourneyStore`
  - `JourneyStore` persists route deltas/meta
  - downstream caches and tiles rebuild from store state
- Journey completion:
  - `JourneyStore` finalizes the journey
  - sync hooks may upload/delete CloudKit journey records
  - `LifelogStore.archiveJourneyPointsIfNeeded(...)` may import the route into passive history
- Passive lifelog:
  - `LifelogStore` records passive points and mood under the active local profile
  - CloudKit uploads day-based lifelog deltas from that local store
- Manual iCloud restore:
  - restore uses account identity for sync status/remote ownership
  - restored data is merged into the currently bound local stores

### Journey Tracking Pipeline (Verified)
- Location tracking is in `SystemLocationSource.swift` and `TrackingService.swift`.
- Two tracking modes: Sport (high precision, 3m min distance, OneEuro enabled) and Daily (battery-optimized, 12m min distance, OneEuro disabled).
- GPS point filtering is multi-stage: first-fix lock → distance sampling → stationary jitter suppression → turn detection → jump/spike filtering → signal recovery gap detection.
- Stationary jitter: dynamic min move = `max(baseMinMove, 0.9 × horizontalAccuracy)`.
- Jump filtering: drops points with `accuracy ≥ 120m` + `distance ≥ 180m` + `time ≤ 30s`; drops speed anomalies > 18 m/s.
- OneEuro adaptive smoothing: adjusts `minCutoff` based on GPS accuracy. Never applied to turn points or background tracking.
- Signal loss renders as dashed segments; very long gaps (≥15min + 500m) as missing segments.
- Post-completion: `JourneyPostCorrection` removes tiny steps and single-point spikes. `JourneyRoutePostProcessor` optionally snaps to roads via Apple Maps (80–200km range only).
- Delta persistence: 60s (sport) / 180s (daily). Crash can lose up to that interval of points.
- Daily mode dynamically adjusts parameters based on detected travel mode (walk/run/transit/bike/drive/flight) via speed median.
- CoreMotion fusion (`MotionActivityFusion`) validates stationary detection.
- China coordinate offset (WGS84 → GCJ-02) applied for rendering only, with fast bounding-box check.

### City Identity System (Verified)
- City key format: `"<EnglishCityName>|<ISO2>"`, e.g., `"Shanghai|CN"`.
- City key is ALWAYS generated using `CLGeocoder` with `fixedLocale = Locale(identifier: "en_US")`. This is locale-independent and stable.
- `stripAdminSuffix` removes `" City"`, `" Shi"`, `" Prefecture"`, `" District"`, `"市"`, `"区"`, `"县"` — so `"Shanghai Shi"` becomes `"Shanghai"`. This is already handled.
- `JourneyFinalizer.finalize()` is the single write path for city keys. It sets both `startCityKey` and `cityKey` to the same canonical value from `resolveCanonical`.
- `JourneyRoute.stableCityKey` is a READ-ONLY computed property that returns `startCityKey ?? cityKey`. It is NOT a separate write source.
- `canonicalCityKeyFallback` is only used when `stableCityKey` is empty (legacy/broken journeys). It is NOT a normal path.

### City Level Resolution (Verified)
- `CityPlacemarkResolver.decideLevel()` determines which administrative level to use for a city key.
- Level is decided by: island detection → user's `CityLevelPreferenceStore` preferred level → country-specific strategy → fallback chain.
- Country-specific strategies (hardcoded):
  - `strategyCountry` (SG, HK, MO, TW, etc.): entire country = one city card.
  - Chinese municipalities (Beijing, Shanghai, Tianjin, Chongqing): forced to `.admin` level via `isChineseMunicipality()`. Pudong will NEVER become a separate key for Shanghai.
  - `strategySubAdmin` (CN non-municipality, GB, FR, etc.): uses `subAdministrativeArea`.
  - JP Tokyo, KR Seoul/Busan, TH Bangkok: forced to `.admin`.
- When user changes level preference in `CityDeepView`, `CityLevelPreferenceStore.setPreferredLevel()` persists the choice per `parentRegionKey`.
- NEW journeys respect the preference via `resolveCanonical` → `decideLevel(preferred:)`.
- When user changes level preference, `CityDeepView.applyCityLevelPreference` now re-keys old journeys whose `stableCityKey` matches any source key but differs from the new `targetKey`, using `upsertSnapshotThrottled` + `rebuildFromJourneyStore()`.

### City Display Name Resolution (Verified)
- City identity (key) is locale-independent. Display names are locale-dependent. These are separate layers.
- Display name resolution priority in `CityPlacemarkResolver.displayTitle()`:
  1. `availableLevelNames[chosenLevel]` (stored locally per city, locale-aware)
  2. `localizedDisplayNameByLocale[locale.identifier]` (persisted per city)
  3. `syncCachedDisplayTitle` from `ReverseGeocodeService` UserDefaults cache
  4. `fallbackTitle` or city name extracted from `cityKey`
- Locale switch does NOT cause blank cities — 4 layers of fallback ensure something always shows.
- `ReverseGeocodeService` rate limits at 1.5s minimum between requests, with backoff on system throttle (GEOErrorDomain -3).
- Display title caching is keyed by `"<cityKey>|<localeID>|<displayScope>"`.
- `CityLibraryVM.prefetchDisplayNamesDetached()` lazily resolves localized names on load.

### City Membership And Deduplication (Verified)
- `CityMembershipContribution` reads `journey.stableCityKey` to determine which city a journey belongs to. This is the grouping key.
- `CityMembershipIndex` groups journeys by city key. `CityCache.rebuildFromJourneyStore()` rebuilds from this index.
- `CityCollectionResolver` provides static mapping (`CityCollectionMapping.json`) to merge city keys into collections for display grouping.
- On-load deduplication: exact `city.id` dedup via `Set<String>`. This is sufficient because the write path produces consistent keys.

### Social City Data (Verified, By Design)
- `FriendCityCard.name` stores the friend's locale-specific display name. This is intentional — the viewer sees the friend's city name as the friend has it.
- `FriendCityCard.id` is the stable English city key, used for identity matching.
- `FriendJourneyCityIdentity.resolveCityID()` matches friend journeys to city cards via: exact ID match → normalized name match → fuzzy containment.
- Postcard `cityName` is a snapshot from send time. This is standard messaging behavior — sent messages do not dynamically re-translate.
- Backend stores both `cityID` (stable) and `cityName` (display snapshot) separately.

### Code Style And Conventions
- Prefer small, testable logic units over burying logic inside large SwiftUI views.
- Follow existing Swift naming style: `UpperCamelCase` for types, descriptive noun-based names for helpers, and explicit suffixes like `Store`, `Service`, `Policy`, `Presentation`, `Resolver`.
- Tests are usually narrowly scoped and named after the behavior under test, for example `FeatureNameTests.swift`.
- Localization uses `L10n` helpers instead of hardcoded UI strings.
- Keep changes aligned with existing patterns instead of introducing parallel architectures.

### Reliable Commands

#### iOS Build
```bash
xcodebuild build -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'
```

#### Focused iOS Test Pattern
```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/<TestCaseName>
```

#### Widget Build
```bash
xcodebuild build -scheme TrackingWidgeExtension -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1'
```

#### Backend
```bash
cd backend-node-v1
npm start
npm test
npm run test:api-contract
```

#### Repo Checks
```bash
bash scripts/preflight_check.sh
bash scripts/readonly_prod_check.sh
```

### Working Notes
- The repo is often in a dirty state; inspect before editing and do not revert unrelated changes.
- There are many historical design and implementation notes under `docs/plans/` and ops runbooks under `docs/ops/`; check them before changing established flows.
- Package resolution and simulator access can fail in restricted environments even when project files are correct, so prefer commands that write derived data locally when needed.
- When changing data ownership logic, inspect `UserSessionStore`, `StreetStampsApp`, `StoragePath`, `JourneyStore`, `LifelogStore`, `CloudKitSyncService`, and `GuestDataRecoveryService` together.

## Change Discipline

### Rule: Think Critically, Not Obediently
- The user is not a professional software engineer. Many requests are based on surface-level observations, other apps' UX patterns, or suggestions from prior AI conversations — not deep technical analysis.
- Do NOT blindly execute instructions. Before implementing, evaluate whether the request actually makes sense for this codebase, this scale, and this product's real needs.
- When a request introduces unnecessary complexity, solves a non-existent problem, or copies a pattern from apps operating at a fundamentally different scale, say so directly and propose a better alternative.
- Back up every recommendation with concrete reasoning: code references, data structure analysis, or algorithmic complexity — not vague appeals to "best practices" or "clean architecture".
- Never say something works or is correct without verifying it in code. Never give empty reassurance. If you are unsure, say so and investigate before answering.
- If a previous AI conversation led to a bad direction, acknowledge the mistake clearly and course-correct rather than building on top of a flawed foundation.

### Rule: Think Globally Before Acting Locally
- Before making any change, trace its impact across the full logic chain. A "simple fix" in one store can break downstream consumers, sync paths, or derived caches.
- Specifically, ask these questions before editing:
  1. **Who reads this data?** Trace all consumers of the field/function being changed. Use `rg` to find every call site, not just the one you're focused on.
  2. **Who writes this data?** Confirm whether you are touching the single canonical write path or introducing a second one. This repo has deliberate single-write-path designs (e.g., `JourneyFinalizer` for city keys). Do not accidentally create divergent write sources.
  3. **What rebuilds from this?** Many stores trigger downstream rebuilds (`CityCache.rebuildFromJourneyStore`, `TrackTileStore`, lifelog archive). Changing an upstream format or timing can silently break downstream invariants.
  4. **Does this cross an ownership boundary?** Changes near `UserSessionStore`, `StoragePath`, or any `userID` parameter may silently move data between local profile scope and cloud/account scope. See Identity And Ownership Model above.
  5. **Is this actually better, or just different?** Not every refactor is an improvement. If existing code works correctly and is readable, resist the urge to restructure it. Churn without clear benefit adds risk.

### Rule: Challenge The User's Request When Necessary
- If the user asks for a change that would break existing behavior, introduce inconsistency, or conflict with established architecture, say so explicitly before proceeding.
- Do not silently comply with a request that you can see will cause problems. Explain the concern, point to the specific code or design constraint, and propose an alternative.
- If the user insists after hearing the concern, proceed but document the tradeoff in a code comment or commit message.
- This is not about refusing work — it is about protecting the user from unintended consequences that are easier to prevent than to debug later.

### Rule: Optimization Must Justify Its Cost
- Every optimization introduces complexity. Before "improving" code, verify:
  - Is there a measured problem? (performance issue, crash, data corruption, user complaint)
  - Does the optimization preserve all existing behavior, including edge cases?
  - Is the optimization's complexity proportional to the problem it solves?
- Do not optimize for hypothetical scale, theoretical purity, or personal style preference. Optimize for real, demonstrated problems.
- If an optimization requires touching more than 3 files, pause and reconsider whether the scope is justified.

### Rule: Verify The Full Round-Trip Before Declaring Done
- After making a change, mentally (or actually) trace the full round-trip: write → persist → reload → display, or request → process → respond → consume.
- A change that looks correct at the write site but breaks at the read site is not done.
- For data model changes, verify: serialization, deserialization, migration of old data, CloudKit sync, and UI display.

## Assessment Discipline

### Rule: Every Claim Must Be Traced To Code
- Do NOT make assessments based on file names, function signatures, or general industry knowledge alone. Read the actual implementation before stating whether something is a problem.
- If you have not read the function body, say "I haven't read this yet" instead of guessing what it does.
- When evaluating risk, trace the complete data path (write → persist → read → display) before concluding. A risk that looks real at one layer may already be handled at another.

### Rule: Do Not Invent Problems
- Do not claim a bug or risk exists unless you can point to specific lines of code that demonstrate the issue.
- If the codebase already handles a scenario (e.g., `stripAdminSuffix` handles "Shanghai Shi", `isChineseMunicipality` handles direct-administered municipalities), acknowledge the existing protection instead of warning about it as if it were missing.
- Multiple fallback paths for READING a value do not mean multiple WRITE paths. Distinguish between read-time fallback chains and actual divergent write sources.

### Rule: Do Not Apply Generic Knowledge Over Specific Code
- Do not say "CLGeocoder is known to be unstable" if the code already normalizes its output. The question is whether the code's handling is sufficient, not whether the upstream API is theoretically imperfect.
- Do not say "locale snapshots are a bug" if the product design intentionally uses them (e.g., friend city names, sent postcards). Evaluate whether the behavior is a bug or a deliberate design choice before flagging it.

### Rule: Correct Yourself Immediately
- If you realize a previous assessment was wrong, retract it explicitly and explain why it was wrong.
- Do not soften a retraction into "well, it's a low risk" — if the code already handles it, say so clearly.

### Rule: Never Trust Agent Outputs Without Verification
- When using subagents for code review or exploration, treat their findings as **leads, not conclusions**. Every claim from an agent must be verified against the actual code before reporting to the user.
- Agents frequently make these specific errors:
  1. **Reading a few lines and missing nearby context** — e.g., seeing `Task.detached` and reporting "no concurrency limit" while a `DispatchSemaphore(value: 2)` exists 20 lines away in the same file.
  2. **Seeing an early `return` and concluding logic is skipped** — without checking that key state mutations happen BEFORE the return.
  3. **Applying generic anti-patterns without tracing call sites** — e.g., flagging `DispatchSemaphore` as "deadlock risk" without verifying which thread the wait occurs on.
  4. **Claiming "no cleanup" or "leak"** — without understanding Swift ARC basics like property reassignment releasing the old value.
- Before including any agent finding in a report: read the function body yourself, check at least 10 lines of surrounding context, and actively try to disprove the claim.
- When grepping for annotations like `@MainActor`, `@Published`, etc., remember they are often on the line ABOVE the declaration. Use multi-line patterns or grep with `-B 1` context to avoid false negatives.
- When citing counts (e.g., "7 @EnvironmentObject"), always recount from the actual code before stating the number. Do not rely on memory or estimation.

### Rule: Anti-Confirmation-Bias In Reviews
- When the task is "find problems", the natural bias is to interpret everything as a problem. Actively counter this by asking: **"Why might this code be correct as written?"**
- Seeing a known anti-pattern (semaphore, singleton closure, computed property) is not sufficient to report a bug. Trace the specific usage to confirm the anti-pattern actually causes harm in this context.
- If you cannot construct a concrete scenario where the "problem" manifests (specific thread, specific timing, specific user action), downgrade it or drop it.

## Personal Preferences

### How To Work In This Repo
- Start with focused verification near the changed behavior before running broader builds.
- Prefer minimal, surgical edits that preserve the current product behavior and naming style.
- When touching SwiftUI screens, move non-UI decision logic into testable helpers if the file is already getting crowded.
- When touching backend auth or migration code, check nearby docs in `docs/ops/` and `docs/plans/` first because this area is actively evolving.
- When editing localization-sensitive UI, verify whether `en`, `zh-Hans`, and other shipped `Localizable.strings` files need corresponding updates.
- When touching identity or sync code, explicitly ask:
  - Is this changing local storage owner?
  - Is this changing cloud/account owner?
  - Is this only changing a binding between the two?
- Avoid "simple" user ID substitutions. In this repo, replacing `currentUserID` with `accountUserID` or vice versa can silently move data across ownership boundaries.

### Production Deployment
- Server: `101.132.159.73` (Alibaba Cloud Shanghai)
- Remote app dir: `/opt/streetstamps/backend-node-v1`
- Compose file: `/opt/streetstamps/backend-node-v1/docker-compose.yml`
- Env file: `/opt/streetstamps/backend-node-v1/.env`
- API container: `streetstamps-node-v1`
- DB container: `streetstamps-postgres`
- Internal health: `http://127.0.0.1:18080/v1/health`
- Public API: `https://api.streetstamps.cyberkkk.cn`
- Deploy command: `./backend-node-v1/deploy-safe.sh` (the only supported entry point)
- Rollback: `./backend-node-v1/rollback.sh /opt/streetstamps/backups/release/<timestamp>`
- Production check: `BASE_URL=https://api.streetstamps.cyberkkk.cn EXPECTED_AUTH_MODE=backend_jwt_only EXPECTED_FIREBASE_COMPAT=false EXPECTED_WRITE_FROZEN=false ./scripts/readonly_prod_check.sh`
- Full workflow docs: `docs/ops/PRODUCTION_WORKFLOW.md`, `docs/ops/SERVER_BOOTSTRAP.md`
- No silent production syncs — always report changes and wait for approval before deploying.

### Practical Reminders
- Use `rg` for search and `rg --files` for file discovery.
- Prefer focused `xcodebuild test -only-testing:...` runs over broad test sweeps during iteration.
- For backend work, run the smallest relevant `npm` test target first, then `npm test` if the change is wider.
- Do not trust old Firebase assumptions without re-reading the latest migration docs; the newer direction is backend-owned auth with narrower Firebase compatibility.
- If a change touches journey save/finalize, passive lifelog, repair, or restore flows, read both the producing store and the consuming sync/repair path before editing.
