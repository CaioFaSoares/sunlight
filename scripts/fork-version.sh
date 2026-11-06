#!/bin/bash
# The fork's version, derived from the upstream release the patch is currently on. Info.plist stays
# exactly as upstream ships it; `scripts/package.sh` stamps this into the built app only.
#   scripts/fork-version.sh version   # 0.2.3-caio.2
#   scripts/fork-version.sh build     # monotonically increasing CFBundleVersion
#   scripts/fork-version.sh base      # 0.2.3
#   scripts/fork-version.sh revision  # 2
set -euo pipefail
cd "$(dirname "$0")/.."

BASE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BASE_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
REVISION=$(tr -d '[:space:]' < FORK_REVISION)
case "$BASE_BUILD" in
  ''|*[!0-9]*) echo "CFBundleVersion is not numeric: $BASE_BUILD" >&2; exit 1 ;;
esac
case "$REVISION" in
  ''|*[!0-9]*) echo "FORK_REVISION is not numeric: $REVISION" >&2; exit 1 ;;
esac
[[ "$REVISION" -gt 0 ]] || { echo 'FORK_REVISION must be at least 1' >&2; exit 1; }

case "${1:-version}" in
  version) printf '%s-caio.%s\n' "$BASE_VERSION" "$REVISION" ;;
  build) printf '%s\n' "$((BASE_BUILD * 100 + REVISION))" ;;
  base) printf '%s\n' "$BASE_VERSION" ;;
  revision) printf '%s\n' "$REVISION" ;;
  *) echo "usage: scripts/fork-version.sh version|build|base|revision" >&2; exit 64 ;;
esac
