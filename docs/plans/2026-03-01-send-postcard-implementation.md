# Send Postcard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build 1:1 friend postcard sending with Figma-based compose/preview UI, local draft queue, backend postcard message persistence, in-app notifications, and system-level local notification surfacing.

**Architecture:** Add a dedicated `postcard` domain on both iOS and Node backend. On iOS, a `PostcardCenter` owns draft state (`draft/sending/sent/failed`), upload/send orchestration, retry, and list loading for Sent/Received. On backend, implement postcard endpoints and validation (city eligibility, per-friend quota, per-city quota, idempotency), persist postcard messages under users, and emit `postcard_received` notification items.

**Tech Stack:** SwiftUI, async/await, UserDefaults draft persistence, existing `BackendAPIClient`, Node.js + Express (`backend-node-v1/server.js`), built-in `node:test`.

---

### Task 1: Backend postcard rule unit tests (quota + idempotency)

**Files:**
- Create: `backend-node-v1/postcard-rules.js`
- Create: `backend-node-v1/tests/postcard-rules.test.mjs`
- Modify: `backend-node-v1/package.json`

**Step 1: Write the failing test**

```js
// backend-node-v1/tests/postcard-rules.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { canSendPostcard } from '../postcard-rules.js';

test('rejects duplicate city->same friend', () => {
  const sent = [{ toUserID: 'u2', cityID: 'paris', status: 'sent' }];
  const result = canSendPostcard({
    sentPostcards: sent,
    toUserID: 'u2',
    cityID: 'paris',
    clientDraftID: 'd2'
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'city_friend_quota_exceeded');
});
```

**Step 2: Run test to verify it fails**

Run: `cd backend-node-v1 && node --test tests/postcard-rules.test.mjs`  
Expected: FAIL (`canSendPostcard` not found yet)

**Step 3: Write minimal implementation**

```js
// backend-node-v1/postcard-rules.js
export function canSendPostcard({ sentPostcards, toUserID, cityID, clientDraftID }) {
  // minimal pass version; expand in next task
  return { ok: true, reason: null, idempotentHit: null };
}
```

**Step 4: Run test to verify it passes/fails meaningfully**

Run: `cd backend-node-v1 && node --test tests/postcard-rules.test.mjs`  
Expected: FAIL with assertion mismatch (now testing real logic)

**Step 5: Commit**

```bash
git add backend-node-v1/postcard-rules.js backend-node-v1/tests/postcard-rules.test.mjs backend-node-v1/package.json
git commit -m "test: add postcard rule tests scaffold"
```

### Task 2: Implement backend postcard rule engine

**Files:**
- Modify: `backend-node-v1/postcard-rules.js`
- Modify: `backend-node-v1/tests/postcard-rules.test.mjs`

**Step 1: Write additional failing tests**

```js
// add cases:
// 1) same city total > 5 blocked
// 2) failed status does not count
// 3) same clientDraftID returns idempotentHit
// 4) city not in allowedCityIDs blocked
```

**Step 2: Run test to verify failures**

Run: `cd backend-node-v1 && node --test tests/postcard-rules.test.mjs`  
Expected: FAIL on new cases

**Step 3: Implement minimal passing logic**

```js
// implement:
// - city eligibility
// - city+friend uniqueness
// - city total <= 5 (sent only)
// - idempotent by clientDraftID
```

**Step 4: Run test to verify pass**

Run: `cd backend-node-v1 && node --test tests/postcard-rules.test.mjs`  
Expected: PASS

**Step 5: Commit**

```bash
git add backend-node-v1/postcard-rules.js backend-node-v1/tests/postcard-rules.test.mjs
git commit -m "feat: implement postcard quota and idempotency rules"
```

### Task 3: Backend API tests for send/list endpoints

**Files:**
- Create: `backend-node-v1/tests/postcard-api.test.mjs`
- Modify: `backend-node-v1/package.json`

**Step 1: Write failing API contract tests**

```js
// test endpoints:
// POST /v1/postcards/send
// GET  /v1/postcards?box=sent|received
// assert error codes: city_friend_quota_exceeded, city_total_quota_exceeded
```

**Step 2: Run test to verify it fails**

Run: `cd backend-node-v1 && node --test tests/postcard-api.test.mjs`  
Expected: FAIL (routes not implemented)

