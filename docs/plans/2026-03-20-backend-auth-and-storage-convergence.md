# Backend Auth and Storage Convergence Design

Date: 2026-03-20
Status: Draft
Owner: Codex + liuyang

## Background

The backend currently behaves like a hybrid of three systems:

1. a backend-owned auth service with JWT access/refresh tokens
2. a Firebase compatibility layer that still participates in request auth
3. a JSON-document persistence layer that only partially uses PostgreSQL

The current code shows all three paths at once. `server.js` still accepts Firebase-backed bearer resolution in `resolveBearerUserID`, still stores the full app state in `app_state` when Postgres is enabled, and still keeps compatibility indexes such as `firebaseIdentityIndex` and `oauthIndex` in the persisted JSON shape. On the client side, `UserSessionStore` and `BackendAPIClient` still preserve Firebase token fallback behavior, which makes the effective auth authority depend on runtime state rather than a single contract.

Related files:
- [backend-node-v1/server.js](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/backend-node-v1/server.js)
- [StreetStamps/UserSessionStore.swift](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/UserSessionStore.swift)
- [StreetStamps/BackendAPIClient.swift](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/StreetStamps/BackendAPIClient.swift)
- [backend-node-v1/migrate-to-relational.sql](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/backend-node-v1/migrate-to-relational.sql)
- [backend-node-v1/DATA_ISOLATION_FIX.md](/Users/liuyang/Downloads/StreetStamps_fixed_v3_3/backend-node-v1/DATA_ISOLATION_FIX.md)

## Current Problems

### 1. Auth authority is split

Business requests can still be authenticated by either backend JWTs or Firebase-derived identity resolution. That makes it hard to reason about who owns the session, how token refresh works, and which failure mode should be considered authoritative.

### 2. Storage is not truly relational yet

Even when PostgreSQL is enabled, the service persists the entire application state as a single JSON document. That means the system still lacks row-level constraints, real transactional boundaries, and independently queryable domain tables.

### 3. Data isolation has already failed once

The repository contains explicit repair notes for cross-user journey contamination. That means the current model is too dependent on app-layer discipline and too weak on server-side ownership enforcement.

### 4. Client behavior still reflects the old split

The app keeps Firebase-specific state and fallback paths in the session store and backend client. As long as the client can choose between token types at runtime, backend migrations will stay noisy and hard to validate.

## Target State

The target state is a single backend-owned authority for production business APIs:

1. `backend token` is the only credential accepted for normal business API authorization.
2. Firebase becomes a compatibility and migration layer only.
3. PostgreSQL becomes the primary system of record for server-owned data.
4. JSON/blob storage remains only as a temporary migration source or rollback path.
5. Every cross-user or ownership-sensitive write is enforced server-side, never trusted from client payloads alone.

The product should still support a clean guest/account boundary on the client, but the backend should no longer infer production identity from Firebase during normal request handling.

## Firebase Exit Path

Firebase should be reduced in stages instead of removed abruptly.

### Stage 1: Stop Firebase from owning business API auth

The normal request path should reject Firebase bearer tokens for business endpoints. Firebase can remain available for:

- historical reads
- migration jobs
- out-of-band repair scripts
- one-time import tooling

### Stage 2: Keep Firebase only for controlled compatibility

Any Firebase-linked code should be behind an explicit compatibility switch, not an implicit runtime fallback. The switch should be narrow enough that the team can answer:

- which endpoints still accept it
- why it still exists
- when it will be removed

### Stage 3: Remove runtime dependence

Once backend token issuance, refresh, and recovery are stable, remove Firebase from normal auth flows and stop carrying Firebase-specific session state in the client session model.

## Target PostgreSQL Schema

The minimum relational core should be:

| Table | Purpose | Key fields |
| --- | --- | --- |
| `users` | Product account identity and profile | `id`, `display_name`, `handle`, `status`, `created_at`, `last_login_at` |
| `auth_identities` | Login identities bound to users | `id`, `user_id`, `provider`, `provider_subject`, `email`, `email_verified`, `password_hash`, `created_at`, `updated_at` |
| `refresh_tokens` | Long-lived session refresh records | `id`, `user_id`, `token_hash`, `device_info`, `expires_at`, `revoked_at`, `created_at` |
| `journeys` | User-owned journey records | `id`, `user_id`, `title`, `city_id`, `distance`, `start_time`, `end_time`, `visibility`, `data`, `created_at` |

The same relational cutover should also reserve space for:

- `email_verification_tokens`
- `password_reset_tokens`
- `journey_likes`
- `friend_requests`
- `notifications`
- `postcards`

The existing `backend-node-v1/migrate-to-relational.sql` already sketches this direction, but the live service still needs to move from JSON-bag persistence to actual table reads and writes.

## Migration Mapping

The current JSON/blob shape should be translated as follows:

