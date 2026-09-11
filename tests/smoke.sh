#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Local smoke test. Requires: docker compose, curl, jq, python3. Builds nothing; run
# `docker compose build` first (CI does), or set SPLITPRO_RAILWAY_IMAGE to a built image.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
mkdir -p "$REPO_ROOT/test-output"
METRICS="$REPO_ROOT/test-output/metrics.txt"

# values from compose.yaml, used only to assert they never appear in logs
LOCAL_DB_PASSWORD='local-test-only-password'
LOCAL_NEXTAUTH_SECRET='local-test-only-secret-not-for-production-use'

section "fresh stack (empty volumes)"
compose down -v --remove-orphans >/dev/null 2>&1 || true
t0=$(date +%s)
compose up -d --no-build
if wait_for_code "$BASE_URL/api/auth/providers" 200 300; then pass "ready"; else compose logs --no-color splitpro | tail -50; die "app never became ready"; fi
cold=$(( $(date +%s) - t0 ))
echo "cold_start_seconds=$cold" | tee "$METRICS"

section "entrypoint behaviour"
# the supervisor polls every 2 s, so its "ready" line can land slightly after the first 200
for _ in $(seq 1 15); do
  compose logs --no-color splitpro | grep -q "SplitPro is ready" && break
  sleep 1
done
logs=$(compose logs --no-color splitpro)
assert_contains "waited for database" "PostgreSQL is accepting connections" "$logs"
assert_contains "fixed volume ownership" "fixing ownership of /app/uploads" "$logs"
assert_contains "readiness gate passed" "SplitPro is ready (GET /api/auth/providers -> 200)" "$logs"
assert_contains "migrations applied on empty db" "migration(s) were applied" "$logs"
assert_not_contains "no DB password in logs" "$LOCAL_DB_PASSWORD" "$logs"
assert_not_contains "no NEXTAUTH_SECRET in logs" "$LOCAL_NEXTAUTH_SECRET" "$logs"

section "process identity"
assert_eq "PID 1 is tini" "tini" "$(compose exec -T splitpro cat /proc/1/comm | tr -d '\r')"
# shellcheck disable=SC2016
app_user=$(compose exec -T splitpro sh -c 'ps -o user,args | awk "/next-server|server.js/ && !/awk/ {print \$1; exit}"' | tr -d '\r')
assert_eq "app process runs as node" "node" "$app_user"
assert_eq "uploads owned by node" "node" "$(compose exec -T splitpro stat -c %U /app/uploads | tr -d '\r')"

section "public routes"
assert_eq "GET / redirects (locale)" "307" "$(http_code "$BASE_URL/")"
assert_eq "GET /api/auth/providers" "200" "$(http_code "$BASE_URL/api/auth/providers")"
assert_contains "email provider advertised" '"email"' "$(curl -s "$BASE_URL/api/auth/providers")"
assert_eq "GET /api/auth/csrf" "200" "$(http_code "$BASE_URL/api/auth/csrf")"
assert_eq "GET /manifest.json (PWA)" "200" "$(http_code "$BASE_URL/manifest.json")"
signin=$(curl -s -L "$BASE_URL/auth/signin")
assert_contains "sign-in page renders SplitPro" "SplitPro" "$signin"
assert_eq "sign-in page 200" "200" "$(http_code -L "$BASE_URL/auth/signin")"

section "unauthenticated access is refused"
assert_eq "tRPC without session -> 401" "401" "$(http_code "$BASE_URL/api/trpc/group.getAllGroups")"
assert_eq "upload without session -> 401" "401" "$(http_code -X POST "$BASE_URL/api/upload")"
assert_eq "receipt fetch without session -> 403" "403" "$(http_code "$BASE_URL/api/files/1/none.webp")"
assert_eq "session endpoint empty" "{}" "$(curl -s "$BASE_URL/api/auth/session" | jq -c .)"

section "login via magic link (two users)"
JAR_A="$TEST_TMP/a.jar"; JAR_B="$TEST_TMP/b.jar"
if login "alice@smoke.invalid" "$JAR_A"; then pass "alice logged in"; else die "alice login failed"; fi
if login "bob@smoke.invalid" "$JAR_B"; then pass "bob logged in"; else die "bob login failed"; fi
A=$(session_user_id "$JAR_A"); B=$(session_user_id "$JAR_B")
[ "$A" != "$B" ] && pass "distinct user ids ($A, $B)" || fail "user ids collide"