**Step 3: Add test script command**

```json
{
  "scripts": {
    "start": "node server.js",
    "test": "node --test tests/*.test.mjs"
  }
}
```

**Step 4: Re-run test to keep red**

Run: `cd backend-node-v1 && npm test`  
Expected: FAIL (still red before route implementation)

**Step 5: Commit**

```bash
git add backend-node-v1/tests/postcard-api.test.mjs backend-node-v1/package.json
git commit -m "test: add postcard API contract tests"
```

### Task 4: Implement backend postcard endpoints + notification emission

**Files:**
- Modify: `backend-node-v1/server.js`
- Modify: `backend-node-v1/postcard-rules.js`

**Step 1: Implement failing-first hooks in `server.js`**

```js
// add placeholders returning 501 for:
// POST /v1/postcards/send
// GET /v1/postcards
```

**Step 2: Run tests to verify expected fails change**

Run: `cd backend-node-v1 && npm test`  
Expected: FAIL with 501/shape mismatch (routes wired but incomplete)

**Step 3: Implement minimal passing backend**

```js
// server-side changes:
// - persist me.sentPostcards[] and target.receivedPostcards[]
// - create postcard message object:
//   { messageID, type:'postcard', fromUserID, toUserID, cityID, cityName, photoURL, messageText, sentAt, clientDraftID }
// - validate friend relationship
// - enforce quota via canSendPostcard
// - push notification item type='postcard_received'
// - cap notifications list length to 400 (existing pattern)
```

**Step 4: Run tests to verify pass**

Run: `cd backend-node-v1 && npm test`  
Expected: PASS

**Step 5: Commit**

```bash
git add backend-node-v1/server.js backend-node-v1/postcard-rules.js
git commit -m "feat: add postcard send/list APIs and notification emission"
```

### Task 5: Extend iOS API layer for postcard DTOs/endpoints

**Files:**
- Modify: `StreetStamps/BackendAPIClient.swift`
- Create: `StreetStamps/PostcardModels.swift`

**Step 1: Write failing compile references in a new model file**

```swift
// PostcardModels.swift
struct PostcardMessageDTO: Codable, Identifiable { ... }
struct SendPostcardRequest: Codable { ... }
```

**Step 2: Run build to verify red/compile errors**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: FAIL until API methods are added and wired

**Step 3: Implement API methods**

```swift
// BackendAPIClient additions:
func sendPostcard(token: String, req: SendPostcardRequest) async throws -> PostcardMessageDTO
func fetchPostcards(token: String, box: String, cursor: String?) async throws -> [PostcardMessageDTO]
```

**Step 4: Re-run build**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/BackendAPIClient.swift StreetStamps/PostcardModels.swift
git commit -m "feat: add postcard API client and DTO models"
```

### Task 6: Local draft persistence + send state machine

**Files:**
- Create: `StreetStamps/PostcardDraftStore.swift`
- Create: `StreetStamps/PostcardCenter.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`

**Step 1: Write failing logic checks (debug assertions in dedicated test harness)**

```swift
// create a small debug-only harness function in PostcardCenter.swift:
// assert transitions: draft -> sending -> sent / failed -> sending
```

**Step 2: Run build to keep red if symbols missing**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: FAIL until types are complete

**Step 3: Implement minimal store + center**

```swift
// PostcardDraftStore: UserDefaults-based save/load/replace by draftID
// PostcardCenter: createDraft, enqueueSend, retry, mergeSentReceived, status publishing
```

**Step 4: Re-run build**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/PostcardDraftStore.swift StreetStamps/PostcardCenter.swift StreetStamps/StreetStampsApp.swift
git commit -m "feat: add postcard draft persistence and send state machine"
```

### Task 7: Compose and preview UI from Figma nodes (150:84, 150:166)

**Files:**
- Create: `StreetStamps/PostcardComposerView.swift`
- Create: `StreetStamps/PostcardPreviewView.swift`
- Modify: `StreetStamps/FriendsHubView.swift`

**Step 1: Write failing navigation hook in friend profile**

```swift
// FriendProfileScreen: add menu tile/button to push PostcardComposerView(friendID: ...)
```

**Step 2: Run build to verify red until views exist**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: FAIL (new view unresolved)

**Step 3: Implement compose + preview minimal version**

