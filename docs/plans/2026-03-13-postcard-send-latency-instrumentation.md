# Postcard Send Latency Instrumentation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add lightweight diagnostics so we can see where postcard sending time is spent across client photo preparation, media upload, postcard send, and server persistence.

**Architecture:** Keep the existing send flow unchanged and layer timing capture around the existing boundaries. Expose client-side timing as testable state for development diagnostics, and emit server-side structured logs for `/v1/media/upload` and `/v1/postcards/send`.

**Tech Stack:** Swift, XCTest, Node.js, Express

---

### Task 1: Client Diagnostics Model

**Files:**
- Modify: `StreetStamps/PostcardCenter.swift`
- Test: `StreetStampsTests/PostcardSendFlowPerformanceTests.swift`

**Step 1: Write the failing test**

Add a test that sends a postcard through the existing mocked transport and asserts the draft stores non-zero timing values for upload and send phases.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardSendFlowPerformanceTests`

Expected: FAIL because no timing diagnostics are stored yet.

**Step 3: Write minimal implementation**

Add a small diagnostics payload to postcard drafts and populate it inside `enqueueSend`.

**Step 4: Run test to verify it passes**

Run the same focused test command and confirm the new assertion passes.

### Task 2: Client Logging

**Files:**
- Modify: `StreetStamps/PostcardCenter.swift`

**Step 1: Write the failing test**

Extend the same test to assert total elapsed timing is captured and stable after send completes.

**Step 2: Run test to verify it fails**

Run the focused postcard performance test target and confirm the new assertion fails.

**Step 3: Write minimal implementation**

Capture total send latency and emit a concise debug log with the phase breakdown.

**Step 4: Run test to verify it passes**

Run the focused test command and confirm the timing assertions pass.

### Task 3: Server Timing Logs

**Files:**
- Modify: `backend-node-v1/server.js`

**Step 1: Write the implementation**

Wrap `/v1/media/upload` and `/v1/postcards/send` with request timers and log phase totals, including save duration and upload backend.

**Step 2: Verify behavior**

Run: `node --test tests/postcard-rules.test.mjs tests/security-hardening.test.mjs`

Expected: PASS with no regression from timing instrumentation.

### Task 4: Final Verification

**Files:**
- Modify: none

**Step 1: Run focused client verification**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/PostcardSendFlowPerformanceTests`

**Step 2: Run focused server verification**

Run: `node --test tests/postcard-rules.test.mjs tests/security-hardening.test.mjs`

**Step 3: Summarize evidence**

Report which phase timings are now observable and any remaining blind spots.
