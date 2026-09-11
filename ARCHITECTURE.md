# Architecture

## Selected topology: two Railway services

```
                 HTTPS (Railway edge)
                        │
                        ▼
┌───────────────────────────────────────────┐        ┌────────────────────────────────────┐
│ service: splitpro                          │  IPv6  │ service: postgres                   │
│ image: ghcr.io/youssefsiam38/splitpro-     │ private│ image: ossapps/postgres:17.7-trixie │
│        railway:<version>                   │ ─────▶ │        (PG 17.7 + pg_cron)           │
│ tini → entrypoint → node server.js (node)  │  5432  │ docker-entrypoint.sh postgres        │
│ volume: /app/uploads (receipts)            │        │   -c shared_preload_libraries=pg_cron│
│ public domain, healthcheck                 │        │ volume: /var/lib/postgresql/data     │
└───────────────────────────────────────────┘        │ no public networking                 │
                                                     └────────────────────────────────────┘
```

| Service | Source | Public | Volume | Why |
|---|---|---|---|---|
| `splitpro` | this repository's wrapper image (GHCR, version tag that is never moved; digest recorded per release) | yes, Railway domain, port from `PORT` | `/app/uploads` | Upstream expects a single web process; receipts are stored on local disk. |
| `postgres` | `ossapps/postgres:17.7-trixie` (version tag; digest recorded in UPSTREAM.md — Railway's template generator rejects `@sha256` image references, verified 2026-09-11) | no | `/var/lib/postgresql/data` (`PGDATA` set to a subdirectory) | SplitPro's migrations require `pg_cron`, which Railway's stock Postgres does not ship. Upstream builds and ships this image and uses it in its own production Compose file. |

Inter-service traffic uses Railway private networking (`postgres.railway.internal`), wired with a
reference variable so the connection string is never duplicated:

```
DATABASE_URL = postgresql://${{postgres.POSTGRES_USER}}:${{postgres.POSTGRES_PASSWORD}}@${{postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{postgres.POSTGRES_DB}}
```

## Why a wrapper image at all

The upstream image is almost Railway-ready, but two behaviours make a stock image fragile as a
one-click template:

1. **Cold-start race.** On first deploy both services start together. PostgreSQL needs 10–40 s for
   `initdb`. If SplitPro connects before that, its startup instrumentation throws, and the process
   then **stays alive answering HTTP 500 forever**. Railway's restart policy never fires because
   nothing exited. The user sees a "failed healthcheck" deployment and has to redeploy manually.
2. **Root process.** The upstream container runs the app as root. Receipt uploads are the only
   writable state, and there is no reason for the web process to have root.

The wrapper (`Dockerfile`, `scripts/entrypoint.sh`) adds, on top of the digest-pinned upstream image:

- `tini` as PID 1 (signal forwarding, zombie reaping).
- A bounded TCP wait for the database host parsed from `DATABASE_URL` (default 180 s). Credentials
  are never logged.
- Ownership fix of `/app/uploads` on first boot, then privilege drop to `node` with `su-exec`.
- A readiness supervisor: polls `GET /api/auth/providers` on loopback; if it does not return 200
  within `APP_READY_TIMEOUT` (default 300 s), it stops the app and **exits non-zero** so Railway's
  restart policy kicks in. If the app process dies at any time, the container exits with its code.
- SIGTERM/SIGINT are forwarded to the app; the container exits with the app's status.

Application code, Next.js build, Prisma migrations, and the upstream `server.js` are untouched.

## Health check

Railway healthcheck path: `/api/auth/providers`, timeout 300 s.

What a `200` from this route proves for the *new* deployment:

- The Node process is listening on `PORT` at `0.0.0.0`.
- Next.js `instrumentation.register()` finished: the database was reachable, all Prisma
  migrations applied, data migrations ran, and at least one auth provider is configured
  (`validateAuthEnv()` throws otherwise). Any failure there makes every route answer 500.

The wrapper's own DB wait runs before the app starts, so the route cannot report ready while the
database is down at boot. The route is unauthenticated, fast, and returns only provider names and
URLs already visible on the sign-in page — no versions, credentials, or internal addresses.

Railway healthchecks gate the traffic switch at deploy time only; they are not continuous liveness
probes. A database outage *after* a successful start is surfaced by the app's own 500 responses and
Railway's HTTP metrics, not by the healthcheck.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Upstream image directly, no wrapper | Cold-start race leaves a permanently broken container (see above); app runs as root; no way to fail fast on missing variables. |
| Railway's stock PostgreSQL template/image | No `pg_cron`; migration `20250920192654_recurrence` fails; recurring expenses and cache pruning are hard dependencies in the schema, not optional features. |
| Building our own Postgres+pg_cron image | Upstream already builds, tests, and publishes exactly this image for its own production Compose. Reusing it by digest keeps one fewer artifact to maintain and keeps parity with upstream's supported setup. |
| Single container with PostgreSQL embedded | Worse durability and upgrade story; couples database restarts to app deploys; contradicts upstream's production shape; Railway gives each service its own volume anyway. |
| Reverse proxy in front of the app to serve a synthetic `/healthz` with `SELECT 1` | Adds a hop that could break multipart uploads, streaming, and push; the marginal benefit is nil because Railway healthchecks are deploy-time only and the upstream route already reflects boot-time DB state. |
| `railway add --database postgres` plus manual `CREATE EXTENSION` | Extension binaries are not present in the image; cannot be fixed with SQL. |
| Path-prefix routing or multiple public domains | Not needed; one public service. |

## Persistence and replicas

Both services have exactly one volume each (Railway limit). Neither can use replicas. Redeploys of
either service cause brief downtime while the volume is re-attached. Receipts and the database must
be backed up together.

## Secrets and first run

- `NEXTAUTH_SECRET`: generated per deployment with `${{secret(64, "abcdef0123456789")}}`.
- `POSTGRES_PASSWORD`: generated per deployment with `${{secret(32)}}` on the `postgres` service and
  referenced by the app.
- `NEXTAUTH_URL`: `https://${{RAILWAY_PUBLIC_DOMAIN}}`.
- Authentication provider: SplitPro has no password login, so the template requires SMTP settings
  from the deployer (the most portable provider) and offers Google / OIDC as optional alternatives.
- First-run ownership: there is no admin account to claim. See UPSTREAM.md "First-run behaviour"
  and README "Security" for the exact model and the `DISABLE_EMAIL_SIGNUP` control.

## Process supervision (single-container, multi-step)

```
PID 1  /sbin/tini -- entrypoint
  └─ sh entrypoint            (root: validation, DB wait, chown, supervisor)
       └─ su-exec node node server.js   (node: the application)
```

- Exactly one listener, `0.0.0.0:$PORT`.
- Any exit of `node server.js` ends the container with the same status.
- SIGTERM → forwarded → wait → exit. Tested in `tests/smoke.sh`.
