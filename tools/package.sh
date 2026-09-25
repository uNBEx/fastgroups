#!/usr/bin/env bash
# Local dry run of the release build: runs the BigWigs packager without uploading.
# The zip and the unpacked addon land in .release/. Release notes come from CHANGELOG.md
# (the newest section unless a tag is given). Committed files only; the packager skips
# untracked ones.
# Usage: tools/package.sh [tag] [--update]    (--update fetches the latest packager)
set -euo pipefail
cd "$(dirname "$0")/.."

PACKAGER=resources/packager/release.sh
URL=https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh

TAG=
UPDATE=
for arg in "$@"; do
    case "$arg" in
        --update) UPDATE=1 ;;
        *) TAG="$arg" ;;
    esac
done

if [ -n "$UPDATE" ] || [ ! -f "$PACKAGER" ]; then
    mkdir -p "$(dirname "$PACKAGER")"
    curl -fsSL "$URL" -o "$PACKAGER"
    chmod +x "$PACKAGER"
fi

if [ -z "$TAG" ]; then
    TAG=$(awk '/^## v/ { print $2; exit }' CHANGELOG.md)
fi
tools/release-notes.sh "$TAG" > RELEASE_NOTES.md

rm -rf .release
mkdir -p .release
if ! "$PACKAGER" -d -r "$PWD/.release" > .release/package.log 2>&1; then
    tail -n 30 .release/package.log >&2
    echo "packager failed, full log: .release/package.log" >&2
    exit 1
fi
grep -iE '^(warning|error)' .release/package.log || true

echo
echo "== zip contents"
unzip -l .release/*.zip
