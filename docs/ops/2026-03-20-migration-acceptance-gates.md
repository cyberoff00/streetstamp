# Migration Acceptance Gates

This checklist is the final gate before any traffic moves to a new server or a new backend storage path.

If any item below is not green, do not cut over production traffic.

## 1. Auth Regression Matrix

| Scenario | Expected result | Blocker if failed |
| --- | --- | --- |
| Email login with valid credentials | Returns a backend session, app enters logged-in state | Business APIs may still be using Firebase or mixed token paths |
| Email login with wrong password | Returns a clear auth error, session remains guest | Credential handling is unsafe or misleading |
| Apple login with valid token | Returns a backend session and stable user identity | Apple auth cannot be trusted for production |
| Refresh with valid refresh token | Returns a new backend access token | Session renewal is broken |
| Refresh with expired or revoked refresh token | Returns `401`, app can recover by re-login | Stale sessions may survive cutover |
| Logout | Revokes session locally and on server | Tokens may remain valid after user intent to sign out |
| Expired access token on API request | Client retries refresh once, then forces re-login if refresh fails | Silent auth loops or stuck UI are possible |
| Firebase fallback path | Is disabled in the normal production path and only used if explicitly allowed by migration policy | Auth authority is still split |
| User switch after logout/login | Current account, guest scope, and local profile all point to the new user only | Cross-account contamination is still possible |

## 2. Data Isolation And Consistency Checks

These checks must pass on the source environment and the target environment.

- Every journey on the server has exactly one owner and that owner matches the authenticated user that wrote it.
- No journey, like, friend request, postcard, or notification exists under the wrong user ID.
- `journeys/migrate` does not accept client ownership as truth; the server rewrites ownership.
- Deleted journeys stay deleted after sync, restore, and re-open.
- The count of users, journeys, city cards, likes, and friend requests matches the migration report.
- A sample of at least one account with public data and one account with private data is compared before and after migration.
- If PostgreSQL is the target store, the database row counts match the exported snapshot counts.
- If file-backed media is still used, every referenced media object exists and is reachable from the new environment.

## 3. Post-Migration Smoke Chain

Run these smoke paths only after auth and data checks are green.

- `GET /v1/health` returns healthy status, the expected storage mode, and the expected auth mode.
- If the cutover target is backend-only auth, `/v1/health.auth.businessBearer` must equal `backend_jwt_only`.
- If the cutover target still allows temporary compatibility, `/v1/health.auth.firebaseBearerCompat` must match the approved migration policy exactly.
- Login works with the configured production auth path.
- Token refresh works without Firebase-only dependencies.
- Load the main feed or profile view and confirm the app boots into an authenticated state.
- Create a journey or update an existing one and verify it persists.
- Upload or read a postcard media object and confirm the URL resolves.
- Open friends, likes, and notifications screens and verify they load without auth errors.
- If CloudKit remains enabled, verify sync resumes without duplicating or deleting unrelated records.

## 4. Rollback Acceptance

Rollback is only valid if the old environment still behaves correctly after the cutback.

- Repoint traffic to the old server successfully.
- Authenticate again on the old server without manual token repair.
- Read an existing journey and confirm ownership is unchanged.
- Create or update a small non-destructive record and confirm the old environment still accepts writes if it is meant to remain writable.
- Verify the old database or data store still matches the last known good backup.
- Confirm any temporary migration flags are cleared or disabled.
- Confirm the app can reopen after rollback without a forced reinstall.

## 5. Release Gates

Do not cut production traffic unless all of the following are true:

- Auth regression matrix is green.
- Data isolation and consistency checks are green.
- Post-migration smoke chain is green.
- Rollback acceptance is green in a dry run or an actual rollback rehearsal.
- Production config matches the target environment and no dev endpoint is still referenced.
- `/v1/health` reports the approved auth mode for the release window.
- Backups exist and a restore has been rehearsed.
- Monitoring is live for auth failures, 5xx rate, write failures, and storage errors.
- The on-call owner has signed off that rollback is still possible.

## Go / No-Go

- `GO`: all checks above are green, and the cutover window is approved.
- `NO-GO`: any auth, data, smoke, rollback, or monitoring item is red or unknown.
