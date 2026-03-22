# Motion And Passive Power Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce idle battery use by running MotionActivity only when tracking or passive lifelog needs it, and make passive lifelog switch to a truly lower-power stationary profile.

**Architecture:** Add small policy/value types that decide when motion updates should run and which passive location profile should apply for moving vs stationary states. Wire those policies into the existing lifecycle code so the app keeps the current behavior goals while lowering always-on work.

**Tech Stack:** Swift, SwiftUI, CoreLocation, CoreMotion, XCTest

---

### Task 1: Lock the desired policy in tests

**Files:**
- Modify: `StreetStampsTests/PassiveLocationProfileTests.swift`
- Create: `StreetStampsTests/MotionActivityPolicyTests.swift`

**Steps:**
1. Add a failing test for distinct passive profiles in moving vs stationary states.
2. Add a failing test for motion activity policy when passive lifelog or journey tracking is active.
3. Run the focused tests and confirm they fail for the expected missing behavior.

### Task 2: Implement the policy types

**Files:**
- Modify: `StreetStamps/LocationLifecycleDecision.swift`
- Modify: `StreetStamps/MotionActivityFusion.swift`

**Steps:**
1. Add passive state-aware location profiles.
2. Add a motion activity run policy plus an explicit start/stop control path in the hub.
3. Keep the API small so existing call sites only need minimal changes.

### Task 3: Wire policies into runtime behavior

**Files:**
- Modify: `StreetStamps/SystemLocationSource.swift`
- Modify: `StreetStamps/StreetStampsApp.swift`
- Modify: `StreetStamps/TrackingService.swift`

**Steps:**
1. Apply the new stationary/moving passive profiles when passive state changes.
2. Start motion updates when passive lifelog or journey tracking becomes active.
3. Stop motion updates when both are inactive.

### Task 4: Verify

**Files:**
- Test: `StreetStampsTests/PassiveLocationProfileTests.swift`
- Test: `StreetStampsTests/MotionActivityPolicyTests.swift`

**Steps:**
1. Run focused tests for the new policy coverage.
2. Run a broader regression slice around lifecycle/location behavior if available.
