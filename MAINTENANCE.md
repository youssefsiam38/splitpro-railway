# Maintenance

## Watch upstream

- Releases: https://github.com/oss-apps/split-pro/releases (`gh release list -R oss-apps/split-pro`)
- Image tags: `curl -s https://hub.docker.com/v2/repositories/ossapps/splitpro/tags?page_size=20 | jq -r '.results[].name'`
- Postgres image: `.../repositories/ossapps/postgres/tags`
- Security: upstream has no advisory channel; watch Releases, Dependabot alerts on the upstream
  repository, and `pnpm-lock.yaml` changes. Review at least monthly, and within 48 h of any upstream
  release that mentions security or Prisma/NextAuth bumps.

## Verify new inputs

```bash
docker buildx imagetools inspect ossapps/splitpro:vX.Y.Z        # index digest + per-arch digests
docker buildx imagetools inspect ossapps/postgres:17.7-trixie
gh api repos/oss-apps/split-pro/git/ref/tags/vX.Y.Z --jq .object  # tag -> commit
```

Record the digests, commit, and release date in `UPSTREAM.md` and `THIRD_PARTY_NOTICES.md`. Re-vendor
`licenses/SPLITPRO-LICENSE` from the tagged commit if it changed.

## Upgrade procedure

1. Update `ARG SPLITPRO_IMAGE=` (digest) and `ARG SPLITPRO_VERSION=` in `Dockerfile`; update
   `compose.yaml` if the Postgres digest changes.
2. Read upstream release notes for new required variables, migration notes, or pg_cron changes.
3. `docker compose build && tests/static.sh && tests/smoke.sh && tests/persistence.sh`.
4. **Upgrade test against existing data:** start the *previous* release's stack
   (`SPLITPRO_RAILWAY_IMAGE=ghcr.io/youssefsiam38/splitpro-railway:<prev> docker compose up -d --no-build`),
   run `tests/persistence.sh`'s "write state" portion (or use the app), then
   `docker compose down` and `docker compose up -d` with the new image against the same volumes.
   Confirm `A total of N migration(s) were applied` with N ≥ 0 and no errors, then log in and check
   balances and receipts.
5. Update README versions table, UPSTREAM.md, THIRD_PARTY_NOTICES.md.
6. Commit to `main`, wait for the `test` workflow to pass.
7. Tag: `git tag -a vA.B.C -m "vA.B.C: SplitPro vX.Y.Z"` and push the tag. Never move or reuse a
   tag; if publication fails, fix and tag the next patch.
8. `gh run watch --exit-status` on the `publish-image` run. Record the digest from the run summary.
9. Anonymous pull check: `DOCKER_CONFIG=$(mktemp -d) docker pull ghcr.io/youssefsiam38/splitpro-railway:A.B.C`.
10. `gh release create vA.B.C --notes-file <notes>` listing upstream version, digests, architectures,
    migration notes, test evidence. No AI attribution anywhere.
11. Update the Railway template's `splitpro` service image to the new immutable tag
    (`ghcr.io/youssefsiam38/splitpro-railway:A.B.C`) in the template composer, save, and run the
    clean-room deploy (below) before considering the marketplace version changed.

## Railway template operations

- Metadata (description, category, overview, icon):
  `npx -y @railway/cli@latest templates update <TEMPLATE_ID> --category Other --description "..." --readme-file RAILWAY_TEMPLATE.md --json`
- Service configuration (image, variables, volumes, healthcheck, start command) is edited in the
  template composer in the Railway dashboard; the CLI does not expose it. Verify every service after
  saving.
- Clean-room deploy: `npx -y @railway/cli@latest init --name splitpro-cleanroom-$(date +%s)` then
  `railway deploy --template <CODE>` (or use the template's own deploy page), fill only SMTP with
  test credentials, wait for SUCCESS, run `tests/railway-smoke.sh https://<domain>`, then delete the
  project by ID: `railway project delete --project <ID> --yes --json`.
- Rollback: set the `splitpro` service image in the template back to the last known-good tag and
  save. Existing deployments are unaffected until they redeploy.
- Unpublish (keeps existing user deployments running):
  `npx -y @railway/cli@latest templates unpublish <TEMPLATE_ID_OR_CODE> --yes --json`.
- Metrics and support: Railway dashboard → Templates → this template shows deployment count and
  health; support questions arrive in the Railway Template Queue and by GitHub issues. Answer with a
  tested fix and fold recurring issues into README "Known limitations".

## Dependency updates

GitHub Actions in this repository are pinned to commit SHAs with a version comment. Update them by
bumping the SHA and comment together after reading the action's release notes. Dependabot may open
pull requests for Actions but must never publish an image; publication only happens on a manually
created tag after CI passes.

## Cadence

- Weekly: glance at upstream releases and the Railway template queue.
- Monthly: full dependency and advisory review; rebuild the current tag locally to confirm inputs
  are still pullable by digest.
- On every upstream release: evaluate within a week; ship a patch if it fixes bugs or security.
