#!/usr/bin/env bash
# Copy the addon into the WoW AddOns folder (WSL). Then /reload in game.
# Copies the same files a release zip gets: files git knows about (committed or new, not
# ignored), minus dotfiles and the .pkgmeta ignore list.
# Usage: tools/deploy.sh [path-to-AddOns]
set -euo pipefail
cd "$(dirname "$0")/.."

ADDONS="${1:-/mnt/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns}"
if [ ! -d "$ADDONS" ]; then
    echo "AddOns folder not found: $ADDONS" >&2
    exit 1
fi

# entries of the "ignore:" list in .pkgmeta
IGNORES=$(awk '
    /^[^ ]/ { inlist = ($0 ~ /^ignore:/); next }
    inlist && /^ *- / { sub(/^ *- */, ""); print }
' .pkgmeta)

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

git ls-files --cached --others --exclude-standard | sort -u | while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "/$f" in */.*) continue ;; esac
    skip=
    while IFS= read -r ig; do
        [ -n "$ig" ] || continue
        case "$f" in "$ig" | "$ig"/*) skip=1; break ;; esac
    done <<< "$IGNORES"
    if [ -z "$skip" ]; then echo "$f"; fi
done > "$STAGE/files"

rsync -a --files-from="$STAGE/files" ./ "$STAGE/FastGroups/"
rsync -a --delete "$STAGE/FastGroups/" "$ADDONS/FastGroups/"

echo "deployed $(wc -l < "$STAGE/files") files to $ADDONS/FastGroups"
