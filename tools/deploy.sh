#!/usr/bin/env bash
# Copy the addon into the WoW AddOns folder (WSL). Then /reload in game.
# Usage: tools/deploy.sh [path-to-AddOns]
set -euo pipefail
cd "$(dirname "$0")/.."

ADDONS="${1:-/mnt/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns}"
if [ ! -d "$ADDONS" ]; then
    echo "AddOns folder not found: $ADDONS" >&2
    exit 1
fi

rsync -a --delete \
    --exclude '.git' --exclude 'resources' --exclude 'tests' --exclude 'tools' \
    --exclude 'CLAUDE.md' --exclude 'CLAUDE.local.md' --exclude 'IDEAS.md' \
    --exclude '.luacheckrc' --exclude '.pkgmeta' --exclude '.gitignore' \
    ./ "$ADDONS/FastGroups/"

echo "deployed to $ADDONS/FastGroups"
