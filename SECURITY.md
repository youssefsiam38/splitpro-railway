# Security policy

## Scope

This repository ships a thin wrapper image and Railway template around SplitPro. Two kinds of
issues exist:

| Issue is in… | Report to |
|---|---|
| the wrapper: `Dockerfile`, `scripts/entrypoint.sh`, template variable wiring, exposure of a service that should be private, secrets appearing in logs, CI/publishing pipeline | this repository — open a private advisory via GitHub "Report a vulnerability" on https://github.com/youssefsiam38/splitpro-railway/security, or an issue without exploit details if advisories are unavailable |
| SplitPro itself (authentication, authorization, data handling, dependencies) | upstream at https://github.com/oss-apps/split-pro (no published security policy as of 2026-09-11; use a GitHub issue asking for a private channel) |
| PostgreSQL or pg_cron | their respective projects |

Please do not include working exploit payloads or other people's data in public issues.

## What this wrapper does and does not protect

- Runs the application as the unprivileged `node` user; only the entrypoint runs as root to fix
  volume ownership.
- Never prints variable values; logs contain only variable names and pass/fail states.
- Pins every input by digest and every GitHub Action by commit SHA.
- Does **not** add authentication or rate limiting in front of SplitPro. The sign-in model (magic
  link, OTP, OAuth/OIDC) is upstream's. Read the README "Security" section before opening the
  deployment to strangers.

## Supported versions

Only the newest published tag receives fixes. Upgrades are published as new immutable tags; existing
tags are never moved.
