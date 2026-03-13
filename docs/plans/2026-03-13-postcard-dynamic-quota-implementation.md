# Postcard Dynamic Quota Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update postcard quota rules so each city starts at 2 postcards per friend and 10 unique friends, then unlocks +1 per-friend quota and +10 unique-friend quota for each additional journey in that city, with localized guidance telling users to start more journeys when they hit the limit.

**Architecture:** Keep quota enforcement centralized in the backend postcard rule helper, and pass the selected city's journey count from the iOS send flow to the API. Preserve existing error codes so only the quota math and user-facing copy change.

**Tech Stack:** Node.js backend rules/tests, SwiftUI client send flow, XCTest localization coverage

---

### Task 1: Lock the new quota behavior in tests

**Files:**
- Modify: `backend-node-v1/tests/postcard-rules.test.mjs`
- Modify: `backend-node-v1/tests/postcard-api.contract.mjs`
- Modify: `StreetStampsTests/PostcardSendErrorPresentationTests.swift`

**Step 1: Write the failing tests**

- Add a rules test showing a third postcard becomes allowed when `cityJourneyCount` is `2`.
- Add a rules test showing the 11th friend becomes allowed when `cityJourneyCount` is `2`.
- Add an API contract assertion that the third same-city postcard succeeds when the request includes `cityJourneyCount: 2`.
- Update the Swift presentation test to expect quota-full copy that mentions starting more journeys.

**Step 2: Run tests to verify they fail**

Run: `node --test backend-node-v1/tests/postcard-rules.test.mjs`
Expected: FAIL because the helper still hardcodes 2 / 10.

Run: `node backend-node-v1/tests/postcard-api.contract.mjs`
Expected: FAIL because the send endpoint still rejects the third postcard.

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/PostcardSendErrorPresentationTests`
Expected: FAIL because localized strings still use the old copy.

### Task 2: Implement dynamic quota calculation

**Files:**
- Modify: `backend-node-v1/postcard-rules.js`
- Modify: `backend-node-v1/server.js`

**Step 1: Add the new request input**

- Accept `cityJourneyCount` in the send endpoint payload.
- Normalize it to an integer with a minimum of `1`.

**Step 2: Update the quota helper**

- Compute:
  - `friendQuota = 2 + max(0, cityJourneyCount - 1)`
  - `cityQuota = 10 + max(0, cityJourneyCount - 1) * 10`
- Keep existing idempotency and `allowedCityIDs` behavior unchanged.

**Step 3: Re-run backend tests**

Run: `node --test backend-node-v1/tests/postcard-rules.test.mjs`
Expected: PASS

Run: `node backend-node-v1/tests/postcard-api.contract.mjs`
Expected: PASS

### Task 3: Pass journey count from the client and update copy

**Files:**
- Modify: `StreetStamps/PostcardComposerView.swift`
- Modify: `StreetStamps/PostcardPreviewView.swift`
- Modify: `StreetStamps/PostcardCenter.swift`
- Modify: `StreetStamps/PostcardModels.swift`
- Modify: `StreetStamps/en.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`

**Step 1: Thread the selected city's journey count through the send flow**

- Read the selected city's `journeyIds.count` from `cityCache.cachedCities`.
- Pass that count into `PostcardPreviewView`, then into `PostcardCenter`, then into `SendPostcardRequest`.

**Step 2: Update localized quota guidance**

- Keep the same keys.
- Mention that more journeys unlock more postcard quota.

**Step 3: Re-run Swift coverage**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/PostcardSendErrorPresentationTests`
Expected: PASS

### Task 4: Final verification

**Files:**
- No additional code changes expected

**Step 1: Run the targeted verification set**

Run: `node --test backend-node-v1/tests/postcard-rules.test.mjs`
Expected: PASS

Run: `node backend-node-v1/tests/postcard-api.contract.mjs`
Expected: PASS

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -only-testing:StreetStampsTests/PostcardSendErrorPresentationTests`
Expected: PASS
