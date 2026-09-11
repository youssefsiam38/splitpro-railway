# Upstream: SplitPro

Facts below were checked against primary sources on 2026-09-11. Re-verify before every upgrade.

## Identity

| Item | Value |
|---|---|
| Project | SplitPro — open-source alternative to Splitwise |
| Repository | https://github.com/oss-apps/split-pro |
| Website / hosted instance | https://splitpro.app |
| Maintainer | OSS Apps (GitHub org `oss-apps`) |
| License | MIT — `LICENSE` at repository root ("Copyright (c) 2024 OSS Apps") |
| Documentation | `README.md`, `docker/README.md`, `docs/CONFIGURATION.md`, `docs/AUTHENTICATION.md`, `docs/RECURRING_TRANSACTIONS.md`, `docs/BANK_TRANSACTIONS.md`, `docs/CURRENCY_CONVERSIONS.md`, `docs/MIGRATING_FROM_V1.md` |
| Security policy | None published upstream (no `SECURITY.md`, GitHub community profile reports none). Report via GitHub issues or the maintainers' contact on the repository. |
| GitHub stars (snapshot) | ~1.4k |
| Last push to `main` (snapshot) | 2026-08-16 |
| Trademark / naming | "SplitPro" is the upstream project name. This template is described as a *community-maintained Railway template for SplitPro* and is *not affiliated with OSS Apps*. "Splitwise" is a third-party trademark used only descriptively. |

## Pinned release

| Item | Value |
|---|---|
| Release | v2.1.5, published 2026-08-01 |
| Git commit | `7e6a401212ce6c7bb109ff69adb1784a3fd6318a` (annotated tag `v2.1.5`) |
| Release notes | https://github.com/oss-apps/split-pro/releases/tag/v2.1.5 (README link fix, OIDC non-standard field fix, Indonesian locale) |
| App image | `docker.io/ossapps/splitpro:v2.1.5` |
| App image index digest | `sha256:efaa52b30d009573c4bf70e5711d6447536914469420db58680e1e6779acde6e` |
| App image platforms | `linux/amd64` (`sha256:ed636cab2989ae925937bff0912de31bcbd56c98022a478c499d6a4af4ffd9b1`), `linux/arm64` (`sha256:b1491128b6b3e20dc60b4797a32b967df78549055ba7a5ab17509d101f4fe1bc`) |
| App image source | Built by upstream GitHub Actions (`.github/workflows/publish.yaml`) from the tagged commit; Dockerfile at repository root. Base `node:22.16.0-alpine3.21`. |
| Database image | `docker.io/ossapps/postgres:17.7-trixie` (PostgreSQL 17.7 + `pg_cron` from PGDG), the image upstream's production Compose file uses |
| Database image index digest | `sha256:7b28a64dca6bc8a5a9df32b69f413939f93d1b87b169748f3754ef25eaa5b962` |
| Database image platforms | `linux/amd64` (`sha256:b44d6c64f22fa812d93f6b6302b55a131a1dfebe1b748fd649a37998ace98753`), `linux/arm64` (`sha256:fb447208a4fa6cd4925c2047506002fa53321ff9a076cd1d21898fb66bb09d68`) |
| Database image source | `docker/postgres/Dockerfile` upstream (`FROM postgres:<major>.<minor>-<base>` + `apt-get install postgresql-<major>-cron`), built by `.github/workflows/postgres.yaml` |
| Checksums | Upstream publishes no separate checksum files; the OCI digests above are the integrity anchor and were read from the registry with `docker buildx imagetools inspect`. |

## Runtime facts (verified by running the pinned image)

