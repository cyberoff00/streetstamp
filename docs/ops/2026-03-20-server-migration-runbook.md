# Server Migration Runbook

Date: 2026-03-20
Scope: StreetStamps backend migration from the current production host to a new server
Primary goal: move the service without losing data, breaking auth, or creating a split-brain deployment

## 1. Target Topology

The target production stack should be:

- `Reverse proxy`: Nginx terminates TLS and forwards traffic to the app
- `Node API`: Express service on `127.0.0.1:18080`
- `PostgreSQL`: primary application database
- `Object storage`: S3-compatible storage for media uploads and other binary assets

Operational notes:

- The Node API must be the only application process exposed to the reverse proxy.
- PostgreSQL must be the system of record for mutable backend data.
- Object storage must hold media files that are no longer meant to live on the app host disk.
- Local files such as `data/data.json` and `media/` are legacy or transitional only.

## 2. New vs Old Environment Check

Before any cutover, compare the current host and the new host against this list.

### Host and runtime

- OS version and kernel version match the expected production baseline.
- Node.js version matches the version used for validation.
- PostgreSQL major version matches the expected deployment target.
- Nginx is installed and can load the production config without syntax errors.
- The app can bind to `127.0.0.1:18080` and be reached through the proxy.

### Storage and data

- PostgreSQL is reachable from the Node API.
- Object storage credentials are valid and can write and read a test object.
- Legacy `data/data.json` is either migrated or explicitly marked read-only.
- Legacy `media/` contents are either migrated to object storage or kept as archival data only.

### Network and TLS

- The domain resolves to the new server.
- TLS certificate paths in Nginx are valid.
- Port 80 redirects to 443.
- Port 443 only serves the intended API host.

### Application behavior

- `/v1/health` returns healthy status.
- `/v1/health.auth.businessBearer` reports the expected auth mode for the migration window.
- `/v1/health.auth.firebaseBearerCompat` matches the approved compatibility policy.
- Login, refresh, journey read/write, and media upload work against the new host.
- Allowed CORS origins are limited to the production app origin.

## 3. Configuration and Secrets

The new server must have a single source of truth for production configuration.

Required runtime values:

