#!/usr/bin/env bash
# Grant coins to a user by email.
#
# Usage:
#   ./scripts/worldo-coins-grant.sh <email> <amount> [note]
#
# Looks up the user.id by email via direct SSH+psql, then POSTs to
# /v1/admin/coins/grant with the ADMIN_API_TOKEN.
#
# Requires:
#   - SSH access to root@13.193.6.71
#   - WORLDO_ADMIN_TOKEN env var (matching server's ADMIN_API_TOKEN)
#   - WORLDO_API_BASE env var (defaults to https://worldo-api.cyberkkk.cn)

set -euo pipefail

EMAIL="${1:-}"
AMOUNT="${2:-}"
NOTE="${3:-Xianyu customer service}"

if [[ -z "$EMAIL" || -z "$AMOUNT" ]]; then
  echo "Usage: $0 <email> <amount> [note]" >&2
  exit 1
fi

if [[ -z "${WORLDO_ADMIN_TOKEN:-}" ]]; then
  echo "Error: WORLDO_ADMIN_TOKEN env var not set" >&2
  echo "Set it to match the ADMIN_API_TOKEN configured on the server." >&2
  exit 2
fi

API_BASE="${WORLDO_API_BASE:-https://worldo-api.cyberkkk.cn}"
SSH_HOST="${WORLDO_SSH_HOST:-root@13.193.6.71}"

# Step 1: look up user.id by email
echo "→ Looking up user by email: $EMAIL"
SQL="SELECT id FROM users WHERE email ILIKE '$EMAIL' LIMIT 1;"
USER_ID=$(ssh -o StrictHostKeyChecking=no "$SSH_HOST" \
  "docker exec streetstamps-postgres psql -U streetstamps -d streetstamps -t -A -c \"$SQL\"" \
  | tr -d '[:space:]')

if [[ -z "$USER_ID" ]]; then
  echo "Error: no user found with email $EMAIL" >&2
  exit 3
fi

echo "✓ user_id: $USER_ID"

# Step 2: POST grant
echo "→ Granting $AMOUNT coins (note: $NOTE)"
RESPONSE=$(curl -fsS -X POST "$API_BASE/v1/admin/coins/grant" \
  -H "Content-Type: application/json" \
  -H "X-Admin-Token: $WORLDO_ADMIN_TOKEN" \
  -d "{\"user_id\":\"$USER_ID\",\"amount\":$AMOUNT,\"note\":\"$NOTE\"}")

BALANCE=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('balance','?'))")
echo "✓ Granted $AMOUNT coins. New balance: $BALANCE"
echo
echo "Tell the user: kill the app and reopen — coins will appear after reload."
