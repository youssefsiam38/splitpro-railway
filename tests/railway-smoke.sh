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

# Optional end-to-end workflow. Needs an SMTP sink reachable by the deployment and readable here:
#   MAILPIT_URL=https://mailpit.example MAILPIT_AUTH_FILE=/path/with/user:pass
#   STATE_OUT=/path/state.json   -> write representative state (group, uneven expense, receipt)
#   STATE_IN=/path/state.json    -> verify that state still exists (run after a redeploy)
if [ -n "${MAILPIT_URL:-}" ]; then
  section "real login through the public domain"
  JAR_A="$TEST_TMP/ra.jar"; JAR_B="$TEST_TMP/rb.jar"
  login "railway-a@example.invalid" "$JAR_A" && pass "magic-link login (user A)" || die "login A failed"
  login "railway-b@example.invalid" "$JAR_B" && pass "magic-link login (user B)" || die "login B failed"
  A=$(session_user_id "$JAR_A"); B=$(session_user_id "$JAR_B")
  assert_contains "session cookie is Secure" "Secure" "$(curl -s -D - -o /dev/null -b "$JAR_A" "$BASE_URL/api/auth/session")" || true
  if [ -n "${STATE_OUT:-}" ]; then
    section "write representative state"
    grp=$(trpc_mutation "$JAR_A" group.create '{"json":{"name":"Railway Trip"}}')
    G=$(printf '%s' "$grp" | jq -r '.result.data.json.id'); PUB=$(printf '%s' "$grp" | jq -r '.result.data.json.publicId')
    [ -n "$G" ] && [ "$G" != "null" ] && pass "group created ($G)" || die "group create failed"
    trpc_mutation "$JAR_B" group.joinGroup "{\"json\":{\"groupId\":\"$PUB\"}}" | jq -e '.result' >/dev/null && pass "user B joined" || fail "join failed"
    png="$TEST_TMP/r.png"; make_test_png "$png"
    key=$(upload_receipt "$JAR_A" "$png"); [ -n "$key" ] && pass "receipt uploaded ($key)" || die "upload failed"
    trpc_mutation "$JAR_A" expense.addOrEditExpense "{\"json\":{\"paidBy\":$A,\"name\":\"Railway dinner\",\"category\":\"food\",\"amount\":\"3000\",\"groupId\":$G,\"splitType\":\"EXACT\",\"currency\":\"USD\",\"fileKey\":\"$key\",\"participants\":[{\"userId\":$A,\"amount\":\"2000\"},{\"userId\":$B,\"amount\":\"-2000\"}]},\"meta\":{\"values\":{\"amount\":[\"bigint\"],\"participants.0.amount\":[\"bigint\"],\"participants.1.amount\":[\"bigint\"]}}}" | jq -e '.result.data.json[0].id' >/dev/null && pass "uneven expense created" || die "expense failed"
    bal=$(trpc_query "$JAR_A" expense.getBalances | jq -c --argjson b "$B" '[.result.data.json.balances[] | select(.friendId==$b) | .currencies]')
    assert_contains "user B owes 20.00" '"2000"' "$bal"
    curl -s -b "$JAR_A" -o "$TEST_TMP/r1.webp" "$BASE_URL/api/files/$key"
    jq -n --arg g "$G" --arg key "$key" --arg bal "$bal" --arg sha "$(sha256sum "$TEST_TMP/r1.webp" | cut -d' ' -f1)" --arg a "$A" --arg b "$B" \
      '{group:$g, key:$key, balance:$bal, sha:$sha, a:$a, b:$b}' > "$STATE_OUT"
    pass "state written to $STATE_OUT"
  fi
  if [ -n "${STATE_IN:-}" ]; then
    section "verify state after redeploy"
    G=$(jq -r .group "$STATE_IN"); key=$(jq -r .key "$STATE_IN"); B0=$(jq -r .b "$STATE_IN")
    assert_eq "same user id for A" "$(jq -r .a "$STATE_IN")" "$A"
    assert_contains "group still present" '"Railway Trip"' "$(trpc_query "$JAR_A" group.getAllGroups)"
    bal=$(trpc_query "$JAR_A" expense.getBalances | jq -c --argjson b "$B0" '[.result.data.json.balances[] | select(.friendId==$b) | .currencies]')
    assert_eq "balances identical" "$(jq -r .balance "$STATE_IN")" "$bal"
    curl -s -b "$JAR_A" -o "$TEST_TMP/r2.webp" "$BASE_URL/api/files/$key"
    assert_eq "receipt bytes identical after redeploy" "$(jq -r .sha "$STATE_IN")" "$(sha256sum "$TEST_TMP/r2.webp" | cut -d' ' -f1)"
    section "settle up"
    A_ID=$A; B_ID=$B0
    trpc_mutation "$JAR_B" expense.addOrEditExpense "{\"json\":{\"paidBy\":$B_ID,\"name\":\"Settle\",\"category\":\"settlement\",\"amount\":\"2000\",\"groupId\":$G,\"splitType\":\"SETTLEMENT\",\"currency\":\"USD\",\"participants\":[{\"userId\":$B_ID,\"amount\":\"2000\"},{\"userId\":$A_ID,\"amount\":\"-2000\"}]},\"meta\":{\"values\":{\"amount\":[\"bigint\"],\"participants.0.amount\":[\"bigint\"],\"participants.1.amount\":[\"bigint\"]}}}" | jq -e '.result.data.json[0].id' >/dev/null && pass "settlement recorded" || fail "settlement failed"
    left=$(trpc_query "$JAR_A" expense.getBalances | jq -r --argjson b "$B0" '[.result.data.json.balances[] | select(.friendId==$b) | .currencies[] | select(.amount != "0")] | length')
    assert_eq "balance settled to zero" "0" "$left"
  fi
fi

summary
