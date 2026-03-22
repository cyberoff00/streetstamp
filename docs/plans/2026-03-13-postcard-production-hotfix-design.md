# Postcard Production Hotfix Design

**Goal:** Deploy the newer postcard quota logic to production so the live backend matches the current app-side send flow and quota messaging.

**Context:** Production is currently running an older `backend-node-v1` build on `101.132.159.73`. The live backend still enforces the original postcard quota rules, while the local workspace and client flow already expect the dynamic quota version with `cityJourneyCount`.

**Chosen Approach:** Perform a backend-only hot update on the production host. Keep storage untouched in PostgreSQL, update only `postcard-rules.js` and the `/v1/postcards/send` handler path in `server.js`, rebuild the API container, restart it, and verify health plus postcard quota behavior.

**Why This Approach:**
- It closes the logic mismatch without waiting for an iOS client release.
- It avoids schema changes or data migrations because the quota is computed from existing postcard history plus request payload.
- It keeps rollback simple: the server directory can be backed up before the container rebuild.

**Deployment Scope:**
- Production backend code under `/opt/streetstamps/backend-node-v1`
- Docker image rebuild for the `api` service only
- No PostgreSQL writes beyond normal application startup/runtime behavior

**Risks and Mitigations:**
- Risk: Production container could fail to rebuild or restart.
  Mitigation: Take a server-side backup of the backend directory before changing files.
- Risk: Local code and production code may differ outside the postcard files.
  Mitigation: Update only the minimum backend files required for the quota hotfix.
- Risk: Runtime behavior may still differ from local expectations.
  Mitigation: Run targeted local tests first, then run production health checks and inspect the live code after deploy.

**Verification Plan:**
- Local: run postcard rule tests and postcard API contract tests.
- Production: confirm container health, confirm live files include `cityJourneyCount` quota logic, and confirm the API container is healthy after restart.
