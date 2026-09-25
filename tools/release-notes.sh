#!/usr/bin/env bash
# Print one version's section of CHANGELOG.md (without its heading), for the release notes.
# Usage: tools/release-notes.sh <tag>      e.g. tools/release-notes.sh v0.2.0
# Fails when CHANGELOG.md has no "## <tag> - <date>" heading or the section is empty.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: tools/release-notes.sh <tag>}"

NOTES=$(awk -v tag="$TAG" '
    /^## / { if (found) exit; if ($2 == tag) { found = 1; next } }
    found { print }
' CHANGELOG.md)

# trim leading and trailing blank lines
NOTES=$(printf '%s\n' "$NOTES" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

if [ -z "$NOTES" ]; then
    echo "CHANGELOG.md has no section for $TAG" >&2
    exit 1
fi

printf '## FastGroups %s\n\n%s\n' "$TAG" "$NOTES"
