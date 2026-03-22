#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://api.streetstamps.cyberkkk.cn}"

if [[ "$BASE_URL" == "https://api.streetstamps.cyberkkk.cn" && "${ALLOW_PROD_MUTATION:-0}" != "1" ]]; then
  echo "[FAIL] Refusing to run mutating smoke checks against production without ALLOW_PROD_MUTATION=1"
  echo "[FAIL] Use ./scripts/readonly_prod_check.sh for read-only production verification"
  exit 1
fi

json_get() {
  local path="$1"
  python3 -c 'import json,sys
path=sys.argv[1].split(".")
raw=sys.stdin.read().strip()
if not raw:
  print("")
  raise SystemExit(0)
obj=json.loads(raw)
cur=obj
for p in path:
  if p.isdigit():
    cur=cur[int(p)]
  else:
    cur=cur.get(p) if isinstance(cur,dict) else None
if cur is None:
  print("")
elif isinstance(cur,(dict,list)):
  print(json.dumps(cur,ensure_ascii=False))
else:
  print(cur)' "$path"
}

json_len() {
  python3 -c 'import json,sys
raw=sys.stdin.read().strip()
if not raw:
  print(0)
  raise SystemExit(0)
obj=json.loads(raw)
if isinstance(obj,list):
  print(len(obj))
elif isinstance(obj,dict):
  print(len(obj))
else:
  print(0)'
}

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }

curl_json() {
  local method="$1"
  local path="$2"
  local token="${3:-}"
  local body="${4:-}"
  local url="${BASE_URL}${path}"
  if [[ -n "$token" ]]; then
    if [[ -n "$body" ]]; then
      curl -sS -X "$method" "$url" -H 'content-type: application/json' -H "authorization: Bearer $token" -d "$body"
    else
      curl -sS -X "$method" "$url" -H "authorization: Bearer $token"
    fi
  else
    if [[ -n "$body" ]]; then
      curl -sS -X "$method" "$url" -H 'content-type: application/json' -d "$body"
    else
      curl -sS -X "$method" "$url"
    fi
  fi
}

echo "Base URL: $BASE_URL"

health="$(curl_json GET /v1/health)"
[[ "$(printf '%s' "$health" | json_get status)" == "ok" ]] || fail "health check failed: $health"
pass "health ok"

now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
rand="$(date +%s)$RANDOM"

oauth_token="google-e2e-${rand}"
auth="$(curl_json POST /v1/auth/oauth '' "{\"provider\":\"google\",\"idToken\":\"$oauth_token\"}")"
uid="$(printf '%s' "$auth" | json_get userId)"
at="$(printf '%s' "$auth" | json_get accessToken)"
provider="$(printf '%s' "$auth" | json_get provider)"
[[ -n "$uid" && -n "$at" && "$provider" == "google" ]] || fail "oauth login failed: $auth"
[[ "${uid#guest_}" == "$uid" ]] || fail "oauth login still guest uid: $uid"
pass "oauth login ok uid=$uid"

