# Local Journey Isolation And Auth Resume Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ensure `collection_tab` only shows current-device local guest journeys plus the current account's journeys, and keep ongoing journeys + Live Activity intact across passive logout/login.

**Architecture:** Split display data from historical recovery sources, restrict automatic recovery to current-scope inputs, and introduce a persistent ongoing tracking session plus Live Activity reattachment. Fix future corruption first, then add one-time cleanup for already polluted local display state.

**Tech Stack:** Swift, SwiftUI, ActivityKit, local file-backed stores (`JourneyStore`, `CityCache`, `StoragePath`), XCTest

---

### Task 1: Lock In Current Product Rules With Failing Tests

**Files:**
- Modify: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`
- Create: `StreetStampsTests/DisplayJourneyScopeTests.swift`
- Create: `StreetStampsTests/LiveActivityReattachmentTests.swift`

**Step 1: Write failing recovery-scope tests**

Add tests that prove:
- inactive bound account roots do not auto-import
- unrelated historical guest roots do not auto-import into the active display scope
- current local guest data still appears in the active display scope

**Step 2: Run targeted tests to verify they fail**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/GuestDataRecoveryServiceTests -only-testing:StreetStampsTests/DisplayJourneyScopeTests`

Expected: failures showing current logic still imports overly broad sources or cannot express the new display scope.

**Step 3: Write failing ongoing-tracking auth tests**

Add tests that prove:
- passive logout does not clear ongoing tracking state
- re-login restores the same ongoing journey
- Live Activity manager can reattach to an existing activity handle

