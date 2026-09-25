#!/usr/bin/env bash
# Pre-commit checks: ASCII only, Lua 5.1 syntax, luacheck, unit tests, UI smoke test.
# Needs Lua 5.1 and luacheck. Looks in ~/.local/lua51/bin first, then on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

find_bin() {
    for name in "$@"; do
        if [ -x "$HOME/.local/lua51/bin/$name" ]; then echo "$HOME/.local/lua51/bin/$name"; return; fi
    done
    for name in "$@"; do
        if command -v "$name" >/dev/null 2>&1; then command -v "$name"; return; fi
    done
    echo "missing: $*" >&2
    exit 1
}
LUA=$(find_bin lua5.1 lua)
LUAC=$(find_bin luac5.1 luac)
LUACHECK=$(find_bin luacheck)

if ! "$LUA" -v 2>&1 | grep -q "Lua 5.1"; then
    echo "need Lua 5.1, found: $("$LUA" -v 2>&1)" >&2
    exit 1
fi

FILES=$(find . -path ./resources -prune -o -path ./.git -prune -o -type f \
    \( -name '*.lua' -o -name '*.toc' -o -name '*.md' -o -name '*.py' -o -name '*.sh' \
       -o -name '.luacheckrc' -o -name '.pkgmeta' -o -name '*.txt' \) -print)

echo "== ASCII"
if grep -nP '[^\x00-\x7F]' $FILES; then
    echo "non-ASCII characters found" >&2
    exit 1
fi

echo "== Lua 5.1 syntax"
for f in $(echo "$FILES" | grep '\.lua$'); do
    "$LUAC" -p "$f"
done

echo "== luacheck"
"$LUACHECK" Core UI tests --no-color -q

echo "== unit tests"
"$LUA" tests/run.lua

echo "== UI smoke test"
"$LUA" tests/ui_smoke.lua

echo "all checks passed"