- `JWT_SECRET`
- `DATABASE_URL` or the equivalent PostgreSQL host, user, password, and database variables
- `CORS_ALLOWED_ORIGINS`
- `AUTH_LINK_BASE`
- `MEDIA_DIR`
- `MEDIA_PUBLIC_BASE`
- `JSON_BODY_LIMIT_MB`
- `MEDIA_UPLOAD_MAX_BYTES`
- `R2_ACCOUNT_ID` or equivalent object storage account settings
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET`
- `R2_ENDPOINT`
- `R2_REGION`
- `R2_PUBLIC_BASE`
- Mail delivery credentials, if verification or reset emails are enabled

Handling rules:

- Store secrets outside the repo.
- Keep the production env file on the server, not in source control.
- Record the exact deployed config snapshot before cutover.
- Do not reuse a dev JWT secret or dev database URL in production.

## 4. Backup and Restore Drill

Take backups before cutover and prove that restore works before you trust the new environment.

### Backup objects

- PostgreSQL full backup
- Legacy `data/data.json`, if it still exists
- Media assets currently stored on disk
- Object storage bucket contents, if this is a live migration
- Production env snapshot with secrets redacted
- Nginx config and deployment manifest versions

### Backup procedure

1. Freeze writes or switch the app to maintenance mode.
2. Take a PostgreSQL dump.
3. Export or sync media assets.
4. Snapshot the production configuration.
5. Verify that the backup files exist and are non-empty.

Suggested commands:

```bash
pg_dump "$DATABASE_URL" > backup-YYYYMMDD.sql
aws s3 sync s3://<bucket> ./backup-object-storage/
rsync -a media/ ./backup-media/
```

### Restore drill

1. Restore the PostgreSQL dump into an empty staging database.
2. Restore media or object storage artifacts into a test bucket or test prefix.
3. Start the Node API against the restored data.
4. Verify `/v1/health`, auth, a journey read, and a media fetch.
5. Confirm the restored dataset matches the expected record counts.

Do not cut over until a restore drill has passed at least once.

## 5. Freeze Writes and Read-Only Window

Use a short read-only window for the actual migration.

### Freeze policy

- Announce a maintenance window before the cutover.
- Stop mutating writes from the client or route them to a maintenance response.
- Keep read-only checks available where possible.
- Do not allow background jobs to keep writing to the old host during cutover.

### What to freeze

- Journey create/update/delete
- Likes
- Friend requests and friend mutations
- Postcard send and delete flows
- Any media upload endpoint

### Minimum user-facing behavior

- Show a maintenance or temporary read-only message.
- Keep the message simple and time bounded.
- Avoid silent retries that can double-write during the window.

## 6. Cutover Steps

1. Confirm the backup and restore drill passed.
2. Confirm the new server is green in staging or dry-run mode.
3. Put the old production host into read-only or maintenance mode.
4. Take a final backup from the old host.
5. Import or sync the final data into the new PostgreSQL instance.
6. Bring up the Node API on the new server.
7. Reload Nginx with the new production config.
8. Run smoke checks against the new public endpoint.
9. Switch DNS or upstream traffic to the new server.
10. Monitor the first live requests closely before reopening writes.

Acceptance after cutover:

- Login succeeds.
- Refresh succeeds.
- `/v1/health.auth.businessBearer` matches the approved release mode.
- `/v1/health.auth.firebaseBearerCompat` matches the approved release mode.
- A journey can be read.
- A journey write lands in the new database.
- A media upload resolves to the expected public URL.
- CORS only allows the approved app origin.

## 7. Rollback Steps

Rollback should be possible without debate if a hard gate fails.

Rollback triggers:

- Auth failures spike or token refresh breaks.
- Data ownership or isolation checks fail.
- Media upload or media fetch fails consistently.
- Health checks fail after the switch.
- Database migration imports incomplete or corrupt data.

Rollback procedure:

1. Stop writes on the new server.
2. Restore traffic back to the old server.
3. Re-enable the old server in read-only or normal mode, depending on the failure.
4. Verify the old host can still serve login, refresh, reads, and safe writes.
5. Record the failure mode and stop the migration until the root cause is fixed.

Important rule:

- Never keep both hosts writable after a failed cutover.

## 8. Monitoring and Verification

Minimum checks during the migration window:

- `/v1/health` returns 200
- `./scripts/check_auth_mode.sh` passes against the target environment
- `./scripts/readonly_prod_check.sh` passes against the target environment
- Login succeeds
- Refresh succeeds
- Journey read succeeds
- Journey write succeeds
- Media upload succeeds
- Media public URL resolves
- Nginx returns the expected TLS endpoint
- PostgreSQL connection count is stable
- Error rate does not spike after traffic shift

Minimum acceptance gates:

- Auth smoke passes
- Data isolation check passes
- Migration smoke passes
- Rollback smoke passes
- Production config matches the approved env template
- Health and auth mode checks match the approved release window

Suggested auth mode verification commands:

```bash
BASE_URL="https://api.streetstamps.cyberkkk.cn" \
EXPECTED_AUTH_MODE="backend_jwt_only" \
EXPECTED_FIREBASE_COMPAT="false" \
./scripts/check_auth_mode.sh
```

```bash
BASE_URL="https://api.streetstamps.cyberkkk.cn" \
ALLOWED_ORIGIN="https://app.streetstamps.cyberkkk.cn" \
EXPECTED_AUTH_MODE="backend_jwt_only" \
EXPECTED_FIREBASE_COMPAT="false" \
./scripts/readonly_prod_check.sh
```

Recommended monitoring signals:

- 4xx and 5xx rate
- Auth failure rate
- Refresh failure rate
- Media upload failure rate
- PostgreSQL connection and query errors
- Reverse proxy upstream errors
- Disk usage on the old host until it is retired

## Final Go / No-Go

Go only if all of the following are true:

- Backup completed
- Restore drill passed
- Auth smoke passed
- Data isolation passed
- Migration smoke passed
- Rollback path is verified
- Monitoring is active

If any item is missing, stay in the old environment and fix the gap first.
