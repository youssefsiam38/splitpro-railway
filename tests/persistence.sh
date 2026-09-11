#!/usr/bin/env bash
# Persistence test: write representative state, remove containers (keep volumes), start fresh
# containers, verify the state and the receipt file survive byte-for-byte.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "fresh stack"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --no-build
wait_for_code "$BASE_URL/api/auth/providers" 200 300 || die "not ready"

section "write state"
JAR_A="$TEST_TMP/pa.jar"; JAR_B="$TEST_TMP/pb.jar"
login "carol@persist.invalid" "$JAR_A" || die "carol login failed"
login "dave@persist.invalid" "$JAR_B" || die "dave login failed"
A=$(session_user_id "$JAR_A"); B=$(session_user_id "$JAR_B")
grp=$(trpc_mutation "$JAR_A" group.create '{"json":{"name":"Persist Group"}}')
G=$(printf '%s' "$grp" | jq -r '.result.data.json.id'); PUB=$(printf '%s' "$grp" | jq -r '.result.data.json.publicId')
trpc_mutation "$JAR_B" group.joinGroup "{\"json\":{\"groupId\":\"$PUB\"}}" >/dev/null
png="$TEST_TMP/p.png"; make_test_png "$png"
key=$(upload_receipt "$JAR_A" "$png"); [ -n "$key" ] || die "upload failed"
trpc_mutation "$JAR_A" expense.addOrEditExpense "{\"json\":{\"paidBy\":$A,\"name\":\"Persist rent\",\"category\":\"home\",\"amount\":\"120000\",\"groupId\":$G,\"splitType\":\"EXACT\",\"currency\":\"EUR\",\"fileKey\":\"$key\",\"participants\":[{\"userId\":$A,\"amount\":\"45000\"},{\"userId\":$B,\"amount\":\"-45000\"}]},\"meta\":{\"values\":{\"amount\":[\"bigint\"],\"participants.0.amount\":[\"bigint\"],\"participants.1.amount\":[\"bigint\"]}}}" | jq -e '.result.data.json[0].id' >/dev/null || die "expense failed"
bal_before=$(trpc_query "$JAR_A" expense.getBalances | jq -c --argjson b "$B" '[.result.data.json.balances[] | select(.friendId==$b) | .currencies]')
curl -s -b "$JAR_A" -o "$TEST_TMP/before.webp" "$BASE_URL/api/files/$key"
sha_before=$(sha256sum "$TEST_TMP/before.webp" | cut -d' ' -f1)
pass "state written: group $G, balance $bal_before, receipt $key"

section "remove containers, keep volumes, start fresh containers"
compose down >/dev/null
compose up -d --no-build
wait_for_code "$BASE_URL/api/auth/providers" 200 300 || die "not ready after recreate"
logs=$(compose logs --no-color splitpro)
assert_contains "no migrations re-applied" "A total of 0 migration(s) were applied" "$logs"
assert_not_contains "ownership fix not repeated" "fixing ownership" "$logs"

section "verify state survived"
JAR_A2="$TEST_TMP/pa2.jar"
login "carol@persist.invalid" "$JAR_A2" || die "carol re-login failed"
assert_eq "same user id after restart" "$A" "$(session_user_id "$JAR_A2")"
groups=$(trpc_query "$JAR_A2" group.getAllGroups)
assert_contains "group still listed" '"Persist Group"' "$groups"
bal_after=$(trpc_query "$JAR_A2" expense.getBalances | jq -c --argjson b "$B" '[.result.data.json.balances[] | select(.friendId==$b) | .currencies]')
assert_eq "balances identical" "$bal_before" "$bal_after"
assert_contains "balance is 450.00 EUR owed" '"45000"' "$bal_after"
curl -s -b "$JAR_A2" -o "$TEST_TMP/after.webp" "$BASE_URL/api/files/$key"
assert_eq "receipt bytes identical" "$sha_before" "$(sha256sum "$TEST_TMP/after.webp" | cut -d' ' -f1)"
assert_eq "receipt still owned by node" "node" "$(compose exec -T splitpro stat -c %U "/app/uploads/$key" | tr -d '\r')"

summary