section "core workflow: group, uneven expense, settle"
grp=$(trpc_mutation "$JAR_A" group.create '{"json":{"name":"Smoke Trip"}}')
G=$(printf '%s' "$grp" | jq -r '.result.data.json.id // empty')
PUB=$(printf '%s' "$grp" | jq -r '.result.data.json.publicId // empty')
[ -n "$G" ] && pass "group created (id $G)" || { echo "$grp"; die "group create failed"; }
join=$(trpc_mutation "$JAR_B" group.joinGroup "{\"json\":{\"groupId\":\"$PUB\"}}")
printf '%s' "$join" | jq -e '.result' >/dev/null && pass "bob joined group" || fail "bob join failed: $(printf '%s' "$join" | head -c 300)"
# alice pays 30.00, exact split: alice 10.00, bob 20.00 -> bob owes alice 20.00
exp=$(trpc_mutation "$JAR_A" expense.addOrEditExpense "{\"json\":{\"paidBy\":$A,\"name\":\"Smoke dinner\",\"category\":\"food\",\"amount\":\"3000\",\"groupId\":$G,\"splitType\":\"EXACT\",\"currency\":\"USD\",\"participants\":[{\"userId\":$A,\"amount\":\"2000\"},{\"userId\":$B,\"amount\":\"-2000\"}]},\"meta\":{\"values\":{\"amount\":[\"bigint\"],\"participants.0.amount\":[\"bigint\"],\"participants.1.amount\":[\"bigint\"]}}}")
EXP_ID=$(printf '%s' "$exp" | jq -r '.result.data.json[0].id // empty')
[ -n "$EXP_ID" ] && pass "uneven expense created" || { echo "$exp" | head -c 400; die "expense create failed"; }
bal=$(trpc_query "$JAR_A" expense.getBalances)
amt=$(printf '%s' "$bal" | jq -r --argjson b "$B" '.result.data.json.balances[] | select(.friendId==$b) | .currencies[0].amount // "none"')
assert_eq "alice sees bob owes 20.00 (minor units)" "2000" "${amt#-}"
# settlement: bob pays alice 20.00
set_=$(trpc_mutation "$JAR_B" expense.addOrEditExpense "{\"json\":{\"paidBy\":$B,\"name\":\"Settle up\",\"category\":\"settlement\",\"amount\":\"2000\",\"groupId\":$G,\"splitType\":\"SETTLEMENT\",\"currency\":\"USD\",\"participants\":[{\"userId\":$B,\"amount\":\"2000\"},{\"userId\":$A,\"amount\":\"-2000\"}]},\"meta\":{\"values\":{\"amount\":[\"bigint\"],\"participants.0.amount\":[\"bigint\"],\"participants.1.amount\":[\"bigint\"]}}}")
printf '%s' "$set_" | jq -e '.result.data.json[0].id' >/dev/null && pass "settlement recorded" || fail "settlement failed: $(printf '%s' "$set_" | head -c 300)"
bal2=$(trpc_query "$JAR_A" expense.getBalances)
amt2=$(printf '%s' "$bal2" | jq -r --argjson b "$B" '[.result.data.json.balances[] | select(.friendId==$b) | .currencies[] | select(.amount != "0") ] | length')
assert_eq "balance settled to zero" "0" "$amt2"

section "receipt upload to volume"
png="$TEST_TMP/receipt.png"; make_test_png "$png"
key=$(upload_receipt "$JAR_A" "$png")
[ -n "$key" ] && pass "upload accepted (key $key)" || die "upload failed"
assert_eq "receipt served to owner" "200" "$(http_code -b "$JAR_A" "$BASE_URL/api/files/$key")"
assert_contains "receipt is webp" "image/webp" "$(curl -s -o /dev/null -w '%{content_type}' -b "$JAR_A" "$BASE_URL/api/files/$key")"
assert_eq "receipt refused without session" "403" "$(http_code "$BASE_URL/api/files/$key")"
assert_eq "file exists in volume, owned by node" "node" "$(compose exec -T splitpro stat -c %U "/app/uploads/$key" | tr -d '\r')"

section "graceful shutdown (SIGTERM)"
t1=$(date +%s)
compose stop -t 30 splitpro
dur=$(( $(date +%s) - t1 ))
code=$(docker inspect --format '{{.State.ExitCode}}' "$(compose ps -a -q splitpro)")
[ "$dur" -lt 30 ] && pass "stopped in ${dur}s without SIGKILL" || fail "stop took ${dur}s"
case "$code" in 0|143) pass "exit status after SIGTERM is $code" ;; *) fail "unexpected exit status $code" ;; esac
assert_contains "signal forwarded" "stop signal received, forwarding to SplitPro" "$(compose logs --no-color splitpro)"
compose start splitpro
wait_for_code "$BASE_URL/api/auth/providers" 200 120 && pass "restarted after stop" || die "did not come back"

