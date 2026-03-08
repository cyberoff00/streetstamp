# Password Reset Deep Link Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship an end-to-end password reset flow where reset emails open the StreetStamps app with a token and let the user set a new password in-app.

**Architecture:** The backend keeps issuing and validating password reset tokens exactly as it does now, but changes the outbound email link to the `streetstamps://` custom URL scheme. The iOS app extends app-level deep-link parsing to capture reset-password intents, surfaces a reset form from the auth flow, and submits the existing backend reset endpoint with the token and new password.

**Tech Stack:** Node.js/Express backend, SwiftUI iOS app, existing contract tests, existing Swift unit test target

---

### Task 1: Change password reset email links to the app scheme

**Files:**
- Modify: `backend-node-v1/tests/auth-password-reset.contract.mjs`
- Modify: `backend-node-v1/server.js`

**Step 1: Write the failing test**

Change the contract test so it asserts the reset email URL starts with:

```js
assert.equal(resetMail.resetURL.startsWith("streetstamps://reset-password?token="), true);
```

and still extracts the token from the URL for the reset request.

**Step 2: Run test to verify it fails**

Run:

```bash
node backend-node-v1/tests/auth-password-reset.contract.mjs
```

Expected:

- FAIL because the emitted URL still starts with `http://` or `https://`

**Step 3: Write minimal implementation**

Change `deliverPasswordResetEmail()` in `backend-node-v1/server.js` to build:

```js
const resetURL = `streetstamps://reset-password?token=${encodeURIComponent(token)}`;
```

Leave verification-email behavior unchanged.

**Step 4: Run test to verify it passes**

Run:

```bash
node backend-node-v1/tests/auth-password-reset.contract.mjs
```

Expected:

- PASS

**Step 5: Commit**

```bash
git add backend-node-v1/tests/auth-password-reset.contract.mjs backend-node-v1/server.js
git commit -m "feat: use app deep links for password reset emails"
```

### Task 2: Parse password reset deep links at the app level

**Files:**
- Modify: `StreetStamps/AppFlowCoordinator.swift`
- Test: `StreetStampsTests` new or existing deep-link parsing test file

**Step 1: Write the failing test**

Add a Swift unit test that verifies:

```swift
func testHandleIncomingURLStoresPendingPasswordResetToken() {
    let store = AppDeepLinkStore()
    let handled = store.handleIncomingURL(URL(string: "streetstamps://reset-password?token=abc123")!)
    XCTAssertTrue(handled)
    XCTAssertEqual(store.pendingPasswordResetToken, "abc123")
}
```

Add a second test for an empty token URL:

```swift
func testHandleIncomingURLIgnoresPasswordResetWithoutToken() {
    let store = AppDeepLinkStore()
    let handled = store.handleIncomingURL(URL(string: "streetstamps://reset-password?token=")!)
    XCTAssertFalse(handled)
    XCTAssertNil(store.pendingPasswordResetToken)
}
```

**Step 2: Run test to verify it fails**

Run the narrowest available Xcode test command for the new test target/file.

Expected:

- FAIL because `AppDeepLinkStore` does not yet expose password reset intent handling

**Step 3: Write minimal implementation**

In `StreetStamps/AppFlowCoordinator.swift`:

- Add `@Published private(set) var pendingPasswordResetToken: String?`
- Extend `handleIncomingURL(_:)` to parse `streetstamps://reset-password?token=...`
- Add a `consumePendingPasswordResetToken()` helper

**Step 4: Run test to verify it passes**

Run the same narrow test command.

Expected:

- PASS

**Step 5: Commit**

```bash
git add StreetStamps/AppFlowCoordinator.swift StreetStampsTests
git commit -m "feat: parse password reset deep links"
```

### Task 3: Add backend client support for completing password reset

**Files:**
- Modify: `StreetStamps/BackendAPIClient.swift`

**Step 1: Write the failing test**

If an existing API client test target is available, add a focused test for:

```swift
resetPassword(token:newPassword:)
```

that verifies it encodes:

```json
{ "token": "abc123", "newPassword": "Changed1!" }
```

If no practical client unit harness exists, document that this task is covered by the UI/state test in Task 4 plus manual verification against the backend contract.

**Step 2: Run test to verify it fails**

Run the narrowest relevant test command if a harness exists.

Expected:

- FAIL because `BackendAPIClient` does not yet expose a reset-password method

**Step 3: Write minimal implementation**

Add:

```swift
func resetPassword(token: String, newPassword: String) async throws
```

that POSTs to `/v1/auth/reset-password`.

**Step 4: Run test to verify it passes**

Run the same test command if a harness exists.

Expected:

- PASS, or document no isolated harness and rely on later verification

**Step 5: Commit**

```bash
git add StreetStamps/BackendAPIClient.swift
git commit -m "feat: add backend password reset client"
```

### Task 4: Present and submit the reset-password form in auth UI

**Files:**
- Modify: `StreetStamps/AuthEntryView.swift`
- Modify: `StreetStamps/Usersessionstore.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Test: `StreetStampsTests` auth presentation/state test file if feasible

**Step 1: Write the failing test**

Prefer a focused presentation/state test that verifies:

- a pending password reset token causes auth UI reset mode to appear
- submitting matching passwords calls the session-store reset path
- successful submission clears reset mode

If a full SwiftUI view test is too expensive, write a smaller state-oriented test around the deep-link store and session store integration, then document manual UI verification steps.

**Step 2: Run test to verify it fails**

Run the narrowest relevant test command.

Expected:

- FAIL because the auth flow has no reset-password mode

**Step 3: Write minimal implementation**

Implement:

- `UserSessionStore.resetPassword(token:newPassword:)`
- Auth-entry state for:
  - reset token
  - new password
  - confirm password
- validation for:
  - non-empty token
  - matching passwords
- success path:
  - submit reset request
  - clear pending token
  - show completion message
  - return to sign-in mode
- `StreetStampsApp` behavior that opens the auth flow when a password reset deep link arrives

**Step 4: Run test to verify it passes**

Run the same relevant tests.

Expected:

- PASS

**Step 5: Commit**

```bash
git add StreetStamps/AuthEntryView.swift StreetStamps/Usersessionstore.swift StreetStamps/StreetStampsApp.swift StreetStampsTests
git commit -m "feat: support in-app password reset from deep links"
```

### Task 5: Verify the full flow end to end

**Files:**
- No code changes required unless a verification failure reveals a bug

**Step 1: Run backend contract test**

Run:

```bash
node backend-node-v1/tests/auth-password-reset.contract.mjs
```

Expected:

- PASS

**Step 2: Run targeted iOS tests**

Run the exact Xcode test command(s) used for deep-link and auth-flow coverage.

Expected:

- PASS

**Step 3: Manual sanity check**

Verify on device or simulator:

1. Request password reset for a known email.
2. Confirm the email link uses `streetstamps://reset-password?token=...`.
3. Open the link.
4. Confirm the app opens into the reset-password flow.
5. Enter a valid new password and submit.
6. Confirm sign-in succeeds with the new password and fails with the old password.

**Step 4: Commit any verification-driven fixes**

If verification required code changes:

```bash
git add <fixed files>
git commit -m "fix: complete password reset deep link flow"
```
