#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://api.streetstamps.cyberkkk.cn}"
ALLOWED_ORIGIN="${ALLOWED_ORIGIN:-https://app.streetstamps.cyberkkk.cn}"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

health_headers="$(curl -I -sS --max-time 10 -H "Origin: ${ALLOWED_ORIGIN}" "${BASE_URL}/v1/health")"
printf '%s\n' "$health_headers" | grep -qi "200" || fail "health endpoint not reachable"
printf '%s\n' "$health_headers" | grep -qi "x-content-type-options: nosniff" || fail "missing x-content-type-options"
printf '%s\n' "$health_headers" | grep -qi "x-frame-options: DENY" || fail "missing x-frame-options"
printf '%s\n' "$health_headers" | grep -qi "referrer-policy: same-origin" || fail "missing referrer-policy"
printf '%s\n' "$health_headers" | grep -qi "access-control-allow-origin: ${ALLOWED_ORIGIN}" || fail "origin allowlist not reflected"
pass "health headers look correct"

invite_headers="$(curl -I -sS --max-time 10 "${BASE_URL}/open/invite?code=TEST123")"
printf '%s\n' "$invite_headers" | grep -qi "content-type: text/html" || fail "invite page not returning html"
pass "invite landing reachable"

echo "READONLY_PROD_CHECK_DONE"
