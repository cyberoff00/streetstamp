# Self-Hosted Auth Replacement Design

Date: 2026-03-07
Status: Approved
Owner: Codex + liuyang

## Background

`StreetStamps` currently has an in-progress Firebase Auth migration intended to replace the legacy custom auth backend. That direction conflicts with a new product constraint:

- the production API should be hosted overseas
- mainland China users should be able to register, sign in, and use the app without VPN
- global users should experience one consistent backend and user model

Live investigation on the existing `cn-shanghai` ECS showed that Google/Firebase endpoints such as `oauth2.googleapis.com` and `www.googleapis.com` time out even though general outbound HTTPS works. That makes Firebase an unreliable primary auth dependency for mainland-accessible production traffic.

The approved product direction is now:

- replace Firebase as the primary auth source with backend-owned authentication
- keep Firebase configuration and data as backup/reference only
- remove Google sign-in
- keep Apple sign-in, but route it directly into backend-owned identity records
- use Amazon SES for email verification and password reset mail
- require strong password rules for email/password accounts
- treat Apple hidden-email accounts as separate accounts unless the user explicitly binds them later

## Goal

Build a backend-owned authentication system that:

- supports email/password registration, verification, login, refresh, forgot password, and password reset
- supports Sign in with Apple through backend-owned OAuth identity handling
- works from overseas hosting while remaining usable from mainland China without VPN
- keeps one global user system and one global backend deployment
- preserves existing Firebase data as historical backup without depending on Firebase at runtime

## Non-Goals

- no Google sign-in in the new production auth model
- no automatic Apple hidden-email to self-hosted email account merge
- no immediate deletion of Firebase configuration, project, or stored auth users
- no split domestic/overseas backend topology in v1
- no bulk migration of every Firebase user into a new password credential

## Product Constraints

### 1. One Global Backend

The backend should be deployed in one overseas region and serve all users. China access improvements should come from network choice, CDN, and protocol design rather than running a separate domestic auth stack.

### 2. Mainland-Compatible Auth Chain

The primary login chain must not depend on Google-reachable backend services at runtime. Email auth and Apple auth must be verifiable by the backend without calling Firebase Admin or Google identity endpoints during normal request handling.

### 3. Backend Owns Identity

The backend should become the source of truth for:

- user IDs
- sessions
- identity binding
- account merge rules
- verification state
- password reset lifecycle

Third-party providers should only prove identity, not own the product account model.

### 4. Firebase Is Retained as Backup

Firebase should remain configured for reference and potential future migration work, but production login and request authorization should no longer depend on it. Existing Firebase metadata may still be useful for audit, rollback planning, or future import jobs.

## Proposed Architecture

### 1. Backend-Owned Auth Model

The backend becomes the only production auth authority. The app should stop sending Firebase ID tokens to business APIs. Instead:

1. the user signs in through backend-owned email/password or Apple auth
2. the backend returns backend-issued access and refresh tokens
3. all business API requests use those backend tokens

This restores the old operational model of backend-owned sessions while replacing the previous weak email/password handling with a stricter, modernized implementation.

### 2. Identity Separation from User Profile

User profile data should remain in the business user model, while login mechanisms move into a dedicated identity model. One user can have multiple identities, such as:

- one `email_password` identity
- one `apple` identity

That separation makes merge rules explicit and prevents product profile state from being overloaded with auth concerns.

### 3. Email/Password via SES Verification

Email auth should use:

- strong password validation at registration and reset time
- `argon2id` password hashing
- SES verification emails
- SES password reset emails
- explicit email verification state in the backend database

Unverified email accounts should not receive full app sessions.

### 4. Apple as OAuth Identity Provider

Apple login should be treated as an external identity source, not as the main user record. The backend should verify Apple identity tokens and bind the stable Apple `sub` value to an internal user.

Merge rule:

- if Apple returns a real email and it matches an existing verified self-hosted email identity, the backend may merge into that account
- if Apple returns a private relay or hidden email, do not auto-merge

That keeps hidden-email sign-ins safe and avoids accidentally joining unrelated accounts.

### 5. Firebase Retention Strategy

Keep the Firebase project, iOS configuration, and historical auth records for reference. Production behavior should change as follows:

- no Firebase email/password auth in app login flows
- no Firebase token verification in backend request middleware
- no Firebase dependency for Apple sign-in completion
- optional future maintenance scripts may still read Firebase data out of band

## Data Model

### 1. `users`

Backend-owned product users.

Suggested fields:

- `id`
- `display_name`
- `handle`
- `status`
- `created_at`
- `last_login_at`

### 2. `auth_identities`

Stores login identities attached to users.

Suggested fields:

- `id`
- `user_id`
- `provider`
- `provider_subject`
- `email`
- `email_verified`
- `password_hash`
- `created_at`
- `updated_at`

Provider values in v1:

- `email_password`
- `apple`

Rules:

- `provider_subject` for email accounts can use normalized email
- `provider_subject` for Apple accounts must use the stable Apple `sub`
- `password_hash` is only populated for `email_password`

