#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Shared helpers for splitpro-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, lengths, and pass/fail results are printed.

: "${BASE_URL:=http://localhost:3000}"
: "${MAILPIT_URL:=http://localhost:8025}"
# Optional basic-auth for a protected Mailpit (user:pass). Read from MAILPIT_AUTH_FILE when set so the
# value never appears on a command line or in logs.
if [ -n "${MAILPIT_AUTH_FILE:-}" ]; then MAILPIT_AUTH=$(cat "$MAILPIT_AUTH_FILE"); fi
: "${MAILPIT_AUTH:=}"
mp() { if [ -n "$MAILPIT_AUTH" ]; then curl -s -u "$MAILPIT_AUTH" "$@"; else curl -s "$@"; fi; }
: "${TEST_TIMEOUT:=300}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() {
  printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"
  [ "$_FAIL" -eq 0 ]
}

# assert_eq LABEL EXPECTED ACTUAL
assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
# assert_contains LABEL NEEDLE HAYSTACK
assert_contains() { if printf '%s' "$3" | grep -q -- "$2"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if printf '%s' "$3" | grep -q -- "$2"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@"; }

# wait_for_code URL CODE [TIMEOUT]
wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url" || true)
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
      printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2
      return 1
    fi
    sleep 2
  done
}

# login EMAIL JAR  -> completes a magic-link login through Mailpit; leaves cookies in JAR
login() {
  local email=$1 jar=$2 csrf id link
  : > "$jar"
  csrf=$(curl -s -c "$jar" -b "$jar" "$BASE_URL/api/auth/csrf" | jq -r .csrfToken)
  [ -n "$csrf" ] && [ "$csrf" != "null" ] || { echo "no csrf token" >&2; return 1; }
  curl -s -c "$jar" -b "$jar" -o /dev/null -X POST "$BASE_URL/api/auth/signin/email" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "csrfToken=$csrf" --data-urlencode "email=$email" \
    --data-urlencode "callbackUrl=$BASE_URL/balances" --data-urlencode "json=true"
  for _ in $(seq 1 30); do
    id=$(mp "$MAILPIT_URL/api/v1/search?query=to:$email" | jq -r '.messages[0].ID // empty')
    [ -n "$id" ] && break
    sleep 1
  done
  [ -n "$id" ] || { echo "no sign-in mail for $email" >&2; return 1; }
  link=$(mp "$MAILPIT_URL/api/v1/message/$id" | jq -r '.Text' | tr -d '\r' \
    | grep -oE "$BASE_URL/api/auth/callback/email[^[:space:]]+" | head -1)
  [ -n "$link" ] || { echo "no callback link in mail" >&2; return 1; }
  curl -s -c "$jar" -b "$jar" -o /dev/null "$link"
  mp "$MAILPIT_URL/api/v1/messages" -X DELETE -H 'Content-Type: application/json' -d "{\"IDs\":[\"$id\"]}" >/dev/null || true
  curl -s -b "$jar" -c "$jar" "$BASE_URL/api/auth/session" | jq -e '.user.id' >/dev/null
}

# session_user_id JAR
session_user_id() { curl -s -b "$1" "$BASE_URL/api/auth/session" | jq -r '.user.id'; }

# trpc_query JAR PROCEDURE [JSON_INPUT]
trpc_query() {
  local jar=$1 proc=$2 input=${3:-}
  if [ -n "$input" ]; then
    curl -s -b "$jar" -G "$BASE_URL/api/trpc/$proc" --data-urlencode "input={\"json\":$input}"
  else
    curl -s -b "$jar" "$BASE_URL/api/trpc/$proc"
  fi
}

# trpc_mutation JAR PROCEDURE SUPERJSON_BODY   (body is the full {"json":..,"meta":..} object)
trpc_mutation() {
  local jar=$1 proc=$2 body=$3
  curl -s -b "$jar" -X POST "$BASE_URL/api/trpc/$proc" -H 'Content-Type: application/json' --data "$body"
}

# upload_receipt JAR FILE -> prints file key
upload_receipt() {
  curl -s -b "$1" -X POST "$BASE_URL/api/upload" -F "file=@$2;type=image/png" | jq -r '.key // empty'
}

# make_test_png PATH  -> 64x64 solid-colour PNG generated with python (no external assets)
make_test_png() {
  python3 - "$1" <<'PY'
import struct, zlib, sys
w = h = 64
raw = b''.join(b'\x00' + bytes([200, 30, 30]) * w for _ in range(h))
def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
PY
}

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }
