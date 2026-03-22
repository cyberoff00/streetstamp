# Safe Current User Data Repair Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a safe repair flow that fixes the current user's corrupted local display data without touching other users' directories or re-legitimizing polluted journeys.

**Architecture:** Keep repair strictly scoped to `activeLocalProfileID`. Add a diagnostic/report layer that classifies current local journeys into allowed vs quarantined sets, move disallowed files into a per-user quarantine directory, then rebuild ordered local indexes and caches from the cleaned current-user directory only. Keep startup lightweight by performing only cheap integrity checks and deferring expensive repair work to explicit user action or background follow-up.

**Tech Stack:** Swift, SwiftUI, Foundation file I/O, existing `StoragePath`, `JourneyStore`, `CityCache`, `GuestDataRecoveryService`, XCTest

---

### Task 1: Define Current-User Repair Rules

**Files:**
- Modify: `docs/plans/2026-03-15-local-journey-isolation-and-auth-resume-design.md`
- Create: `StreetStamps/CurrentUserRepairModels.swift`
- Test: `StreetStampsTests/CurrentUserRepairPolicyTests.swift`

**Step 1: Write the failing test**

```swift
func test_classifyJourneySources_allowsOnlyCurrentGuestAndCurrentAccount() {
    let policy = CurrentUserRepairPolicy(
        activeLocalProfileID: "local_guest123",
        currentGuestScopedUserID: "guest_guest123",
        currentAccountUserID: "account_abc"
    )

    XCTAssertTrue(policy.allows(.deviceGuest(guestID: "guest123")))
    XCTAssertTrue(policy.allows(.accountCache(accountUserID: "abc")))
    XCTAssertFalse(policy.allows(.deviceGuest(guestID: "other")))
    XCTAssertFalse(policy.allows(.unknown))
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CurrentUserRepairPolicyTests`

Expected: FAIL because repair policy types do not exist yet.

**Step 3: Write minimal implementation**

Create value types for:
- `CurrentUserRepairPolicy`
- `JourneyRepairSource`
- `JourneyRepairDisposition`
- `CurrentUserRepairReport`