**Step 4: Run targeted tests to verify they fail**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LiveActivityReattachmentTests`

Expected: failures showing no reattachment path exists yet.

---

### Task 2: Restrict Automatic Recovery Sources

**Files:**
- Modify: `StreetStamps/Usersessionstore.swift`
- Test: `StreetStampsTests/GuestDataRecoveryServiceTests.swift`

**Step 1: Change automatic recovery source selection**

Update `scopedRecoverySourceUserIDs(...)` and worker variants so automatic recovery only considers:
- the current device-local guest/local source
- the current logged-in account root when present

Do not include all historical `guest_*` or previously bound accounts in automatic recovery.

**Step 2: Keep historical roots discoverable only for manual flows**

Preserve existing candidate discovery logic for explicit manual recovery UI, but do not feed it into startup auto-recovery.

**Step 3: Run targeted tests**

Run the same GuestDataRecoveryService test subset.

Expected: the new recovery scope tests pass.

---

### Task 3: Introduce Explicit Display Scope Builder

**Files:**
- Create: `StreetStamps/DisplayJourneyScope.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/JourneyMemoryNew.swift`
- Modify: `StreetStamps/CityStampLibraryView.swift`
- Test: `StreetStampsTests/DisplayJourneyScopeTests.swift`

**Step 1: Add a display-scope builder**

Create a small service/value type that produces display journeys from exactly:
- current local store contents
- current account-synced contents

The builder should expose enough structure to rebuild city and memory grouping deterministically.

**Step 2: Route collection-facing screens through display scope**

Ensure `collection_tab` reads from the scoped display result rather than implicitly trusting all recovered local content.

**Step 3: Add source metadata helpers if needed**

If necessary, add lightweight origin tagging for display validation.

**Step 4: Run tests**

Run: display scope tests + any city/memory grouping tests touched by this change.

---

### Task 4: Add One-Time Polluted Display Cleanup

**Files:**
- Create: `StreetStamps/DisplayJourneyCleanupService.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/CityCache.swift`
- Test: `StreetStampsTests/DisplayJourneyScopeTests.swift`

**Step 1: Implement cleanup service**

Given current local and current account data, rebuild the allowed journey set and remove out-of-scope content from display storage/cache.

**Step 2: Trigger cleanup at safe startup points**

Run cleanup only after stores load and before collection-facing caches are treated as authoritative.

**Step 3: Rebuild `CityCache` from cleaned journeys**

Do not preserve stale city cards whose journeys are no longer in scope.

**Step 4: Run affected tests**

Expected: polluted-state tests pass and city grouping is rebuilt correctly.

---

### Task 5: Persist Ongoing Tracking Session Snapshot

**Files:**
- Create: `StreetStamps/TrackingSessionSnapshotStore.swift`
- Modify: `StreetStamps/TrackingService.swift`
- Modify: `StreetStamps/MainView.swift`
- Test: `StreetStampsTests/TrackingServiceResumeLocationTests.swift`
- Create: `StreetStampsTests/TrackingAuthResumeTests.swift`

**Step 1: Write failing snapshot tests**

Cover:
- starting a journey writes snapshot metadata
- passive logout does not clear snapshot
- relaunch/restoration can reconstruct ongoing state

**Step 2: Implement snapshot persistence**

Persist:
- ongoing journey ID
- start time
- paused duration
- tracking mode
- pause state

**Step 3: Restore UI from snapshot**

Make `MainView` prioritize restored ongoing state and continue UI rather than start UI.

**Step 4: Run targeted tests**

Expected: ongoing journey survives passive auth changes.

---

### Task 6: Reattach Existing Live Activity

**Files:**
- Modify: `StreetStamps/LiveActivityManager.swift`
- Modify: `StreetStamps/TrackingService.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests/LiveActivityReattachmentTests.swift`

**Step 1: Add discovery/reattachment API**

On startup/foreground, query existing tracking activities and bind one back to `currentActivity`.

**Step 2: Restore timer-driven updates after reattach**

Rebuild the internal timer/cached state so updates resume instead of staying frozen.

**Step 3: Ensure stop/end still works after reattach**

Ending the journey after reattachment must dismiss the existing Live Activity rather than leave a zombie card.

**Step 4: Run targeted tests**

Expected: existing activity is rebound and updates continue.

---

### Task 7: Gate Public Visibility At Journey End While Logged Out

**Files:**
- Modify: `StreetStamps/JourneyFinalizer.swift`
- Modify: `StreetStamps/MyJourneysView.swift`
- Modify: `StreetStamps/JourneyMemoryNew.swift`
- Test: `StreetStampsTests/JourneyFinalizerTests.swift`

**Step 1: Write failing tests**

Cover:
- ending a journey with public/friends visibility while logged out saves locally
- user gets a login-to-publish prompt
- visibility is not silently lost

**Step 2: Implement pending publish handling**

If user is logged out at finalize time:
- persist locally
- downgrade to private/pending local publish state
- store a pending visibility intent

**Step 3: Add user-facing copy**

Use concise copy such as:
"Journey saved locally. Log in to publish it publicly."

**Step 4: Run targeted tests**

---

### Task 8: Add Startup Diagnostics And Guardrails

**Files:**
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/CityCache.swift`

**Step 1: Add scoped startup logs**

Log counts for:
- local journeys loaded
- current account journeys loaded
- out-of-scope journeys rejected
- whether an ongoing tracking session was restored
- whether a Live Activity was reattached

**Step 2: Add assertions/guardrails in debug**

If clearly out-of-scope journeys are detected in display state, log and reject instead of rendering them.

**Step 3: Manually verify with a corrupted local fixture if available**

---

### Task 9: Full Verification

**Files:**
- No new files unless gaps are found

**Step 1: Run targeted test suites**

Run:
- recovery scope tests
- display scope tests
- tracking/auth resume tests
- Live Activity reattachment tests
- journey finalizer tests

**Step 2: Run broader regression suite where practical**

Prioritize:
- `JourneyFinalizerTests`
- `JourneyMemory` / city cache related tests
- auth session tests

**Step 3: Manual scenario checklist**

Verify:
- same device with historical guest/account roots no longer pollutes current collection
- current user's own local guest journeys still appear
- current account journeys appear
- passive logout during tracking does not kill ongoing journey
- relogin restores the same ongoing journey
- Live Activity continues updating
- ending while logged out saves locally and prompts for login before publish

**Step 4: Commit**

Suggested commits:
- `test: lock recovery and tracking resume behavior`
- `fix: restrict automatic display recovery sources`
- `fix: persist ongoing tracking through passive logout`
- `fix: reattach live activity after auth recovery`

