# Production Workflow

This is the canonical workflow for any change that may affect the live StreetStamps backend.

## Fixed Production Target

- Server host: `101.132.159.73`
- Remote app directory: `/opt/streetstamps/backend-node-v1`
- Compose file: `/opt/streetstamps/backend-node-v1/docker-compose.yml`
- Environment file: `/opt/streetstamps/backend-node-v1/.env`
- API container: `streetstamps-node-v1`
- Database container: `streetstamps-postgres`
- Internal health URL: `http://127.0.0.1:18080/v1/health`
- Public API base URL: `https://api.streetstamps.cyberkkk.cn`

Do not deploy to any other path or container unless the production unit itself is intentionally migrated.

## Mandatory Rule

Any work that changes live backend behavior must stop at this checkpoint:

1. Finish local code changes.
2. Run local verification.
3. Report exactly what changed.
4. Report whether the change is local-only or requires production sync.
5. Report the exact server, directory, container, and health endpoint that would be touched.
6. Wait for explicit approval before syncing to production.
7. After deployment, run the fixed production verification chain.
8. Report the live result with exact server, directory, container, and verified endpoint.

No silent production syncs.

## Execution Principles

- Prefer real code, config, deployment, and verification work over writing extra documentation.
- Write documentation only when it directly constrains production behavior, prevents mistakes, or is itself a required deliverable.
- Do not finish important work with patch-on-patch layering when a clear primary path can be established.
- Prefer one clear logic chain over multiple compatibility branches, fallback routes, or temporary side paths.
- If a task would require keeping or removing historical compatibility, stop and get explicit confirmation before implementing it.

Historical compatibility decisions that require explicit confirmation include:

- whether to keep or remove old tokens
- whether to preserve or remove old API behavior
- whether to auto-migrate old data formats
- whether to keep Firebase, CloudKit, or other migration-era compatibility paths
- whether to support old clients after a server-side change

Default bias:

- do the materially important work first
- minimize side documents
- avoid compatibility by default unless explicitly approved

## Canonical Deployment Chain

Local release command:

```bash
./backend-node-v1/deploy-safe.sh
```

This is the only supported production release entry point.

It always performs:

1. local preflight
2. backend syntax validation
3. remote PostgreSQL backup
4. remote release backup
5. upload of canonical release files
6. `docker compose up -d --build api`
7. `readonly_prod_check.sh`
8. `.deployed-git-commit` refresh

## Canonical Verification Chain

Production verification command:

```bash
BASE_URL=https://api.streetstamps.cyberkkk.cn \
EXPECTED_AUTH_MODE=backend_jwt_only \
EXPECTED_FIREBASE_COMPAT=false \
EXPECTED_WRITE_FROZEN=false \
./scripts/readonly_prod_check.sh
```

## Deployment Traceability

Every successful deployment must update:

- `/opt/streetstamps/backend-node-v1/.deployed-git-commit`

That file records:

- deployed source commit
- whether the source worktree was clean or dirty
- source status line count
- deployment timestamp in UTC
- remote deployment directory

## Rollback

Rollback command:

```bash
./backend-node-v1/rollback.sh /opt/streetstamps/backups/release/<timestamp>
```

Rollback must be followed by the same production verification chain.

## Disallowed Paths

Do not use:

- manual `scp` plus ad-hoc `mv`
- direct `docker restart` without rebuild and checks
- expect scripts with passwords
- alternate historical deploy helper scripts
- hand edits inside the live container

## Migration Window Rule

If production is entering a migration or server cutover window:

- set `WRITE_FREEZE_ENABLED=true` in `.env`
- redeploy with `docker compose up -d --build api`
- verify `maintenance.writeFrozen=true`
- only reopen writes after post-cutover verification passes