Make policy express one rule only:
- allow current device guest
- allow current account cache
- quarantine everything else

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS for the new policy test.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-15-local-journey-isolation-and-auth-resume-design.md StreetStamps/CurrentUserRepairModels.swift StreetStampsTests/CurrentUserRepairPolicyTests.swift
git commit -m "feat: define current-user repair policy"
```

### Task 2: Build Current-User Diagnostic Report

**Files:**
- Create: `StreetStamps/CurrentUserRepairDiagnostic.swift`
- Modify: `StreetStamps/DataIntegrityDiagnostic.swift`
- Test: `StreetStampsTests/CurrentUserRepairDiagnosticTests.swift`

**Step 1: Write the failing test**

```swift
func test_buildReport_marks_unindexed_and_disallowed_journeys() throws {
    let fixture = try CurrentUserRepairFixture.make()
    try fixture.writeJourney(id: "guest-ok", source: .deviceGuest(guestID: "guest123"), indexed: true)
    try fixture.writeJourney(id: "foreign", source: .unknown, indexed: false)

    let report = try CurrentUserRepairDiagnostic.buildReport(
        activeLocalProfileID: fixture.activeLocalProfileID,
        currentGuestScopedUserID: fixture.currentGuestScopedUserID,
        currentAccountUserID: fixture.currentAccountUserID
    )

    XCTAssertEqual(report.allowedJourneyIDs, ["guest-ok"])
    XCTAssertEqual(report.quarantinedJourneyIDs, ["foreign"])
    XCTAssertEqual(report.missingFromIndexJourneyIDs, ["foreign"])
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CurrentUserRepairDiagnosticTests`

Expected: FAIL because diagnostic code does not exist.

**Step 3: Write minimal implementation**

Implement a report builder that:
- scans only `StoragePath(userID: activeLocalProfileID).journeysDir`
- loads journey IDs from `index.json` and actual files
- reads metadata or infers source from available fields
- classifies each journey using `CurrentUserRepairPolicy`
- reports:
  - `allowedJourneyIDs`
  - `quarantinedJourneyIDs`
  - `missingFromIndexJourneyIDs`
  - `orphanedIndexedJourneyIDs`

Keep it read-only.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS for report generation.

**Step 5: Commit**

```bash
git add StreetStamps/CurrentUserRepairDiagnostic.swift StreetStamps/DataIntegrityDiagnostic.swift StreetStampsTests/CurrentUserRepairDiagnosticTests.swift
git commit -m "feat: add current-user repair diagnostics"
```

### Task 3: Add Quarantine-Based Current-User Repair

**Files:**
- Create: `StreetStamps/CurrentUserRepairService.swift`
- Modify: `StreetStamps/StoragePath.swift`
- Modify: `StreetStamps/JourneyIndexRepairTool.swift`
- Test: `StreetStampsTests/CurrentUserRepairServiceTests.swift`

**Step 1: Write the failing test**

```swift
func test_repair_moves_disallowed_journeys_to_quarantine_and_rebuilds_ordered_index() throws {
    let fixture = try CurrentUserRepairFixture.make()
    try fixture.writeJourney(id: "allowed-newer", source: .deviceGuest(guestID: "guest123"), indexed: false, endTime: Date(timeIntervalSince1970: 200))
    try fixture.writeJourney(id: "foreign", source: .unknown, indexed: true, endTime: Date(timeIntervalSince1970: 300))
    try fixture.writeJourney(id: "allowed-older", source: .accountCache(accountUserID: "abc"), indexed: true, endTime: Date(timeIntervalSince1970: 100))

    let result = try CurrentUserRepairService.repairCurrentUser(...)

    XCTAssertEqual(result.quarantinedJourneyIDs, ["foreign"])
    XCTAssertEqual(try fixture.loadIndex(), ["allowed-newer", "allowed-older"])
    XCTAssertTrue(fixture.quarantineContains("foreign"))
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CurrentUserRepairServiceTests`

Expected: FAIL because service does not exist.

**Step 3: Write minimal implementation**

Implement repair so it:
- creates a per-user quarantine directory under the active local profile
- moves all journey file variants (`.json`, `.meta.json`, `.delta.jsonl`) for quarantined IDs
- rebuilds `index.json` from allowed journeys only
- preserves order by:
  - completed journeys sorted by descending `endTime`
  - ongoing journeys first if present
  - fallback to `startTime`
  - final fallback to file modification date
- returns a structured repair result

Update `JourneyIndexRepairTool` so it can rebuild from an explicit allowed ID list rather than scanning everything blindly.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS and quarantine behavior verified.

**Step 5: Commit**

```bash
git add StreetStamps/CurrentUserRepairService.swift StreetStamps/StoragePath.swift StreetStamps/JourneyIndexRepairTool.swift StreetStampsTests/CurrentUserRepairServiceTests.swift
git commit -m "feat: quarantine invalid current-user journeys during repair"
```

### Task 4: Rebuild Current-User Caches Safely

**Files:**
- Modify: `StreetStamps/CityNameRepairService.swift`
- Modify: `StreetStamps/CityCache.swift`
- Test: `StreetStampsTests/CurrentUserCacheRepairTests.swift`

**Step 1: Write the failing test**

```swift
func test_rebuildCityCache_preserves_displayable_fields_and_uses_clean_journeys_only() throws {
    let existing = CachedCity(...)
    let journeys = [allowedJourney]

    let rebuilt = try CityNameRepairService.rebuildCityCacheSnapshot(
        journeys: journeys,
        existingCities: [existing]
    )

    XCTAssertEqual(rebuilt.first?.journeyIds, [allowedJourney.id])
    XCTAssertEqual(rebuilt.first?.thumbnailBasePath, existing.thumbnailBasePath)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CurrentUserCacheRepairTests`

Expected: FAIL because cache rebuild snapshot API does not exist.

**Step 3: Write minimal implementation**

Refactor cache repair to:
- build a cache snapshot from allowed journeys only
- preserve reusable display fields from an existing cache entry when city identity matches
- write the rebuilt cache atomically

Avoid replacing cache fields with `nil` when older valid values exist.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS and cache metadata preserved.

**Step 5: Commit**

```bash
git add StreetStamps/CityNameRepairService.swift StreetStamps/CityCache.swift StreetStampsTests/CurrentUserCacheRepairTests.swift
git commit -m "fix: preserve cache metadata during current-user repair"
```

### Task 5: Replace Settings Repair Button Flow

**Files:**
- Modify: `StreetStamps/SettingsView+DataRepair.swift`
- Modify: `StreetStamps/SettingsView.swift`
- Test: `StreetStampsTests/SettingsDataRepairFlowTests.swift`

**Step 1: Write the failing test**

```swift
func test_repairData_uses_current_user_report_and_service_not_blind_full_reindex() async throws {
    let harness = SettingsDataRepairHarness(...)

    await harness.runRepair()

    XCTAssertEqual(harness.invokedActiveLocalProfileID, "local_guest123")
    XCTAssertTrue(harness.didBuildReport)
    XCTAssertTrue(harness.didRepairCurrentUser)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/SettingsDataRepairFlowTests`

Expected: FAIL because the settings flow still calls the blind index rebuild path.

**Step 3: Write minimal implementation**

Update the settings action so it:
- builds a current-user report first
- shows a safe summary of what will be kept vs quarantined
- runs `CurrentUserRepairService`
- waits on actual async completion instead of `sleep(1)`
- reloads `JourneyStore` and `CityCache` only after repair completes
- reports counts for repaired, quarantined, and recovered journeys

Keep the UI scoped to the current user only.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS and no blind rebuild path remains.

**Step 5: Commit**

```bash
git add StreetStamps/SettingsView+DataRepair.swift StreetStamps/SettingsView.swift StreetStampsTests/SettingsDataRepairFlowTests.swift
git commit -m "feat: use safe current-user repair flow from settings"
```

### Task 6: Add Lightweight Startup Integrity Check

**Files:**
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/CurrentUserRepairStartupCheckTests.swift`

**Step 1: Write the failing test**

```swift
func test_startupIntegrityCheck_marksRepairNeeded_without_blocking_boot() throws {
    let state = try StartupRepairFixture.makeOutdatedIndexState()

    let result = CurrentUserRepairDiagnostic.quickCheck(...)

    XCTAssertTrue(result.needsRepair)
    XCTAssertFalse(result.requiresBlockingBootstrap)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CurrentUserRepairStartupCheckTests`

Expected: FAIL because no quick integrity check exists.

**Step 3: Write minimal implementation**

Add a cheap startup check that only inspects:
- current index count
- actual journey file count
- presence of prior quarantined items

If inconsistent:
- mark current user as `needsRepair`
- do not scan other users
- do not block first render

Expose this to settings or a subtle in-app warning later.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.

Expected: PASS and startup remains non-blocking.

**Step 5: Commit**

```bash
git add StreetStamps/Usersessionstore.swift StreetStamps/StreetStampsApp.swift StreetStampsTests/CurrentUserRepairStartupCheckTests.swift
git commit -m "feat: add lightweight startup repair check"
```

### Task 7: Verify End-to-End Safety

**Files:**
- Modify: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`
- Modify: `StreetStampsTests/JourneyCloudMigrationServiceSafetyTests.swift`
- Create: `StreetStampsTests/CurrentUserRepairEndToEndTests.swift`

**Step 1: Write the failing test**

```swift
func test_currentUserRepair_fixes_active_local_without_touching_other_users() throws {
    let fixture = try MultiUserRepairFixture.make()
    try fixture.writeForeignJourneyIntoCurrentLocal()
    try fixture.writeOtherUserDirectory()

    let result = try fixture.runRepair()

    XCTAssertEqual(result.otherUserDirectoryMutationCount, 0)
    XCTAssertEqual(result.currentLocalVisibleJourneys, fixture.expectedAllowedJourneyIDs)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CurrentUserRepairEndToEndTests`

Expected: FAIL because end-to-end safety guarantees are not encoded yet.

**Step 3: Write minimal implementation**

Cover:
- current local polluted with foreign journey files
- current user’s own journey files missing from index
- another user directory present on disk and left untouched
- repair keeps only allowed journeys visible
- quarantine captures the foreign journey files

Add or update tests in recovery and cloud migration suites only where needed to keep behavior aligned.

**Step 4: Run test to verify it passes**

Run the targeted test suite plus related safety tests:

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/CurrentUserRepairEndToEndTests -only-testing:StreetStampsTests/GuestDataRecoveryServiceTests -only-testing:StreetStampsTests/JourneyCloudMigrationServiceSafetyTests
```

Expected: PASS for the targeted coverage.

**Step 5: Commit**

```bash
git add StreetStampsTests/GuestDataRecoveryServiceTests.swift StreetStampsTests/JourneyCloudMigrationServiceSafetyTests.swift StreetStampsTests/CurrentUserRepairEndToEndTests.swift
git commit -m "test: verify current-user repair safety end to end"
```

### Task 8: Final Verification

**Files:**
- Modify: none unless verification reveals issues

**Step 1: Run focused repair tests**

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
  -only-testing:StreetStampsTests/CurrentUserRepairPolicyTests \
  -only-testing:StreetStampsTests/CurrentUserRepairDiagnosticTests \
  -only-testing:StreetStampsTests/CurrentUserRepairServiceTests \
  -only-testing:StreetStampsTests/CurrentUserCacheRepairTests \
  -only-testing:StreetStampsTests/SettingsDataRepairFlowTests \
  -only-testing:StreetStampsTests/CurrentUserRepairStartupCheckTests \
  -only-testing:StreetStampsTests/CurrentUserRepairEndToEndTests
```

Expected: PASS.

**Step 2: Run one broader safety pass**

```bash
xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
  -only-testing:StreetStampsTests/GuestDataRecoveryServiceTests \
  -only-testing:StreetStampsTests/JourneyCloudMigrationServiceSafetyTests
```

Expected: PASS.

**Step 3: If unrelated existing failures block verification**

Record the exact failing test target and compiler/runtime error in the final handoff. Do not claim full success without evidence.

**Step 4: Commit**

```bash
git add docs/plans/2026-03-15-safe-current-user-data-repair-implementation.md
git commit -m "docs: add safe current-user repair implementation plan"
```