section "essential child death ends the container"
cid=$(compose ps -q splitpro)
before=$(docker inspect --format '{{.RestartCount}}' "$cid")
# shellcheck disable=SC2016
compose exec -T splitpro sh -c 'kill -KILL $(ps -o pid,user | awk "\$2==\"node\"{print \$1; exit}")'
for _ in $(seq 1 30); do
  after=$(docker inspect --format '{{.RestartCount}}' "$cid")
  [ "$after" -gt "$before" ] && break; sleep 2
done
[ "${after:-0}" -gt "$before" ] && pass "container exited and was restarted by policy (restarts $before -> $after)" || fail "container did not exit after child died"
assert_contains "exit propagated in logs" "SplitPro exited with status" "$(compose logs --no-color splitpro)"
wait_for_code "$BASE_URL/api/auth/providers" 200 180 && pass "healthy again after restart" || die "not healthy after child-death restart"

section "database unavailable at boot -> fail fast, non-zero exit"
compose stop postgres
DB_WAIT_TIMEOUT=8 compose up -d --no-build --no-deps --force-recreate splitpro
found=0
for _ in $(seq 1 30); do
  if compose logs --no-color splitpro 2>/dev/null | grep -q "did not accept connections within 8s"; then found=1; break; fi
  sleep 2
done
[ "$found" = 1 ] && pass "bounded DB wait failed with clear message" || fail "no DB wait timeout message"
cid=$(compose ps -a -q splitpro)
code=$(docker inspect --format '{{.State.ExitCode}}' "$cid")
rc=$(docker inspect --format '{{.RestartCount}}' "$cid")
{ [ "$code" = "1" ] || [ "$rc" -gt 0 ]; } && pass "container exited non-zero (exit=$code restarts=$rc)" || fail "container did not exit (exit=$code restarts=$rc)"
compose start postgres
compose up -d --no-build --force-recreate splitpro
wait_for_code "$BASE_URL/api/auth/providers" 200 180 && pass "recovers once database returns" || die "did not recover"

section "missing auth provider -> fail fast"
compose stop splitpro
# shellcheck disable=SC2016  # Go template, not shell
net=$(compose ps -q postgres | xargs docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')
img=$(compose config --images | grep -v -E 'postgres|mailpit' | head -1)
if docker run --rm --network "$net" \
  -e DATABASE_URL="postgresql://splitpro:${LOCAL_DB_PASSWORD}@postgres:5432/splitpro" -e NEXTAUTH_SECRET=x -e NEXTAUTH_URL=http://localhost:3000 \
  "$img" >"$TEST_TMP/noprov.log" 2>&1; then
  fail "container should have exited non-zero"
else
  pass "exits non-zero without auth provider"
fi
assert_contains "clear provider message" "no authentication provider configured" "$(cat "$TEST_TMP/noprov.log")"
assert_not_contains "password not leaked in failure output" "$LOCAL_DB_PASSWORD" "$(cat "$TEST_TMP/noprov.log")"
if docker run --rm --network "$net" \
  -e DATABASE_URL="postgresql://splitpro:${LOCAL_DB_PASSWORD}@postgres:5432/splitpro" -e NEXTAUTH_SECRET=x -e NEXTAUTH_URL=https:// -e EMAIL_SERVER_HOST=mailpit \
  "$img" >"$TEST_TMP/nohost.log" 2>&1; then
  fail "container should have exited non-zero for host-less NEXTAUTH_URL"
else
  pass "exits non-zero when NEXTAUTH_URL has no host"
fi
assert_contains "clear NEXTAUTH_URL message" "NEXTAUTH_URL has no host" "$(cat "$TEST_TMP/nohost.log")"
compose start splitpro
wait_for_code "$BASE_URL/api/auth/providers" 200 180 >/dev/null || die "did not come back after provider test"

section "image metadata"
img=$(compose config --images | grep -v -E 'postgres|mailpit' | head -1)
assert_eq "architecture" "amd64" "$(docker image inspect "$img" --format '{{.Architecture}}')"
labels=$(docker image inspect "$img" --format '{{json .Config.Labels}}')
for l in org.opencontainers.image.source org.opencontainers.image.revision org.opencontainers.image.version org.opencontainers.image.licenses io.splitpro-railway.upstream.version; do
  assert_contains "label $l" "\"$l\"" "$labels"
done
assert_eq "upstream license shipped in image" "MIT License" "$(compose exec -T splitpro head -1 /usr/share/licenses/splitpro-railway/SPLITPRO-LICENSE | tr -d '\r')"

section "metrics"
{
  echo "image_bytes=$(docker image inspect "$img" --format '{{.Size}}')"
  docker stats --no-stream --format '{{.Name}} mem={{.MemUsage}}' | grep splitpro-railway-test | sed 's/^/idle_/'
  echo "pgdata_after_first_boot=$(docker run --rm -v splitpro-railway-test_pgdata:/v alpine du -sh /v | cut -f1)"
} | tee -a "$METRICS"

summary
