# Server Bootstrap

This document defines the only supported bootstrap path for a new StreetStamps production server.

## Target State

The new server must end in this shape:

- Docker Engine installed
- Docker Compose available
- app directory at `/opt/streetstamps/backend-node-v1`
- production env at `/opt/streetstamps/backend-node-v1/.env`
- backup roots at:
  - `/opt/streetstamps/backups/db`
  - `/opt/streetstamps/backups/release`
- backend served by compose service `api`
- PostgreSQL served by compose service `postgres`

## 1. Base Host Preparation

Run on the new Linux server:

```bash
mkdir -p /opt/streetstamps/backend-node-v1
mkdir -p /opt/streetstamps/backups/db
mkdir -p /opt/streetstamps/backups/release
```

Install:

- Docker Engine
- Docker Compose plugin
- `curl`
- `jq`

## 2. Copy Canonical Deployment Unit

Copy these files into `/opt/streetstamps/backend-node-v1`:

- `server.js`
- `Dockerfile`
- `docker-compose.yml`
- `package.json`
- `package-lock.json`
- `.env`
- `DEPLOY.md`
- `check_auth_mode.sh`
- `readonly_prod_check.sh`
- `docs/ops/PRODUCTION_WORKFLOW.md`
- `docs/ops/SERVER_BOOTSTRAP.md`

Create the docs directory if needed:

```bash
mkdir -p /opt/streetstamps/backend-node-v1/docs/ops
```

## 3. Create Production Environment File

Start from:

- `/opt/streetstamps/backend-node-v1/.env.production.example`

Write the real production values into:

- `/opt/streetstamps/backend-node-v1/.env`

At minimum, confirm:

- `POSTGRES_PASSWORD`
- `JWT_SECRET`
- `DATABASE_URL`
- `CORS_ALLOWED_ORIGINS`
- `MEDIA_PUBLIC_BASE`
- `AUTH_LINK_BASE`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`
- `R2_*`
- `FIREBASE_BEARER_COMPAT_ENABLED=false`
- `WRITE_FREEZE_ENABLED=false`

## 4. Start Services

Run:

```bash
cd /opt/streetstamps/backend-node-v1
docker compose up -d --build
```

## 5. Verify Health

Run:

```bash
curl -s http://127.0.0.1:18080/v1/health | jq .
```

Expected minimum shape:

- `status: "ok"`
- `storage: "postgresql"`
- `auth.businessBearer: "backend_jwt_only"`
- `auth.firebaseBearerCompat: false`
- `maintenance.writeFrozen: false`

## 6. Run Production Check Chain

Run:

```bash
cd /opt/streetstamps/backend-node-v1
BASE_URL=http://127.0.0.1:18080 \
EXPECTED_AUTH_MODE=backend_jwt_only \
EXPECTED_FIREBASE_COMPAT=false \
EXPECTED_WRITE_FROZEN=false \
bash ./readonly_prod_check.sh
```

## 7. Record Deployment

Write `/opt/streetstamps/backend-node-v1/.deployed-git-commit` with:

- commit
- tree state
- status line count
- deployment UTC timestamp
- remote directory

The standard `deploy-safe.sh` script handles this automatically during future releases.

## 8. Cut Traffic

Only after the full verification chain passes should DNS, reverse proxy, or upstream traffic be switched to the new server.

## 9. Migration Window

For server cutover or data migration:

1. set `WRITE_FREEZE_ENABLED=true`
2. rebuild/redeploy api
3. verify `maintenance.writeFrozen=true`
4. migrate data
5. cut traffic
6. verify production checks
7. set `WRITE_FREEZE_ENABLED=false`
8. redeploy and verify again
