# Deploy and Host SplitPro

SplitPro is an open-source alternative to Splitwise. Record who paid for dinner, rent, or the trip;
split it equally, by exact amounts, percentages, or shares; attach the receipt; and let everyone see
a live "who owes whom" balance with one-tap settle-up. Unlimited expenses, groups, currencies,
recurring expenses, Splitwise import, and a PWA you can add to your phone's home screen. This is a
community-maintained template and is not affiliated with OSS Apps, the SplitPro authors.

## About Hosting

This template deploys two Railway services:

- **splitpro** — the web app, from a version-specific tag of
  `ghcr.io/youssefsiam38/splitpro-railway` (tags are never moved; each release records its digest)
  that wraps the official `ossapps/splitpro:v2.1.5` image. It adds a wait-for-database step, a readiness gate, and runs the app as a non-root user.
  It gets the public HTTPS domain and a volume at `/app/uploads` for receipt images.
- **postgres** — PostgreSQL 17.7 with the `pg_cron` extension (`ossapps/postgres:17.7-trixie`,
  a version-specific tag whose digest is recorded in the repository). SplitPro's schema requires pg_cron for recurring expenses, so Railway's stock
  PostgreSQL cannot be used. It is private-network only and has its own volume.

Secrets (`NEXTAUTH_SECRET`, `POSTGRES_PASSWORD`) are generated per deployment. `DATABASE_URL` and
`NEXTAUTH_URL` are wired with reference variables, so nothing needs to be copied around. Schema
migrations run automatically on every start. Volume-backed services run as a single replica and
have a few seconds of downtime on redeploy.

## Why Deploy

- Keep your group's financial data on infrastructure you control instead of a SaaS that limits
  free users and mines spending data.
- One click gives you the exact production shape upstream supports (app + pg_cron PostgreSQL),
  with generated secrets and private networking already configured.
- No admin account to claim, no setup wizard: the first thing anyone sees is the sign-in page.
- Pinned versions: the template references version-specific image tags (never `latest`), with
  digests recorded in the repository; upgrades are explicit.

## Common Use Cases

- Trips and holidays with friends: everybody logs what they paid, settle up once at the end.
- Roommates: rent, utilities, and groceries as recurring or one-off expenses.
- Couples and families: shared budget with per-person balances and receipts.
- Moving off Splitwise: import your existing Splitwise groups.

## Dependencies for SplitPro

- An **SMTP account** (host, port, username, password, sender address). SplitPro has no
  username/password login; users sign in through a magic link or code sent by email. Any
  transactional provider works.
- Optionally, Google OAuth or an OIDC provider (Authentik, Keycloak, others) as an alternative or
  additional sign-in method.

### Deployment Dependencies

- Railway account with a plan that allows volumes and two always-on services.
- SMTP credentials entered at deploy time in the `splitpro` service variables:
  `FROM_EMAIL`, `EMAIL_SERVER_HOST`, `EMAIL_SERVER_PORT`, `EMAIL_SERVER_USER`,
  `EMAIL_SERVER_PASSWORD`.
- Source and documentation: https://github.com/youssefsiam38/splitpro-railway
- Upstream project: https://github.com/oss-apps/split-pro (MIT)

## After Deploying

1. Wait for both services to be healthy. First boot initialises PostgreSQL and applies SplitPro's
   26 schema migrations; allow 1–3 minutes.
2. Open the `splitpro` service's public URL. Enter your email on the sign-in page, then click the
   link or type the code from the email you receive.
3. In **Account**, set your default currency. Create a group and add friends by email; they receive
   an invitation if `ENABLE_SENDING_INVITES` is `true` (default).
4. Add the site to your phone's home screen for the app-like experience.
5. When everyone has joined, set `DISABLE_EMAIL_SIGNUP=true` on the `splitpro` service so that
   people who discover your URL cannot create new accounts.
6. Optional: attach a custom domain and update `NEXTAUTH_URL` to match; configure Google/OIDC
   sign-in; set `WEB_PUSH_*` keys for browser notifications; connect Plaid/GoCardless for bank
   import.

Resource expectations: roughly 165 MiB memory for the app at idle (300–400 MiB under use) and about 35 MiB for PostgreSQL, ~50 MB
of database storage after first boot, plus receipt images (each stored as a compressed WebP).
Costs depend on Railway's current CPU/memory/storage/egress pricing.

Limitations: single replica per service; Railway healthchecks gate deploys but are not continuous
monitors; recurring schedules use pg_cron syntax in UTC; bank sync and push need third-party
accounts. Backup the database and the `/app/uploads` volume together.