payload="{\"journeys\":[
{\"id\":\"j_public\",\"title\":\"Public Trip\",\"activityTag\":\"walk\",\"overallMemory\":\"pub\",\"distance\":1000,\"startTime\":\"$now_iso\",\"endTime\":\"$now_iso\",\"visibility\":\"public\",\"memories\":[{\"id\":\"m1\",\"title\":\"p\",\"notes\":\"n\",\"timestamp\":\"$now_iso\",\"imageURLs\":[]}]},
{\"id\":\"j_friends\",\"title\":\"Friends Trip\",\"activityTag\":\"walk\",\"overallMemory\":\"fr\",\"distance\":1000,\"startTime\":\"$now_iso\",\"endTime\":\"$now_iso\",\"visibility\":\"friendsOnly\",\"memories\":[{\"id\":\"m2\",\"title\":\"f\",\"notes\":\"n\",\"timestamp\":\"$now_iso\",\"imageURLs\":[]}]},
{\"id\":\"j_private\",\"title\":\"Private Trip\",\"activityTag\":\"walk\",\"overallMemory\":\"pr\",\"distance\":1000,\"startTime\":\"$now_iso\",\"endTime\":\"$now_iso\",\"visibility\":\"private\",\"memories\":[{\"id\":\"m3\",\"title\":\"x\",\"notes\":\"n\",\"timestamp\":\"$now_iso\",\"imageURLs\":[]}]}],
\"unlockedCityCards\":[{\"id\":\"Shanghai|CN\",\"name\":\"Shanghai\",\"countryISO2\":\"CN\"}]}"

mg="$(curl_json POST /v1/journeys/migrate "$at" "$payload")"
[[ "$(printf '%s' "$mg" | json_get journeys)" == "3" ]] || fail "migrate failed: $mg"
pass "migrate journeys ok"

email1="u1_${rand}@example.com"
email2="u2_${rand}@example.com"
pw='Password123!'
r1="$(curl_json POST /v1/auth/email/register '' "{\"email\":\"$email1\",\"password\":\"$pw\"}")"
r2="$(curl_json POST /v1/auth/email/register '' "{\"email\":\"$email2\",\"password\":\"$pw\"}")"
u1="$(printf '%s' "$r1" | json_get userId)"; t1="$(printf '%s' "$r1" | json_get accessToken)"
u2="$(printf '%s' "$r2" | json_get userId)"; t2="$(printf '%s' "$r2" | json_get accessToken)"
[[ -n "$u1" && -n "$u2" ]] || fail "email register failed r1=$r1 r2=$r2"
pass "email users created"

_="$(curl_json POST /v1/journeys/migrate "$t1" "$payload")"

stranger_profile="$(curl_json GET "/v1/profile/$u1" "$t2")"
stranger_jc="$(printf '%s' "$stranger_profile" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d.get("journeys",[])))')"
stranger_first_v="$(printf '%s' "$stranger_profile" | json_get journeys.0.visibility)"
stranger_cards="$(printf '%s' "$stranger_profile" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d.get("unlockedCityCards",[])))')"
[[ "$stranger_jc" == "1" && "$stranger_first_v" == "public" && "$stranger_cards" == "0" ]] || fail "stranger visibility failed: $stranger_profile"
pass "stranger visibility ok"

me_profile="$(curl_json GET /v1/profile/me "$t1")"
invite="$(printf '%s' "$me_profile" | json_get inviteCode)"
[[ -n "$invite" ]] || fail "inviteCode missing from /v1/profile/me: $me_profile"

friend_add="$(curl_json POST /v1/friends/requests "$t2" "{\"displayName\":\"$u1\",\"inviteCode\":\"$invite\"}")"
rid="$(printf '%s' "$friend_add" | json_get request.id)"
[[ -n "$rid" ]] || fail "friend request create failed: $friend_add"
pass "friend request create ok"

accept="$(curl_json POST "/v1/friends/requests/$rid/accept" "$t1")"
friend_id="$(printf '%s' "$accept" | json_get friend.id)"
[[ "$friend_id" == "$u2" ]] || fail "friend request accept failed: $accept"
pass "friend request accept ok"

friend_profile="$(curl_json GET "/v1/profile/$u1" "$t2")"
friend_jc="$(printf '%s' "$friend_profile" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d.get("journeys",[])))')"
friend_cards="$(printf '%s' "$friend_profile" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d.get("unlockedCityCards",[])))')"
[[ "$friend_jc" == "2" && "$friend_cards" -ge "1" ]] || fail "friend visibility failed: $friend_profile"
pass "friend visibility ok"

_="$(curl_json DELETE "/v1/friends/$u1" "$t2")"
fl2="$(curl_json GET /v1/friends "$t2")"
fl2c="$(printf '%s' "$fl2" | json_len)"
[[ "$fl2c" == "0" ]] || fail "friend delete failed: $fl2"
pass "friend delete ok"

echo 'e2e-media' >/tmp/ss_e2e_media.txt
up="$(curl -sS -X POST "${BASE_URL}/v1/media/upload" -H "authorization: Bearer $at" -F "file=@/tmp/ss_e2e_media.txt;type=text/plain")"
url="$(printf '%s' "$up" | json_get url)"
[[ -n "$url" ]] || fail "media upload failed: $up"
code="$(curl -sS -o /tmp/ss_e2e_fetch.bin -w '%{http_code}' "$url")"
[[ "$code" == "200" ]] || fail "media fetch failed code=$code url=$url"
pass "media upload/fetch ok"

again="$(curl_json POST /v1/auth/oauth '' "{\"provider\":\"google\",\"idToken\":\"$oauth_token\"}")"
uid2="$(printf '%s' "$again" | json_get userId)"
at2="$(printf '%s' "$again" | json_get accessToken)"
[[ "$uid2" == "$uid" ]] || fail "relogin user mismatch old=$uid new=$uid2"

merge_payload="{\"journeys\":[{\"id\":\"j_public\",\"title\":\"Public Trip\",\"activityTag\":\"walk\",\"overallMemory\":\"pub\",\"distance\":1000,\"startTime\":\"$now_iso\",\"endTime\":\"$now_iso\",\"visibility\":\"public\",\"memories\":[]},{\"id\":\"j_guest_new\",\"title\":\"Guest New\",\"activityTag\":\"walk\",\"overallMemory\":\"new\",\"distance\":500,\"startTime\":\"$now_iso\",\"endTime\":\"$now_iso\",\"visibility\":\"private\",\"memories\":[]}],\"unlockedCityCards\":[{\"id\":\"Shanghai|CN\",\"name\":\"Shanghai\",\"countryISO2\":\"CN\"}]}"
_="$(curl_json POST /v1/journeys/migrate "$at2" "$merge_payload")"
me_after="$(curl_json GET /v1/profile/me "$at2")"
me_after_j="$(printf '%s' "$me_after" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d.get("journeys",[])))')"
[[ "$me_after_j" == "2" ]] || fail "post relogin merge failed: $me_after"
pass "relogin + merge simulation ok"

echo "E2E_DONE"
