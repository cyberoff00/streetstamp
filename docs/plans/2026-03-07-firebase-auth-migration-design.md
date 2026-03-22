# Firebase Auth Migration Design

Date: 2026-03-07
Status: Approved
Owner: Codex + liuyang

## Background

`StreetStamps` currently uses a custom auth backend for:

- email/password registration and login
- Google / Apple OAuth token exchange
- backend-issued access / refresh tokens
- guest-to-account migration bookkeeping

This leaves several product gaps:

- email verification is not enforced
- forgot-password and reset-password flows do not exist
- account security remains tied to custom token and password handling
- guest behavior is mixed with account migration paths even though guest content should stay local-only

The approved product direction is:

- move authentication to Firebase Auth
- keep business data in the existing backend
- support Firebase email/password with Firebase email-link verification
- keep Google Sign-In and Sign in with Apple
- preserve exactly one historical cloud account: `yinterestingy@gmail.com`
- keep `guest` mode local-only and never upload guest content

## Goal

Build a minimal Firebase-based auth architecture that:

- supports email/password sign-up, sign-in, email verification, password reset, Google, and Apple
- uses Firebase as the only auth source of truth
- lets the existing backend trust Firebase ID tokens instead of custom auth tokens
- preserves the old business account behind `yinterestingy@gmail.com`
- keeps guest mode fully local and isolated from cloud account state

## Non-Goals

- no migration of every historical backend account
- no Firebase Anonymous Auth
- no email one-time-code entry flow; verification and password reset use Firebase email links
- no rewrite of business-domain APIs outside auth/session boundaries
- no guest-content upload, merge, or cloud backup

## Existing Constraints

### 1. Guest Is a First-Class Local Mode

The current session model explicitly distinguishes `guest` and `account` sessions, and guest data is stored under guest-scoped local identifiers. This is worth preserving because the approved product behavior is "guest stays local-only."

### 2. Current Account Login Triggers Guest Recovery

The current auth apply path archives guest content into the account-scoped local area when the user logs into an account. That behavior conflicts with the new requirement and must be removed or gated off for the Firebase migration.

### 3. Backend Owns Business Identity Today

The backend currently returns custom auth payloads and business user IDs. Firebase migration should not force a full business data rewrite. Instead, business identity should remain backend-owned and be mapped from Firebase identity.

### 4. OAuth Paths Already Exist in UI

Google and Apple entry points already exist in the app. Migration should reuse those UI entry points while replacing the identity source and downstream token model.

## Proposed Architecture

### 1. Firebase Becomes the Only Authentication Provider

All user-facing authentication flows move to Firebase Auth:

- email/password register
- email/password sign-in
- send email verification
- send password reset email
- Google sign-in
- Apple sign-in

The iOS app stops calling custom backend auth routes for sign-in. Instead:

1. authenticate with Firebase
2. obtain Firebase ID token from the signed-in Firebase user
3. send that ID token to backend business APIs

The backend no longer issues first-party auth tokens for the app.

### 2. Backend Keeps Business User IDs

The backend continues to own business user records and business-scoped IDs. Add a durable identity mapping layer:

- `firebaseUid -> appUserId`
- optional denormalized fields such as `email`, `providers`, `emailVerified`

This keeps the current data model stable:

- journeys
- social graph
- postcards
- profile state

All continue to belong to `appUserId`, not to Firebase UID directly.

### 3. One-Time Targeted Historical Account Preservation

Only one historical business account needs to survive: the old cloud account tied to `yinterestingy@gmail.com`.

Migration rule:

- on first backend-authenticated request with a Firebase token whose normalized email is `yinterestingy@gmail.com`
- if no mapping exists yet for that Firebase UID
- bind that Firebase UID to the pre-existing business account instead of creating a new one

After that first bind, all future requests from that Firebase user resolve to the same historical `appUserId`.

No bulk import of legacy auth users is required.

### 4. Guest Remains Local-Only

`guest` should remain a local session mode with no Firebase user and no cloud writes. The app must not:

- silently convert guest into Firebase anonymous auth
- auto-upload guest content on account sign-in
- auto-merge guest data into cloud account data

Allowed behavior:

- guest keeps using local guest-scoped storage
- account login switches the UI session to an authenticated cloud-capable user
- guest local content stays on-device unless a future feature explicitly exports it

### 5. Backend Auth Contract Simplification

