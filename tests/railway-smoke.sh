#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Public smoke test against a deployed instance.
#   tests/railway-smoke.sh https://your-app.up.railway.app
# Optional: MAILPIT_URL=https://mailpit.example  -> also performs a real login and workflow.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
export REPO_ROOT
BASE_URL=${1:?usage: railway-smoke.sh https://domain}
BASE_URL=${BASE_URL%/}
export BASE_URL
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
host=${BASE_URL#https://}

section "TLS and redirects"
assert_eq "https root reachable (locale redirect)" "307" "$(http_code "$BASE_URL/")"
assert_contains "valid certificate" "SSL certificate verify ok" "$(curl -sv -o /dev/null "$BASE_URL/api/auth/providers" 2>&1 || true)"
http_redirect=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 15 "http://$host/")
assert_contains "http -> https redirect" "https://$host" "$http_redirect"
assert_contains "signed-in landing redirects to app" "$BASE_URL/en" "$(curl -s -o /dev/null -w '%{redirect_url}' "$BASE_URL/")"

section "readiness and routes"
assert_eq "healthcheck route" "200" "$(http_code "$BASE_URL/api/auth/providers")"
providers=$(curl -s "$BASE_URL/api/auth/providers")
assert_contains "at least one provider" '"id"' "$providers"
assert_contains "provider callback uses public https origin" "\"callbackUrl\":\"$BASE_URL/" "$providers"
assert_eq "sign-in page" "200" "$(http_code -L "$BASE_URL/auth/signin")"
assert_contains "sign-in page is SplitPro" "SplitPro" "$(curl -s -L "$BASE_URL/auth/signin")"
assert_eq "manifest" "200" "$(http_code "$BASE_URL/manifest.json")"

section "unauthenticated access refused"
assert_eq "tRPC -> 401" "401" "$(http_code "$BASE_URL/api/trpc/group.getAllGroups")"
assert_eq "upload -> 401" "401" "$(http_code -X POST "$BASE_URL/api/upload")"
assert_eq "files -> 403" "403" "$(http_code "$BASE_URL/api/files/1/none.webp")"

section "cookies"
hdrs=$(curl -s -D - -o /dev/null "$BASE_URL/api/auth/csrf")
assert_contains "csrf cookie is Secure" "Secure" "$hdrs"
assert_contains "csrf cookie is HttpOnly" "HttpOnly" "$hdrs"
assert_contains "cookie uses __Host- prefix" "__Host-next-auth.csrf-token" "$hdrs"

if [ -n "${MAILPIT_URL:-}" ]; then
  section "real login and workflow through public domain"
  JAR="$TEST_TMP/r.jar"
  login "railway-smoke@example.invalid" "$JAR" && pass "magic-link login over public domain" || fail "login failed"
  grp=$(trpc_mutation "$JAR" group.create '{"json":{"name":"Railway Smoke"}}')
  printf '%s' "$grp" | jq -e '.result.data.json.id' >/dev/null && pass "group created" || fail "group create failed"
fi

summary
