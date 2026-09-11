#!/bin/sh
# splitpro-railway entrypoint
#
# Runs as PID 1's child under tini. Responsibilities:
#   1. validate required variables (names only; values are never printed)
#   2. wait, with a bound, for the PostgreSQL TCP endpoint to accept connections
#   3. make the receipts volume writable by the unprivileged `node` user
#   4. start SplitPro (`node server.js`) as `node`
#   5. gate on the app's own readiness route and exit non-zero if it never becomes ready,
#      so Railway restarts the service instead of leaving a container that answers 500s
#   6. forward SIGTERM/SIGINT to the app and exit with its status when it stops
set -u

log()  { printf '[splitpro-railway] %s\n' "$*" >&2; }
fail() { log "FATAL: $*"; exit 1; }

: "${PORT:=3000}"
: "${HOSTNAME:=0.0.0.0}"
: "${DB_WAIT_TIMEOUT:=180}"
: "${APP_READY_TIMEOUT:=300}"
: "${UPLOADS_DIR:=/app/uploads}"
: "${READINESS_PATH:=/api/auth/providers}"
export PORT HOSTNAME

# --- DATABASE_URL, or assemble it from POSTGRES_* the way upstream start.sh does -------------
if [ -z "${DATABASE_URL:-}" ] && [ -n "${POSTGRES_USER:-}" ] && [ -n "${POSTGRES_PASSWORD:-}" ] \
   && [ -n "${POSTGRES_DB:-}" ] && [ -n "${POSTGRES_HOST:-${POSTGRES_CONTAINER_NAME:-}}" ]; then
  DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST:-${POSTGRES_CONTAINER_NAME}}:${POSTGRES_PORT:-5432}/${POSTGRES_DB}"
  export DATABASE_URL
  log "DATABASE_URL assembled from POSTGRES_* variables"
fi

# --- required variables ----------------------------------------------------------------------
missing=""
for v in DATABASE_URL NEXTAUTH_SECRET NEXTAUTH_URL; do
  eval "val=\${$v:-}"
  [ -n "$val" ] || missing="$missing $v"
done
[ -z "$missing" ] || fail "missing required variable(s):$missing"

case "$NEXTAUTH_URL" in
  http://*|https://*) ;;
  *) fail "NEXTAUTH_URL must start with http:// or https:// (got a value with a different scheme)" ;;
esac

# --- at least one authentication provider (SplitPro has no password login) --------------------
has_provider=0
[ -n "${EMAIL_SERVER_HOST:-}" ] && has_provider=1
[ -n "${GOOGLE_CLIENT_ID:-}" ] && [ -n "${GOOGLE_CLIENT_SECRET:-}" ] && has_provider=1
[ -n "${AUTHENTIK_ID:-}" ] && [ -n "${AUTHENTIK_SECRET:-}" ] && [ -n "${AUTHENTIK_ISSUER:-}" ] && has_provider=1
[ -n "${KEYCLOAK_ID:-}" ] && [ -n "${KEYCLOAK_SECRET:-}" ] && [ -n "${KEYCLOAK_ISSUER:-}" ] && has_provider=1
[ -n "${OIDC_CLIENT_ID:-}" ] && [ -n "${OIDC_CLIENT_SECRET:-}" ] && [ -n "${OIDC_WELL_KNOWN_URL:-}" ] && has_provider=1
[ "$has_provider" = 1 ] || fail "no authentication provider configured. Set the SMTP variables (EMAIL_SERVER_HOST, EMAIL_SERVER_PORT, EMAIL_SERVER_USER, EMAIL_SERVER_PASSWORD, FROM_EMAIL) or GOOGLE_CLIENT_ID + GOOGLE_CLIENT_SECRET, or OIDC_CLIENT_ID + OIDC_CLIENT_SECRET + OIDC_WELL_KNOWN_URL."

# --- wait for PostgreSQL ---------------------------------------------------------------------
# host:port are extracted with sed; the credential portion is never logged.
hostport=$(printf '%s' "$DATABASE_URL" | sed -E 's#^[a-zA-Z]+://([^@/]*@)?([^/?]+).*#\2#')
case "$hostport" in
  \[*\]:*) db_host=${hostport%]:*}; db_host=${db_host#[}; db_port=${hostport##*]:} ;;
  \[*\])   db_host=${hostport#[}; db_host=${db_host%]}; db_port=5432 ;;
  *:*)     db_host=${hostport%:*}; db_port=${hostport##*:} ;;
  *)       db_host=$hostport; db_port=5432 ;;
esac
[ -n "$db_host" ] || fail "could not determine database host from DATABASE_URL"

log "waiting up to ${DB_WAIT_TIMEOUT}s for PostgreSQL at ${db_host}:${db_port}"
deadline=$(( $(date +%s) + DB_WAIT_TIMEOUT ))
until node -e '
  const [host, port] = process.argv.slice(1);
  const s = require("net").connect({ host, port: Number(port) });
  s.setTimeout(3000);
  s.once("connect", () => { s.destroy(); process.exit(0); });
  s.once("timeout", () => { s.destroy(); process.exit(1); });
  s.once("error", () => process.exit(1));
' "$db_host" "$db_port" 2>/dev/null; do
  [ "$(date +%s)" -lt "$deadline" ] || fail "PostgreSQL at ${db_host}:${db_port} did not accept connections within ${DB_WAIT_TIMEOUT}s"
  sleep 2
done
log "PostgreSQL is accepting connections"

# --- receipts volume ownership -----------------------------------------------------------------
mkdir -p "$UPLOADS_DIR" || fail "cannot create $UPLOADS_DIR"
if [ "$(id -u)" = "0" ]; then
  owner=$(stat -c '%u' "$UPLOADS_DIR")
  if [ "$owner" != "$(id -u node)" ]; then
    log "fixing ownership of $UPLOADS_DIR for user node"
    chown -R node:node "$UPLOADS_DIR" || fail "cannot chown $UPLOADS_DIR"
  fi
  run_as="su-exec node"
else
  run_as=""
fi
if ! $run_as sh -c "touch '$UPLOADS_DIR/.write-test' && rm -f '$UPLOADS_DIR/.write-test'"; then
  fail "$UPLOADS_DIR is not writable by the application user"
fi

# --- start the app -----------------------------------------------------------------------------
cd /app || fail "/app missing"
log "starting SplitPro on ${HOSTNAME}:${PORT}"
# shellcheck disable=SC2086
$run_as node server.js &
app_pid=$!

# shellcheck disable=SC2317  # invoked via trap
on_signal() {
  log "stop signal received, forwarding to SplitPro"
  kill -TERM "$app_pid" 2>/dev/null
  wait "$app_pid"
  code=$?
  log "SplitPro exited with status $code"
  exit "$code"
}
trap on_signal TERM INT

# --- readiness gate ------------------------------------------------------------------------------
url="http://127.0.0.1:${PORT}${READINESS_PATH}"
deadline=$(( $(date +%s) + APP_READY_TIMEOUT ))
last=""
while :; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    wait "$app_pid"; code=$?
    fail "SplitPro exited during startup with status $code"
  fi
  if last=$(wget -q -T 5 -O /dev/null "$url" 2>&1); then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    kill -TERM "$app_pid" 2>/dev/null; wait "$app_pid"
    fail "SplitPro did not become ready within ${APP_READY_TIMEOUT}s (${last:-no response})"
  fi
  sleep 2
done
log "SplitPro is ready (GET ${READINESS_PATH} -> 200)"

wait "$app_pid"
code=$?
log "SplitPro exited with status $code"
exit "$code"
