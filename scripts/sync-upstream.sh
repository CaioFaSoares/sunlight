#!/bin/bash
# Rebases this fork's patches onto the latest upstream main. The fork is a small feature set, not a
# release frozen on one upstream version: after this, FORK_REVISION is bumped when the base release
# changed, the tests run, and `make app` builds a version stamped by scripts/fork-version.sh.
#   scripts/sync-upstream.sh [--test]
# Resolve rebase conflicts by hand; the script stops at the first conflict.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Commit or stash the working tree before syncing upstream." >&2
  exit 1
fi
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream https://github.com/spacefarm-digital/sunlight.git
fi

git fetch upstream main --tags
if git merge-base --is-ancestor upstream/main HEAD; then
  echo "Already on $(scripts/fork-version.sh base) ($(git rev-parse --short upstream/main)); nothing to rebase."
  exit 0
fi

BEFORE=$(scripts/fork-version.sh base)
git rebase upstream/main
AFTER=$(scripts/fork-version.sh base)
if [[ "$BEFORE" != "$AFTER" ]]; then
  REVISION=$(scripts/fork-version.sh revision)
  printf '%s\n' "$((REVISION + 1))" > FORK_REVISION
  echo "Upstream moved $BEFORE → $AFTER; FORK_REVISION is now $(scripts/fork-version.sh revision)."
fi
echo "Patch set now on upstream $AFTER; build version $(scripts/fork-version.sh version) ($(scripts/fork-version.sh build))."

if [[ "${1:-}" == "--test" ]]; then
  env PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/swift test
fi
echo "Review the diff, commit the rebase, then run: make app SIGN=\"Apple Development: …\""
