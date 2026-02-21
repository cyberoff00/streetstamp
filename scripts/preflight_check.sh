#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pass() { echo "[PASS] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

cd "$ROOT"

echo "Project root: $ROOT"

[[ -f "StreetStamps.xcodeproj/project.pbxproj" ]] || fail "missing Xcode project file"
pass "xcode project exists"

[[ -f "StreetStamps/BackendConfig.swift" ]] || fail "missing BackendConfig.swift"
[[ -f "StreetStamps/AccountCenterView.swift" ]] || fail "missing AccountCenterView.swift"
[[ -f "StreetStamps/FriendsHubView.swift" ]] || fail "missing FriendsHubView.swift"
pass "core app files exist"

[[ -f "backend-node-v1/server.js" ]] || fail "missing backend-node-v1/server.js"
node --check backend-node-v1/server.js >/dev/null
pass "backend-node-v1/server.js syntax ok"

if [[ -f "GoogleService-Info.plist" ]]; then
  pass "GoogleService-Info.plist exists"
else
  warn "GoogleService-Info.plist missing (Google login may fail)"
fi

if rg -n "R2_PUBLIC_BASE:\s*\"\"" backend-node-v1/docker-compose.yml >/dev/null 2>&1; then
  warn "R2_PUBLIC_BASE empty in backend-node-v1/docker-compose.yml"
else
  pass "R2_PUBLIC_BASE appears configured in backend-node-v1/docker-compose.yml"
fi

if rg -n "GoogleSignIn" StreetStamps.xcodeproj/project.pbxproj >/dev/null 2>&1; then
  pass "GoogleSignIn linkage found in project"
else
  warn "GoogleSignIn linkage not detected in project.pbxproj"
fi

if rg -n "profileVisibility|handle|stats|inviteCode" backend-node-v1/server.js >/dev/null 2>&1; then
  pass "backend exposes social profile fields"
else
  warn "backend may not expose complete social profile fields"
fi

if rg -n "MigrationStatusStore|JourneyMigrationReport|pendingMigrationFromGuestUserID" StreetStamps >/dev/null 2>&1; then
  pass "migration persistence hooks present"
else
  warn "migration persistence hooks not fully present"
fi

echo "PREFLIGHT_DONE"
