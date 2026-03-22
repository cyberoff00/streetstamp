# Firebase Auth Setup Notes

Date: 2026-03-07
Status: Draft
Owner: Codex + liuyang

## Required Inputs

### iOS app

- `GoogleService-Info.plist` must be present in the app target resources.
- The Firebase iOS app `BUNDLE_ID` inside `GoogleService-Info.plist` must match the app bundle identifier.
- `GOOGLE_IOS_CLIENT_ID` in `Info.plist` must match the Firebase / Google Sign-In configuration used by the same project.
- `API_BASE_URL` must point at a backend that trusts Firebase ID tokens.

### Backend

- `FIREBASE_PROJECT_ID`
- one of:
  - `GOOGLE_APPLICATION_CREDENTIALS` pointing at a Firebase service-account JSON file
  - `FIREBASE_SERVICE_ACCOUNT_JSON` containing the service-account JSON payload
- `FIREBASE_AUTH_ENABLED=1` when Firebase token verification is intended to be active
- `FIREBASE_LEGACY_EMAIL` defaulting to `yinterestingy@gmail.com`
- `FIREBASE_LEGACY_APP_USER_ID` pointing at the preserved legacy business account

## Current Fail-Fast Expectations

- The iOS app should surface a clear setup issue when Firebase resources or bundle alignment are missing.
- The backend should refuse to enable Firebase auth if `FIREBASE_PROJECT_ID`, credentials, or preserved-account settings are absent.
- The backend must not silently fall back to custom auth once Firebase auth is enabled.

## Operator Notes

- Firebase email verification and password reset depend on console-side email template setup.
- Google and Apple providers must be enabled in the same Firebase project referenced by `GoogleService-Info.plist`.
- The preserved legacy account migration is intentionally scoped to `yinterestingy@gmail.com`; no bulk legacy import is part of this rollout.