Current custom routes can be phased out:

- `/v1/auth/email/register`
- `/v1/auth/email/login`
- `/v1/auth/oauth`
- `/v1/auth/refresh`

Replacement:

- backend accepts `Authorization: Bearer <firebase-id-token>`
- backend middleware verifies the Firebase token
- middleware resolves or creates `appUserId`
- request context uses the resolved business user

This sharply reduces backend responsibility for passwords, OAuth token exchange, and refresh token lifecycle.

## Data Model Changes

Add backend identity mapping storage with at least:

- `firebaseUid`
- `appUserId`
- `email`
- `emailVerified`
- `providers`
- `createdAt`
- `lastLoginAt`

For the single preserved historical account, add a deterministic migration hook:

- configured legacy email: `yinterestingy@gmail.com`
- configured legacy `appUserId` or lookup path to discover it

If the current backend remains file-backed in development, this can start as an in-file mapping structure. If production uses Postgres, the same shape should become a table.

## iOS Design

### 1. Session Model

Replace custom backend tokens in the app session with:

- `guest(guestID:)`
- `account(appUserId:, firebaseUid:, provider:, email:, emailVerified:)`

The app should not persist backend refresh tokens because Firebase handles user session refresh internally.

### 2. Auth Entry Flows

`AuthEntryView` becomes a Firebase client:

- email register creates Firebase user
- app sends verification email
- sign-in checks `isEmailVerified`
- forgot password sends Firebase reset email
- Google and Apple sign-in create or reuse Firebase users

Recommended UX:

- if email/password registration succeeds but email is unverified, show a verification-required state instead of treating the user as fully ready
- allow resend verification email
- when an already-signed-in Firebase user becomes verified, refresh local auth state

### 3. Backend API Client

`BackendAPIClient` should request the current Firebase ID token for authenticated requests and attach it as the bearer token. Token refresh becomes Firebase SDK responsibility rather than custom refresh endpoint logic.

### 4. Guest Boundary

When switching from guest to account:

- keep guest files in guest-scoped local storage
- do not call guest recovery upload or account archiving paths
- do not treat guest as pending cloud migration

## Backend Design

### 1. Firebase Token Verification Middleware

Use Firebase Admin SDK in the backend to:

- verify bearer ID token
- extract `uid`, `email`, `email_verified`, and provider data
- resolve `appUserId` via identity mapping

### 2. Resolve-Or-Create Business User

Backend auth middleware behavior:

1. verify Firebase token
2. if mapping exists for `firebaseUid`, use mapped `appUserId`
3. else if email is `yinterestingy@gmail.com`, attach the known historical account
4. else create a new business user and mapping
5. attach business user context to request

### 3. Legacy Account Preservation

Do not attempt password migration. The preserved account is restored by email/provider identity match through Firebase, not by reusing old custom auth credentials.

## Error Handling

### iOS

- unverified email: block cloud sign-in state and show resend-verification affordance
- password reset email sent: always show generic success copy
- Firebase auth failures: map to localized user-facing messages
- backend rejects verified Firebase token: treat as configuration or migration error and surface a generic retryable message

### Backend

- invalid or expired Firebase token: return `401`
- verified Firebase token but failed mapping lookup/create: return `500`
- migration email matched but legacy business user missing: return `500` with operator-visible logs

## Testing Strategy

### iOS

Add focused tests around:

- session state transition between guest and Firebase account
- guest login no longer setting pending guest cloud migration
- backend request auth header sourcing Firebase token provider
- auth UI state for unverified email

### Backend

Add focused tests around:

- verified Firebase token creates new mapping and business user
- repeated Firebase token reuse resolves same business user
- `yinterestingy@gmail.com` binds to the preserved historical account
- guest-only flows remain unauthenticated and local-only

## Risks

- if the preserved historical account ID is misidentified, `yinterestingy@gmail.com` could be bound to the wrong business user
- if guest migration code is only partially removed, account sign-in could still archive or upload guest data
- if backend routes accept both old custom tokens and Firebase tokens indefinitely, auth complexity will linger and regressions will hide

## Rollout

1. enable Firebase providers in a test project
2. ship backend Firebase verification behind configuration
3. migrate iOS auth UI to Firebase flows
4. verify first login with `yinterestingy@gmail.com` binds to the correct existing business account
5. remove or disable old custom auth routes once the Firebase path is stable
