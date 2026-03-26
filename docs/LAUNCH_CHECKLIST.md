# StreetStamps Launch Checklist

## P0 - Must Before Release
- [x] Account center productized flow (login/config/migration/visibility).
- [x] Migration rule: upload `public/friendsOnly`, keep `private` local.
- [x] Lifelog is local-only and is not part of cloud migration.
- [x] Cloud data scope finalized:
  - Avatar/loadout and user profile stats are stored in cloud profile payload.
  - Journey route coordinates and memories are uploaded only for `public/friendsOnly`.
  - `private` journeys and lifelog require manual migration when switching devices.
- [x] Guest-to-account migration marker and merge source support.
- [x] Friend identity model: `handle`, `inviteCode`, profile stats, visibility.
- [x] Backend profile payload extended (`handle`, `inviteCode`, `profileVisibility`, `stats`).
- [x] R2 public URL output configured and verified.
- [ ] Set production env from `backend-node-v1/.env.production.example`.
- [ ] Override `JWT_SECRET`, `DATABASE_URL`, `POSTGRES_PASSWORD`, `CORS_ALLOWED_ORIGINS`, and mail credentials in production.
- [ ] Apply `docs/ops/nginx-streetstamps.conf` (or equivalent) on the reverse proxy.
- [ ] Deploy latest `backend-node-v1/server.js` and compose config to production container.
- [ ] Run read-only production verification.
  Command:
  `BASE_URL=https://worldo-api.cyberkkk.cn ALLOWED_ORIGIN=https://app.streetstamps.cyberkkk.cn ./scripts/readonly_prod_check.sh`
- [ ] Run mutating end-to-end regression only after read-only checks pass.
  Command:
  `ALLOW_PROD_MUTATION=1 BASE_URL=https://worldo-api.cyberkkk.cn ./scripts/e2e_smoke.sh`

## P1 - Quality Gate
- [x] Add automated API regression script in repo (`scripts/e2e_smoke.sh`).
- [x] Add read-only production verification script (`scripts/readonly_prod_check.sh`).
- [ ] Add iOS UI smoke test cases for login/migration/friends.
- [ ] Add failure recovery UX: token expired / migration interrupted.
- [ ] Add release environment lock (prevent dev endpoint in production build).
  Preflight command:
  `./scripts/preflight_check.sh`
- [ ] Capture production metrics for auth failures, throttling, upload failures, and 5xx rate.

## P2 - Hardening
- [ ] Friend request workflow (request/accept/reject/block) on backend + app.
- [ ] Privacy/compliance pages and account data deletion flow.
- [ ] Observability dashboard (auth success rate, migration success rate, media upload error rate).
- [ ] Rollback and backup SOP.
