# Postcard Quota Localized Errors Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update postcard send quota rules to 2 per friend per city and 10 per city total, and surface localized product-quality quota errors in iOS.

**Architecture:** Keep backend quota enforcement and structured error codes as the source of truth. Add an iOS mapping layer that converts backend postcard send failures into localized, user-facing messages without weakening existing generic error handling.

**Tech Stack:** Node.js backend, Swift iOS app, XCTest, node:test, localized `.strings`

---

### Task 1: Lock backend quota behavior with failing tests

**Files:**
- Modify: `backend-node-v1/tests/postcard-rules.test.mjs`
- Modify: `backend-node-v1/tests/postcard-api.contract.mjs`

**Step 1: Write the failing tests**

- Update rule tests to allow a second postcard to the same friend/city and reject the third.
- Update city total tests to allow 10 postcards from the same city and reject the 11th.
- Update API contract to verify the third send to the same friend/city returns `city_friend_quota_exceeded`.

**Step 2: Run test to verify it fails**

Run: `node --test backend-node-v1/tests/postcard-rules.test.mjs`
Expected: FAIL because rules still enforce `1 / 5`.

**Step 3: Write minimal implementation**

- Change backend quota thresholds in `backend-node-v1/postcard-rules.js`.

**Step 4: Run test to verify it passes**

Run: `node --test backend-node-v1/tests/postcard-rules.test.mjs`
Expected: PASS.

### Task 2: Preserve backend error codes for frontend mapping

**Files:**
- Modify: `backend-node-v1/server.js`

**Step 1: Write the failing expectation**

- Ensure the send endpoint returns both `code` and a stable backend `message` for quota failures.

**Step 2: Run targeted contract test**

Run: `node backend-node-v1/tests/postcard-api.contract.mjs`
Expected: FAIL if message/code contract does not match updated behavior.

**Step 3: Write minimal implementation**

- Return specific messages for `city_friend_quota_exceeded` and `city_total_quota_exceeded`.

**Step 4: Re-run contract test**

Run: `node backend-node-v1/tests/postcard-api.contract.mjs`
Expected: PASS.

### Task 3: Add iOS postcard send error mapping with failing tests

**Files:**
- Create: `StreetStampsTests/PostcardSendErrorPresentationTests.swift`
- Modify: `StreetStamps/BackendAPIClient.swift`
- Modify: `StreetStamps/PostcardCenter.swift`

**Step 1: Write the failing tests**

- Verify backend postcard quota codes map to localized Chinese/English product copy.
- Verify unknown postcard errors still fall back to existing generic send failure.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardSendErrorPresentationTests`
Expected: FAIL before the mapping exists.

**Step 3: Write minimal implementation**

- Extend backend error parsing to preserve postcard send error code.
- Add a small presentation mapper used by `PostcardCenter` when send fails.

**Step 4: Run test to verify it passes**

Run: same `xcodebuild` command.
Expected: PASS.

### Task 4: Add bilingual localized strings

**Files:**
- Modify: `StreetStamps/en.lproj/Localizable.strings`
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`
- Modify: `StreetStampsTests/LocalizationCoverageTests.swift`

**Step 1: Write the failing localization coverage update**

- Add required postcard quota keys to coverage assertions.

**Step 2: Run targeted localization test**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/LocalizationCoverageTests`
Expected: FAIL until both locales contain the keys.

**Step 3: Write minimal implementation**

- Add English and Simplified Chinese strings for friend quota exceeded, city total exceeded, and generic fallback if needed.

**Step 4: Re-run localization test**

Run: same `xcodebuild` command.
Expected: PASS.