```swift
// Compose:
// - city picker source = current city + unlocked cities
// - single local photo picker
// - 80-char text limit
// - disable send when quota/rules invalid
// Preview:
// - postcard front/back style per Figma
// - send action enqueues draft in PostcardCenter
```

**Step 4: Re-run build**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/FriendsHubView.swift StreetStamps/PostcardComposerView.swift StreetStamps/PostcardPreviewView.swift
git commit -m "feat: add postcard compose and preview flow from friend profile"
```

### Task 8: My Profile postcard entry + Sent/Received inbox

**Files:**
- Create: `StreetStamps/PostcardInboxView.swift`
- Modify: `StreetStamps/ProfileView.swift`

**Step 1: Write failing hook from profile action row**

```swift
// add postcard tile in topActionRow; tapping opens PostcardInboxView
```

**Step 2: Run build to confirm initial fail**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: FAIL before creating PostcardInboxView

**Step 3: Implement inbox view**

```swift
// segmented control: Sent / Received
// Sent includes local statuses: sending/sent/failed and Retry action
// Received shows postcard cards and detail navigation
```

**Step 4: Re-run build**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/ProfileView.swift StreetStamps/PostcardInboxView.swift
git commit -m "feat: add profile postcard inbox with sent/received tabs"
```

### Task 9: Notification rendering + local system notification surfacing

**Files:**
- Modify: `StreetStamps/ProfileView.swift`
- Modify: `StreetStamps/FriendsHubView.swift`
- Create: `StreetStamps/PostcardNotificationBridge.swift`
- Modify: `StreetStamps/BackendAPIClient.swift`

**Step 1: Write failing type handling**

```swift
// notification rows currently distinguish like/stomp only;
// add postcard_received branch to force compile updates
```

**Step 2: Run build (red)**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: FAIL until all switch/labels updated

**Step 3: Implement notification and local push bridge**

```swift
// UI:
// - show postcard_received title/subtitle and deep-link target
// local system notification:
// - request UN authorization once
// - when newly fetched unread postcard notifications appear, schedule local UNNotificationRequest
// - tap local notification deep-links into profile Postcards > Received detail
```

**Step 4: Re-run build**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/ProfileView.swift StreetStamps/FriendsHubView.swift StreetStamps/PostcardNotificationBridge.swift StreetStamps/BackendAPIClient.swift
git commit -m "feat: support postcard notifications and local system alerts"
```

### Task 10: Localization, copy, and acceptance verification

**Files:**
- Modify: `StreetStamps/zh-Hans.lproj/Localizable.strings`
- Optional create: `docs/plans/2026-03-01-send-postcard-qa-checklist.md`

**Step 1: Add failing placeholders in UI for untranslated keys**

```swift
// replace hard-coded postcard strings with L10n.t("...") keys before adding translations
```

**Step 2: Run build and app smoke checks**

Run: `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`  
Expected: PASS build, manual QA likely FAIL before copy finalized

**Step 3: Fill localization and finalize copy**

```text
// keys for: send entry, compose labels, preview, quota errors, sent/received statuses, retry, notifications
```

**Step 4: Execute end-to-end verification checklist**

Run:
1. `cd backend-node-v1 && npm test`
2. `xcodebuild -project StreetStamps.xcodeproj -scheme StreetStamps -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' build`
3. Manual checks:
   - Friend profile has Send Postcard entry
   - Compose enforces 1 photo + 80 chars
   - City filtering works (`current + unlocked`)
   - Duplicate same-city-to-same-friend blocked
   - Same-city total over 5 blocked
   - Send creates sending/sent/failed statuses and retry
   - Receiver gets in-app notification + local system notification
   - Profile Postcards shows Sent/Received correctly

Expected: PASS

**Step 5: Commit**

```bash
git add StreetStamps/zh-Hans.lproj/Localizable.strings docs/plans/2026-03-01-send-postcard-qa-checklist.md
git commit -m "chore: finalize postcard localization and QA checklist"
```

## Notes / Constraints

- “系统推送”在当前工程中无现成 APNs/FCM 服务端链路。本计划先交付“系统级本地通知”触达（依赖拉取到新通知后触发），并保持通知数据结构可扩展到远程推送。
- Quota and idempotency are server-authoritative; client-side checks are UX pre-check only.
- Retry reuses `clientDraftID` and must not increase quota counts.
