#!/usr/bin/env bash
# Static validation: shell syntax, shellcheck, compose config, Dockerfile pins.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. tests/lib.sh

section "shell syntax"
for f in scripts/entrypoint.sh tests/*.sh; do
  if sh -n "$f" 2>/dev/null || bash -n "$f"; then pass "syntax $f"; else fail "syntax $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -s sh scripts/entrypoint.sh; then pass "shellcheck entrypoint"; else fail "shellcheck entrypoint"; fi
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck tests"; else fail "shellcheck tests"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if compose config -q; then pass "compose config"; else fail "compose config"; fi

section "dockerfile pins"
base=$(grep -E '^ARG SPLITPRO_IMAGE=' Dockerfile | cut -d= -f2)
if printf '%s' "$base" | grep -qE '@sha256:[0-9a-f]{64}$'; then pass "base image pinned by digest"; else fail "base image not pinned: $base"; fi
if grep -qE '^ENTRYPOINT \["/sbin/tini"' Dockerfile; then pass "tini is PID 1"; else fail "tini entrypoint missing"; fi
for f in .github/workflows/*.yml; do
  if grep -E 'uses: ' "$f" | grep -vqE '@[0-9a-f]{40}( |$)'; then fail "unpinned action in $f"; else pass "actions pinned by SHA in $f"; fi
done

section "no tracked secrets"
if git -C "$REPO_ROOT" rev-parse >/dev/null 2>&1; then
  hits=$(git -C "$REPO_ROOT" ls-files -z | xargs -0 grep -lE '(ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]+)' 2>/dev/null || true)
  if [ -z "$hits" ]; then pass "no credential patterns in tracked files"; else fail "credential pattern in: $hits"; fi
  if git -C "$REPO_ROOT" ls-files | grep -qE '(^|/)\.env$'; then fail ".env is tracked"; else pass ".env not tracked"; fi
else
  echo "  SKIP  not a git checkout"
fi
summary