### 3. `email_verification_tokens`

Suggested fields:

- `id`
- `user_id`
- `email`
- `token_hash`
- `expires_at`
- `used_at`
- `created_at`

### 4. `password_reset_tokens`

Suggested fields:

- `id`
- `user_id`
- `email`
- `token_hash`
- `expires_at`
- `used_at`
- `created_at`

### 5. `refresh_tokens`

Suggested fields:

- `id`
- `user_id`
- `token_hash`
- `device_info`
- `expires_at`
- `revoked_at`
- `created_at`

## Password and Verification Rules

### 1. Password Policy

Approved minimum policy:

- at least 8 characters
- must include at least 1 letter
- must include at least 1 number
- must include at least 1 special character

Recommended additional restrictions:

- trim leading and trailing whitespace
- maximum length cap such as 72 or 128 characters
- reject very common weak passwords

### 2. Registration Flow

1. client submits email, password, and display name
2. backend validates password policy and normalized email
3. backend creates `users` and `auth_identities`
4. backend creates verification token
5. backend sends SES verification email
6. account remains unverified until link completion

### 3. Verification Flow

1. user taps email verification link
2. backend validates token and expiry
3. backend marks the email identity as verified
4. token becomes single-use

### 4. Password Reset Flow

1. user submits email
2. backend returns a generic success message regardless of account existence
3. if the account exists, backend issues reset token and sends SES mail
4. user submits new password with reset token
5. backend updates the password hash
6. backend revokes existing refresh tokens

## Apple Account Rules

### 1. Existing Apple Identity

If the Apple `sub` already exists in `auth_identities`, sign in to the attached user.

### 2. First-Time Apple Identity with Real Email

If Apple returns a real email and it matches an existing verified `email_password` identity:

- merge into the existing user
- create a new `apple` identity row bound to that same `user_id`

### 3. First-Time Apple Identity with Hidden Email

Do not auto-merge. Create a separate user and `apple` identity row.

This rule was explicitly approved to avoid unsafe merges caused by Apple private relay addresses.

## API Design

Recommended minimum auth endpoints:

- `POST /v1/auth/register`
- `POST /v1/auth/verify-email`
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `POST /v1/auth/forgot-password`
- `POST /v1/auth/reset-password`
- `POST /v1/auth/apple`
- `POST /v1/auth/logout`

The app should only use backend-issued access and refresh tokens after these flows succeed.

## iOS App Design

### 1. Remove Firebase from Primary Login Flow

`AuthEntryView`, `FirebaseEmailAuthService`, and the Firebase-backed account completion path should be replaced or bypassed for production login.

The app should:

- call backend register/login/reset endpoints for email auth
- open backend email verification links
- call backend Apple auth exchange instead of signing Apple credentials into Firebase

### 2. Session Model

The app session should return to a backend-token model:

- `guest(guestID:)`
- `account(userID:, provider:, email:, accessToken:, refreshToken:, guestID:)`

Guest behavior should remain local-only.

### 3. UI Behavior

The app should still support:

- register
- sign in
- forgot password
- email verification instructions
- Apple sign in

But the backing logic should no longer depend on Firebase runtime state.

## Backend Hosting Recommendation for 1000 DAU

For global consistency with mainland usability:

- deploy the core API in one overseas region, preferably Singapore or Tokyo
- use managed PostgreSQL instead of a single JSON state record for auth data
- store media in object storage
- send email through SES
- use CDN or edge acceleration for media and static responses

Suggested starting size:

- app server: 2 vCPU / 4 GB RAM
- managed PostgreSQL: 2 vCPU / 4 GB RAM
- object storage for media
- SES for auth mail

This is sufficient for roughly 1000 DAU light-social traffic with margin, assuming media workloads remain moderate.

## Rollout Strategy

1. Build new backend-owned auth tables and endpoints first.
2. Move email/password app flows to the new backend.
3. Add Apple auth exchange and merge rules.
4. Disable Firebase from production auth paths while keeping config and historical data.
5. Observe production behavior before removing any backup-only Firebase code.

## Risks

### 1. Account Merge Mistakes

The highest product risk is incorrect merging between Apple identities and existing email accounts. Hidden-email accounts must stay isolated unless an explicit account-linking feature is added later.

### 2. Migration Complexity

The repo currently contains in-progress Firebase auth work. Transitioning away from that path will require careful separation so partially migrated code does not remain on the runtime hot path.

### 3. Session Security

Refresh token storage, revocation, and password reset invalidation must be implemented cleanly. Weak token lifecycle handling would reintroduce the same class of security issues this migration is meant to solve.

## Approved Summary

The approved production direction is:

- use self-hosted email/password auth
- send verification and reset mail through Amazon SES
- enforce strong password policy
- remove Google sign-in
- keep Apple sign-in as OAuth
- merge Apple into self-hosted email only when Apple returns the same real email
- keep hidden-email Apple accounts separate
- retain Firebase only as backup/reference, not as production auth infrastructure