| Current source | Target table or derived record | Notes |
| --- | --- | --- |
| `users[uid]` | `users` | Keep account/profile fields here, not in auth tables |
| `authIdentities[aid]` | `auth_identities` | Preserve provider, provider subject, email, verification, password hash |
| `refreshTokens[rid]` | `refresh_tokens` | Store token hash, expiry, revocation state, and device info |
| `users[uid].journeys[]` | `journeys` | Flatten nested journeys into one row per journey with `user_id` |
| `emailVerificationTokens` | `email_verification_tokens` | Token hash + expiry + used state |
| `passwordResetTokens` | `password_reset_tokens` | Token hash + expiry + used state |
| `likesIndex` | `journey_likes` | Normalize by owner journey and liker |
| `friendRequestsIndex` | `friend_requests` | Keep sender, receiver, note, and timestamps |
| `postcardsIndex` | `postcards` | Keep sender, receiver, city, message, media URL, read state |
| `firebaseIdentityIndex` | import-only compatibility data | Do not make this a production dependency |
| `emailIndex`, `inviteIndex`, `oauthIndex`, `handleIndex` | derived indexes | Rebuild from relational tables instead of treating them as source of truth |

Mapping rules:

1. Do not trust client-provided ownership fields if the server can infer them from auth.
2. Preserve the original JSON payload in a `data` JSONB column only where the structure is still actively used by the app.
3. Anything that represents authorization, ownership, or session lifecycle belongs in first-class columns, not nested blobs.

## High-Risk API Boundaries

The current risk is not only auth; it is also endpoints that accept large client snapshots or mutate cross-user state.

### `POST /v1/journeys/migrate`

This endpoint should be narrowed to an authenticated, server-owned migration path.

Required changes:

1. The authenticated user must be the only source of truth for ownership.
2. `ownerUserID` must be derived server-side, not accepted as authority from the payload.
3. The endpoint should reject any attempt to migrate records that do not belong to the current session.
4. Snapshot imports should be idempotent and collision-safe by journey ID.

### Other sensitive write endpoints

The same principle applies to:

- journey like/unlike endpoints
- friend request creation and acceptance
- postcard send flows
- notification read-sync

For these routes, the server should always derive ownership from auth and from server-side lookup tables, never from the client as a primary authority.

## Phase Order

### Phase 1: Freeze the auth contract

Goal: make backend token the only production business API credential.

Deliverables:

- backend auth refresh and login remain working
- Firebase fallback becomes explicit and narrow
- client session state is updated to prefer backend tokens only
- API tests cover token refresh, expiry, and session switch behavior

### Phase 2: Introduce the relational core

Goal: move the server from JSON blob persistence to table-backed reads and writes.

Deliverables:

- `users`, `auth_identities`, `refresh_tokens`, and `journeys` become real tables in the active path
- mapping scripts or migration jobs backfill from the current JSON/blob state
- existing derived indexes are rebuilt from relational state

### Phase 3: Harden ownership-sensitive APIs

Goal: stop trusting client snapshots for server-owned data.

Deliverables:

- `POST /v1/journeys/migrate` enforces server-side ownership
- cross-user contamination paths are covered by tests
- friend, like, and postcard writes are validated against auth and ownership rules

### Phase 4: Remove legacy dependencies

Goal: turn off Firebase runtime auth and retire blob persistence as a production dependency.

Deliverables:

- Firebase remains import-only or repair-only
- JSON/blob state is retained only as an archive or rollback source
- production traffic uses backend tokens and relational storage exclusively

## Risks And Rollback

### Risk: auth cutover breaks sign-in or refresh

Rollback:

- keep the compatibility switch for Firebase bearer handling until backend token flows are stable
- preserve refresh token records so the session can be reissued without re-registering users
- revert only the auth gate, not the relational migration work

### Risk: relational cutover misses part of the data model

Rollback:

- keep the JSON/blob state as the read fallback until backfill parity is verified
- do not delete the source blob until a full data comparison passes
- if necessary, restart the service against the old blob-backed path while preserving the migrated tables

### Risk: ownership-sensitive writes still leak across users

Rollback:

- disable the risky write endpoint or narrow it to read-only until the ownership rules pass tests
- compare owner counts and per-user journey counts before and after migration
- restore from the last known good blob snapshot if a contamination regression appears

### Risk: client and server get out of sync during migration

Rollback:

- ship the client auth/session change before or together with the backend cutover
- keep the client able to switch environments and force re-login
- make the migration window explicit so old and new auth semantics are not both live longer than necessary

## Success Criteria

The convergence is done when all of the following are true:

1. production business APIs only accept backend-issued tokens
2. PostgreSQL tables are the active source of truth for users, identities, refresh tokens, and journeys
3. `POST /v1/journeys/migrate` and similar ownership-sensitive writes are server-authoritative
4. Firebase remains only as a controlled migration or repair path
5. rollback can move back to the previous auth/storage path without corrupting user ownership

