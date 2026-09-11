# Third-party notices

This repository contains original wrapper code (Dockerfile, `scripts/entrypoint.sh`, tests, CI, and
documentation) under the MIT License in `LICENSE`. The published container image redistributes the
following third-party software.

| Component | Version | License | Source | Notice location in image |
|---|---|---|---|---|
| SplitPro | v2.1.5 (commit `7e6a401212ce6c7bb109ff69adb1784a3fd6318a`) | MIT, © 2024 OSS Apps | https://github.com/oss-apps/split-pro | `/usr/share/licenses/splitpro-railway/SPLITPRO-LICENSE` (copied verbatim from the tagged commit; also `licenses/SPLITPRO-LICENSE` in this repository) |
| SplitPro runtime dependencies (Next.js, Prisma, NextAuth, sharp, and others) | as bundled in `ossapps/splitpro:v2.1.5` | various OSI licenses per package | `pnpm-lock.yaml` at the upstream commit | inside `/app/node_modules` as shipped by upstream |
| Node.js | 22.16.0 | MIT and others | https://github.com/nodejs/node | base image `node:22.16.0-alpine3.21` |
| Alpine Linux | 3.21.3 | various (mostly MIT/BSD/GPL for individual packages) | https://alpinelinux.org | base image |
| tini | Alpine package | MIT | https://github.com/krallin/tini | added by this wrapper |
| su-exec | Alpine package | MIT | https://github.com/ncopa/su-exec | added by this wrapper |

Not redistributed by this repository, but deployed by the Railway template from its own registry:

| Component | Version | License | Source |
|---|---|---|---|
| PostgreSQL (`ossapps/postgres:17.7-trixie`) | 17.7 | PostgreSQL License | https://www.postgresql.org |
| pg_cron | PGDG package for PostgreSQL 17 | PostgreSQL License | https://github.com/citusdata/pg_cron |

"SplitPro" is the name of the upstream project by OSS Apps. "Splitwise" is a trademark of its owner
and is used only to describe what SplitPro is an alternative to. This template is community
maintained and is not affiliated with, endorsed by, or supported by OSS Apps, Splitwise, or Railway.
