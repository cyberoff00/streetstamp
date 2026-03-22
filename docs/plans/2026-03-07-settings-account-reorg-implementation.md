# Settings Account Reorg Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reorganize the Settings account area so account actions live in the account detail page, while keeping the root settings list visually consistent and localized.

**Architecture:** Keep the existing navigation and presentation helpers. Update `SettingsAccountPresentation` and `SettingsRowPresentation` first, then rewire the Settings root section to navigate into `AccountCenterView`, and finally tighten `AccountCenterView` logout UX with confirmation. Finish by adding localization keys to each shipped language file.

**Tech Stack:** SwiftUI, XCTest, `Localizable.strings`

---

### Task 1: Lock presentation changes with tests

**Files:**
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStampsTests/SettingsAccountPresentationTests.swift`
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStampsTests/SettingsRowPresentationTests.swift`

**Step 1: Write the failing tests**

- Expect logged-in account cards to show a chevron affordance.
- Expect root account actions to be empty for both guest and logged-in states.
- Expect profile visibility and map dark mode rows to use localized string keys.

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme StreetStamps -project StreetStamps.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:StreetStampsTests/SettingsAccountPresentationTests -only-testing:StreetStampsTests/SettingsRowPresentationTests`

Expected: FAIL on the old chevron/action/copy assertions.

**Step 3: Write minimal implementation**

- Update the presentation helpers in `SettingsView.swift`.

**Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command and expect PASS for both test classes.

### Task 2: Rewire Settings root account section

**Files:**
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/SettingsView.swift`

**Step 1: Implement the root section changes**

- Wrap the logged-in account card in a `NavigationLink` to `AccountCenterView`.
- Keep guest behavior unchanged.
- Remove the root profile visibility and logout rows.
- Change the logged-in nickname weight to non-bold.
- Center single-line toggle rows vertically in `toggleRowCard`.

**Step 2: Verify behavior**

- Ensure the file compiles cleanly and the tests from Task 1 stay green.

### Task 3: Update account detail behavior

**Files:**
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/AccountCenterView.swift`

**Step 1: Implement the detail-page actions**

- Keep profile visibility in the account detail page.
- Add a destructive logout row at the bottom of the detail view.
- Present a confirmation alert before calling `logoutToGuest()`.

**Step 2: Verify behavior**

- Confirm no duplicate logout/profile-visibility controls remain on the root settings page.

### Task 4: Add localization keys

**Files:**
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/en.lproj/Localizable.strings`
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/es.lproj/Localizable.strings`
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/fr.lproj/Localizable.strings`
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/ja.lproj/Localizable.strings`
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/ko.lproj/Localizable.strings`
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/zh-Hans.lproj/Localizable.strings`
- Modify: `/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/zh-Hant.lproj/Localizable.strings`

**Step 1: Add string keys**

- Add keys for the friends-only/private profile visibility labels.
- Add a key for the map dark mode label.
- Add keys for the account-center logout confirmation copy.

**Step 2: Verify behavior**

- Re-run the targeted tests and a project test/build pass.
