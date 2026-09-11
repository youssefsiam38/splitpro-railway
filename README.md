# SplitPro on Railway

Split trips, rent, groceries, and dinners with friends, roommates, or family, and let everyone see
who owes whom. **SplitPro** is an open-source alternative to Splitwise with unlimited expenses,
receipts, recurring expenses, multiple currencies, Splitwise import, and a PWA that installs on
phones. This repository is a **community-maintained Railway template** that deploys SplitPro and the
PostgreSQL build it needs in one click. It is **not affiliated with OSS Apps**, the SplitPro authors.

<!-- DEPLOY_BUTTON_START -->
_Deploy button will appear here after the template is published._
<!-- DEPLOY_BUTTON_END -->

## What you get

| Service | Image (immutable) | Public | Volume |
|---|---|---|---|
| `splitpro` | `ghcr.io/youssefsiam38/splitpro-railway:<version>` wrapping `ossapps/splitpro:v2.1.5` | yes (Railway domain, HTTPS) | `/app/uploads` — receipt images |
| `postgres` | `docker.io/ossapps/postgres:17.7-trixie` (PostgreSQL 17.7 + pg_cron), pinned by digest | no (private network only) | `/var/lib/postgresql/data` — database |

Included versions:

| Component | Version |
|---|---|
| SplitPro | v2.1.5 (commit `7e6a401`) |
| PostgreSQL | 17.7 with pg_cron 1.6 |
| Node.js (in image) | 22.16.0 on Alpine 3.21 |
| Wrapper | see [releases](https://github.com/youssefsiam38/splitpro-railway/releases) |

Why a wrapper image and why not Railway's stock Postgres: see [ARCHITECTURE.md](ARCHITECTURE.md).

## Before you deploy: you need an email (SMTP) account

SplitPro has **no username/password login**. People sign in with a magic link or one-time code sent
by email (or via Google / OIDC if you configure those later). The template therefore asks for SMTP
settings at deploy time. Any transactional email provider works (Resend, Postmark, Brevo, Mailgun,
SES, a Gmail app password, your own server). You need:

- host, port (usually `587`), username, password
- a sender address the provider allows you to send from

## First run (about 5 minutes)

1. Click **Deploy on Railway**. Fill in the five SMTP fields. Everything else is generated.
2. Wait until both services show a green check. First boot initialises PostgreSQL, applies 26
   schema migrations, and starts SplitPro; this usually takes 1–3 minutes.
3. Open the `splitpro` service's public URL. You land on the sign-in page.
4. Enter your email. Open the email and click the link (or type the code).
5. You are in. Set your default currency in Account, create a group, and add friends by email.
   Friends receive an invitation email if `ENABLE_SENDING_INVITES` is `true` (default).
6. Once everyone you want has signed up, consider setting `DISABLE_EMAIL_SIGNUP=true` on the
   `splitpro` service so strangers who find your URL cannot create accounts (see Security).

Install it on your phone: open the URL in Safari/Chrome and use "Add to Home Screen".

## Environment variables

### `splitpro` service

| Variable | Required | Set by template | Description | Example |
|---|---|---|---|---|
| `DATABASE_URL` | yes | reference to `postgres` (`postgresql://${{postgres.POSTGRES_USER}}:${{postgres.POSTGRES_PASSWORD}}@${{postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{postgres.POSTGRES_DB}}`) | Connection string over Railway private networking | — |
| `NEXTAUTH_SECRET` | yes | generated `${{secret(64, "abcdef0123456789")}}` | Signs sessions and tokens. 64 hex chars. | — |
| `NEXTAUTH_URL` | yes | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public origin. Change only when you attach a custom domain. | `https://splitpro.example.com` |
| `PORT` | yes | Railway | Listening port. Do not set manually. | — |
| `HOSTNAME` | yes | image default `0.0.0.0` | Bind address. | — |
| `FROM_EMAIL` | **yes, you** | — | Sender address for sign-in and invite emails | `splitpro@example.com` |
| `EMAIL_SERVER_HOST` | **yes, you** | — | SMTP host | `smtp.resend.com` |
| `EMAIL_SERVER_PORT` | **yes, you** | default `587` | SMTP port | `587` |
| `EMAIL_SERVER_USER` | **yes, you** | — | SMTP username | `resend` |
| `EMAIL_SERVER_PASSWORD` | **yes, you** | — | SMTP password or API key | — |
| `EMAIL_TLS_REJECT_UNAUTHORIZED` | no | `1` | Set `0` only for relays with self-signed certificates | `1` |
| `DEFAULT_HOMEPAGE` | no | `/balances` | Route `/` redirects to after login. Upstream default `/home` is a marketing page. | `/balances` |
| `ENABLE_SENDING_INVITES` | no | `true` | Let users email invitations to friends | `true` |
| `DISABLE_EMAIL_SIGNUP` | no | `false` | When `true`, only existing accounts can sign in by email | `false` |
| `UPLOAD_MAX_FILE_SIZE_MB` | no | `10` | Receipt upload limit | `10` |
| `CURRENCY_RATE_PROVIDER` | no | `frankfurter` | `frankfurter`, `openexchangerates` (needs `OPEN_EXCHANGE_RATES_APP_ID`), or `nbp` | `frankfurter` |
| `CLEAR_CACHE_CRON_RULE` | no | `0 2 * * 0` | pg_cron schedule (UTC) for pruning cached rates/bank data. No ranges or lists. | `0 2 * * 0` |
| `CACHE_RETENTION_INTERVAL` | no | `2 days` | PostgreSQL interval for cache retention | `2 days` |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | no | empty | Enables "Sign in with Google". Redirect URI: `https://<domain>/api/auth/callback/google` | — |
| `OIDC_NAME`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_WELL_KNOWN_URL` | no | empty | Generic OIDC provider. Callback: `https://<domain>/api/auth/callback/<oidc_name lowercased>` | — |
| `AUTHENTIK_*`, `KEYCLOAK_*` | no | empty | See upstream `docs/AUTHENTICATION.md` | — |
| `WEB_PUSH_PUBLIC_KEY`, `WEB_PUSH_PRIVATE_KEY`, `WEB_PUSH_EMAIL` | no | empty | Browser push notifications (`npx web-push generate-vapid-keys`) | — |
| `PLAID_*`, `GOCARDLESS_*` | no | empty | Bank transaction import | — |
| `DISCORD_WEBHOOK_URL`, `FEEDBACK_EMAIL` | no | empty | Error notifications, feedback address | — |
| `DB_WAIT_TIMEOUT` | no | `180` | Wrapper: seconds to wait for PostgreSQL before exiting non-zero | `180` |
| `APP_READY_TIMEOUT` | no | `300` | Wrapper: seconds to wait for the app to answer `200` before exiting non-zero | `300` |

### `postgres` service

| Variable | Set by template | Description |
|---|---|---|
| `POSTGRES_USER` | `splitpro` | Database role (superuser inside this container, as in the official image) |
| `POSTGRES_PASSWORD` | generated `${{secret(32)}}` | Never shown in the app service; referenced by `DATABASE_URL` |
| `POSTGRES_DB` | `splitpro` | Database name. Must match `cron.database_name` in the start command; do not change. |
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Subdirectory so PostgreSQL tolerates the volume's `lost+found` |

Start command: `docker-entrypoint.sh postgres -c shared_preload_libraries=pg_cron -c cron.database_name=splitpro -c cron.timezone=UTC`

## Persistent paths

| Service | Path | Contents | Backup |
|---|---|---|---|
| `splitpro` | `/app/uploads` | receipt images: `<userId>/<uuid>.webp`, `<uuid>-thumb.webp` | copy the directory |
| `postgres` | `/var/lib/postgresql/data` (`PGDATA=…/pgdata`) | all groups, expenses, users, sessions, pg_cron jobs | `pg_dump` |

Back up both together: receipt keys are stored in the database.

## Public routes

| Route | Auth | Purpose |
|---|---|---|
| `/` | no | redirects to the localised app, then to `DEFAULT_HOMEPAGE` or sign-in |
| `/auth/signin` | no | sign-in page |
| `/api/auth/*` | no | NextAuth (providers, csrf, callbacks, session) |
| `/api/auth/providers` | no | **Railway healthcheck path** — `200` only after migrations and provider validation succeeded |
| `/api/trpc/*` | session | application API |
| `/api/upload` | session | receipt upload |
| `/api/files/*` | session | receipt download |
| `/manifest.json`, `/sw.js` | no | PWA |

Only the `splitpro` service has a public domain. PostgreSQL is reachable solely on the private
network.

## Run locally

Requires Docker with Compose v2, `curl`, `jq`, `python3`. The Compose stack mirrors the Railway
topology and adds [Mailpit](https://mailpit.axllent.org/) as a stand-in SMTP server so you can
complete a real login without an email account.

```bash
docker compose build
docker compose up -d
# app: http://localhost:3000   mail inbox: http://localhost:8025
```

Tests (the same ones CI runs):

```bash
tests/static.sh        # shellcheck, compose config, pinned digests and action SHAs
tests/smoke.sh         # cold start, routes, login, group + uneven expense + settlement, upload, SIGTERM, child death, DB-down
tests/persistence.sh   # state and receipt survive container recreation
tests/railway-smoke.sh https://your-app.up.railway.app   # public checks against a deployment
```

## Backup and restore

Database (from your machine, using the Railway CLI linked to the project):

```bash
railway ssh --service postgres -- pg_dump -U splitpro -d splitpro -Fc > splitpro-$(date +%F).dump
```

Receipts:

```bash
railway volume files download --service splitpro /app/uploads ./uploads-backup
```

Restore onto a fresh deployment: stop the `splitpro` service, `pg_restore` into the new database
with the same `POSTGRES_USER`/`POSTGRES_DB`, upload the receipts directory back to `/app/uploads`,
start `splitpro`. Upstream notes: `docker/README.md` "Migrating instance".

## Upgrades

- Each wrapper release pins one SplitPro version and one PostgreSQL image by digest. Tags are never
  moved. Release notes list the upstream version and any migration notes.
- To upgrade an existing deployment, change the `splitpro` service image to the new
  `ghcr.io/youssefsiam38/splitpro-railway:<version>` tag. Migrations run automatically at startup.
  Take a database backup first.
- PostgreSQL major upgrades are not automatic; they require dump and restore.
- Process for maintainers: [MAINTENANCE.md](MAINTENANCE.md).

## Resource use and cost

Railway bills for CPU, memory, volume storage, and egress; see
[railway.com/pricing](https://railway.com/pricing) for current rates. Measured locally with the
pinned images (values will differ on Railway):

| Metric | Value |
|---|---|
| `splitpro` memory | ~165 MiB idle after boot; ~375 MiB after the smoke workflow (logins, uploads, image conversion) |
| `postgres` memory | ~30–36 MiB idle |
| Cold start to ready (database already up, image cached) | ~8 s; first boot with `initdb` and migrations: typically 1–3 min on Railway |
| Wrapper image size (`linux/amd64`, uncompressed) | ~462 MB |
| Database volume after first boot | ~47 MB |
| Receipts volume | grows with uploads; each receipt is stored as a ≤1200 px WebP plus a thumbnail |

Cost drivers: two always-on containers (SplitPro does not sleep well because it runs a notification
poller), volume size, and egress from receipt downloads. Nothing here is free tier by default.

## Security

- **Who can sign up.** With email login, anyone who reaches your URL and controls an email address
  can create an account on your instance. This is upstream's design so friends can join. After your
  group has signed up, set `DISABLE_EMAIL_SIGNUP=true`. Using Google or OIDC only restricts sign-in
  to that identity provider.
- **There is no administrator account** and no setup wizard; nothing can be "claimed" ahead of you.
  Each user only sees groups and friends they are part of.
- **Secrets** are generated per deployment by Railway and never printed by the wrapper. Logs contain
  variable names only.
- **The app runs as an unprivileged user** (`node`); only the entrypoint runs as root to fix volume
  ownership on first boot.
- **Sign-in codes** are 5-character one-time codes emailed alongside the link (upstream behaviour);
  the mailbox is the security boundary. Use a reputable SMTP provider with 2FA.
- PostgreSQL has no public port. Do not add a TCP proxy unless you need external access, and remove
  it afterwards.
- Report wrapper issues via [SECURITY.md](SECURITY.md).

## Known limitations

- Single replica per service (volumes cannot be replicated on Railway); redeploys cause a few
  seconds of downtime.
- Railway healthchecks run at deploy time only; a database outage after startup shows as HTTP 500s.
- SMTP is required at deploy time even if you intend to use Google/OIDC only; you can blank the SMTP
  variables afterwards once another provider is configured.
- Bank sync (Plaid/GoCardless), currency providers, and web push need third-party accounts.
- Recurring-expense schedules use pg_cron syntax (no ranges or lists) and run in UTC.
- `linux/arm64` images are published because the base images support it, but Railway runs `amd64`;
  arm64 is build-tested only.

## Legal and data

Your deployment stores personal financial data of everyone in your groups. You are the data
controller: choose a Railway region appropriate for your users, keep backups, and inform your
group. Uploaded receipts may contain third-party personal data; only upload what you are allowed to.

## Links

- Upstream: https://github.com/oss-apps/split-pro (MIT) — docs in `docs/` and `docker/README.md`
- Upstream hosted instance: https://splitpro.app
- Wrapper image: https://github.com/youssefsiam38/splitpro-railway/pkgs/container/splitpro-railway
- License for this repository: [MIT](LICENSE). Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- Architecture and decisions: [ARCHITECTURE.md](ARCHITECTURE.md) · Upstream facts: [UPSTREAM.md](UPSTREAM.md) · Marketplace audit: [MARKETPLACE_AUDIT.md](MARKETPLACE_AUDIT.md)
