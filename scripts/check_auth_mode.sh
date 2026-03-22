#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://api.streetstamps.cyberkkk.cn}"
EXPECTED_AUTH_MODE="${EXPECTED_AUTH_MODE:-backend_jwt_only}"
EXPECTED_FIREBASE_COMPAT="${EXPECTED_FIREBASE_COMPAT:-false}"
EXPECTED_WRITE_FROZEN="${EXPECTED_WRITE_FROZEN:-false}"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

health_json="$(curl -sS --max-time 10 "${BASE_URL}/v1/health")"

business_bearer="$(printf '%s' "$health_json" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("auth") or {}).get("businessBearer",""))')"
firebase_compat="$(printf '%s' "$health_json" | python3 -c 'import json,sys; value=(json.load(sys.stdin).get("auth") or {}).get("firebaseBearerCompat"); print(str(value).lower() if value is not None else "")')"
write_frozen="$(printf '%s' "$health_json" | python3 -c 'import json,sys; value=(json.load(sys.stdin).get("maintenance") or {}).get("writeFrozen"); print(str(value).lower() if value is not None else "")')"
storage_mode="$(printf '%s' "$health_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("storage",""))')"

[[ -n "$business_bearer" ]] || fail "health auth.businessBearer missing"
[[ -n "$firebase_compat" ]] || fail "health auth.firebaseBearerCompat missing"
[[ -n "$write_frozen" ]] || fail "health maintenance.writeFrozen missing"

[[ "$business_bearer" == "$EXPECTED_AUTH_MODE" ]] || fail "unexpected auth mode: got '$business_bearer', expected '$EXPECTED_AUTH_MODE'"
[[ "$firebase_compat" == "$EXPECTED_FIREBASE_COMPAT" ]] || fail "unexpected firebase compat flag: got '$firebase_compat', expected '$EXPECTED_FIREBASE_COMPAT'"
[[ "$write_frozen" == "$EXPECTED_WRITE_FROZEN" ]] || fail "unexpected write frozen flag: got '$write_frozen', expected '$EXPECTED_WRITE_FROZEN'"

pass "auth mode ok: businessBearer=$business_bearer firebaseBearerCompat=$firebase_compat writeFrozen=$write_frozen storage=$storage_mode"
echo "AUTH_MODE_CHECK_DONE"
