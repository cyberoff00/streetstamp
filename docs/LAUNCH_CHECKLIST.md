# StreetStamps Launch Checklist

## P0 - Must Before Release
- [x] Account center productized flow (login/config/migration/visibility).
- [x] Migration rule: upload `public/friendsOnly`, keep `private` local.
- [x] Guest-to-account migration marker and merge source support.
- [x] Friend identity model: `handle`, `inviteCode`, profile stats, visibility.
- [x] Backend profile payload extended (`handle`, `inviteCode`, `profileVisibility`, `stats`).
- [x] R2 public URL output configured and verified.
- [ ] Deploy latest `backend-node-v1/server.js` to production container.
- [ ] End-to-end regression on production: login -> migrate -> add friend -> profile view.
  Command:
  `BASE_URL=https://api.streetstamps.cyberkkk.cn ./scripts/e2e_smoke.sh`

## P1 - Quality Gate
- [x] Add automated API regression script in repo (`scripts/e2e_smoke.sh`).
- [ ] Add iOS UI smoke test cases for login/migration/friends.
- [ ] Add failure recovery UX: token expired / migration interrupted.
- [ ] Add release environment lock (prevent dev endpoint in production build).
  Preflight command:
  `./scripts/preflight_check.sh`

## P2 - Hardening
- [ ] Friend request workflow (request/accept/reject/block) on backend + app.
- [ ] Privacy/compliance pages and account data deletion flow.
- [ ] Observability dashboard (auth success rate, migration success rate, media upload error rate).
- [ ] Rollback and backup SOP.