| Item | Value |
|---|---|
| Listener | Next.js standalone `node server.js`; honours `PORT` (default 3000) and `HOSTNAME`. Must be `0.0.0.0` on Railway. |
| Process user in upstream image | root (no `USER` directive); a `node` user (uid 1000) exists and `/app/uploads` is pre-chowned to it |
| Schema migrations | Run automatically at startup by `src/instrumentation.ts` → `runMigrations()` when `DOCKER_OUTPUT=1` (set in the image). 26 Prisma migrations applied on an empty database in the test run. |
| Data migrations | Also at startup (`convert-files-to-webp`), gated by `AppMetadata.schema_version` |
| Startup when DB unreachable | Instrumentation throws, **process keeps running and answers HTTP 500 on every route**. It does not exit and does not retry. (Reason for this wrapper's DB wait and readiness supervisor.) |
| Readiness signal | `GET /api/auth/providers` → 200 JSON only after instrumentation (migrations + provider validation) succeeded; 500 otherwise |
| Health endpoint | None upstream. |
| Persistent paths | `/app/uploads` — receipt images as WebP under `<userId>/<uuid>.webp` plus `-thumb.webp`. Database is the other durable state. No other writable state. |
| Cache paths | None on disk; currency-rate and bank caches live in PostgreSQL and are pruned by a `pg_cron` job (`CLEAR_CACHE_CRON_RULE`, `CACHE_RETENTION_INTERVAL`). |
| Temp paths | `formidable` writes uploads to the OS temp dir before conversion, then deletes them. |
| Ports | 3000 (HTTP). No UDP. |

## Dependencies

| Dependency | Required | Notes |
|---|---|---|
| PostgreSQL 16/17/18 **with `pg_cron`** | yes | Migration `20250920192654_recurrence` runs `CREATE EXTENSION IF NOT EXISTS pg_cron` and adds a foreign key to `cron.job`. Without the extension the migration fails and the app never becomes ready. `shared_preload_libraries=pg_cron` and `cron.database_name=<db>` must be set on the server. Railway's stock PostgreSQL image does not ship `pg_cron`, so this template runs upstream's `ossapps/postgres` image as a Railway service. |
| One authentication provider | yes | SMTP (magic link / OTP email), Google OAuth, Authentik, Keycloak, or generic OIDC. **There is no username/password login.** Startup throws `No authentication providers are configured` if none is set. |
| SMTP | conditionally | Required for email login and for `ENABLE_SENDING_INVITES`. Not required when using OAuth/OIDC only. |
| Redis / object storage / workers / browser | no | Not used. Single process. |
| Currency rates | optional | `frankfurter` (default, no key), `openexchangerates` (needs `OPEN_EXCHANGE_RATES_APP_ID`), `nbp`. Outbound HTTPS. |
| Bank sync | optional | GoCardless or Plaid credentials. |
| Web push | optional | VAPID keys (`WEB_PUSH_*`). |
| Discord webhook | optional | error notifications. |

## Environment variables

Authoritative list: upstream `.env.example` and `docs/CONFIGURATION.md`. See README for the table
as exposed by this template.

## First-run behaviour and ownership

- There is no administrator role and no setup wizard. Every person who completes a login on the
  instance gets a normal account. Any two accounts can add each other as friends and share groups.
- With email login enabled, **anyone who reaches the public URL can request a magic link for their
  own address and create an account**. This is the upstream design (it is how friends join).
- Controls available: `DISABLE_EMAIL_SIGNUP=true` blocks *new* email accounts after the owner and
  friends have signed up; using OAuth/OIDC only limits sign-in to that identity provider's users;
  `ENABLE_SENDING_INVITES` controls whether users can email invitations.
- The magic-link token is also delivered as a 5-character lowercase OTP (`generateVerificationToken`
  in `src/server/auth.ts`). Treat the SMTP mailbox as the security boundary.

## Reverse proxy and base URL

- `NEXTAUTH_URL` must equal the browser-visible origin (`https://<domain>`); wrong values break
  OAuth callbacks and magic links.
- `NEXTAUTH_URL_INTERNAL` may be set to `http://localhost:<PORT>` when the container cannot reach
  its own public origin. On Railway the public origin is reachable, and the wrapper sets nothing.
- Behind Railway's edge the app receives plain HTTP; NextAuth derives cookie security from
  `NEXTAUTH_URL` being `https://`, so cookies are `Secure` in production.

## Resource behaviour (measured locally, see README "Resource use")

- Image: wrapper image ~462 MB uncompressed (`linux/amd64`).
- Cold start against a ready database with a warm image: ~8 s to readiness including 26 migrations.
- Idle memory and first-boot volume sizes: recorded in README.

## Backup and restore

- Database: `pg_dump`/`pg_dumpall` from the Postgres service; upstream documents
  `pg_dumpall -c -U postgres > splitpro_backup.sql` and `psql < backup.sql` on a clean database.
- Receipts: copy `/app/uploads` (Railway: `railway volume files download` / SCP).
- Both must be taken together for a consistent restore (receipt `fileKey`s live in the database).

## Upgrade and migration

- New app versions apply schema migrations automatically at startup. Take a database backup first.
- v1 → v2 upgrades have dedicated steps in `docs/MIGRATING_FROM_V1.md` (not applicable to fresh
  template deployments).
- Major PostgreSQL version changes require `pg_dump`/restore; do not repoint an existing data
  directory at a different major.

## Known Railway constraints

- Volume-backed services cannot use replicas and have brief downtime on redeploy.
- Railway's private network is IPv6; the app connects to `postgres.railway.internal` over it.
- Railway healthchecks run only at deploy time (traffic switch), not continuously.
- Upstream's `*_FILE` secret-file convention is not used on Railway; the wrapper does not implement it.
