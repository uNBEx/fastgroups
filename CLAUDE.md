# FastGroups - notes for agents

World of Warcraft **retail** addon (Midnight, client 12.1.x, `## Interface: 120100`) for raid
leaders and assistants. Its only job is sorting players into the raid's built-in subgroups:
a raid-frame-style board with drag and drop, balanced halves (left/right), saved loadouts with
absent/new player reconciliation, planning rosters, and preset sharing (export strings and
hidden addon comms). Only the person arranging groups needs it installed.

## Status
- Stage 1 (done): tooling, research, interactive HTML mockup in `resources/mockup/index.html`
  (gitignored, local only). Waiting for user review of the mockup before Stage 2.
- Stage 2 (next): the Lua addon itself. Planned layout is below.
- Never push to the remote without the user's explicit approval. Local commits are fine.

## Planned layout (Stage 2)
```
FastGroups.toc          Interface 120100, SavedVariables: FastGroupsDB, AddonCompartmentFunc
Libs/                   LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0
Core/Init.lua           namespace (local ADDON, ns = ...), event dispatcher, /fg and /fastgroups, DB defaults
Core/Players.lua        player model: "Name-Realm" key, class, role, specID, melee/ranged
Core/Inspect.lua        inspect queue for unknown specs (only while the window is open)
Core/Layout.lua         draft board model, move/swap, sort, per-half counts, diff vs live raid
Core/Split.lua          split conventions and auto-balance
Core/Apply.lua          push the draft to the real raid, one move per GROUP_ROSTER_UPDATE
Core/Loadouts.lua       save/load, side memory, reconcile (present / absent / new / returning)
Core/Rosters.lua        planning rosters (guild picker, manual add)
Core/Serialize.lua      "!FG1!" + Base64(Deflate(CBOR(payload)))
Core/Comm.lua           addon messages: chunked OFFER / ACCEPT / DATA
UI/*.lua                Theme, Main window + sidebar, Board, Counters, LoadoutList, Rosters, Share, Options, Minimap
tests/                  plain Lua 5.1 unit tests with a stubbed WoW API
tools/check.sh          ASCII scan + luac -p + luacheck + tests
```

## Domain rules that drive the design
- A raid has 8 groups of 5. Mythic is a fixed 20 and **only groups 1-4 count**; groups 5-8 are the
  bench. Flex raids go up to 30 (groups 1-6). "Groups used: Auto" = 4 on Mythic, otherwise
  `2 * ceil(n / 10)` capped at 6.
- Split conventions: odd/even (left = 1,3,5; right = 2,4,6) or low/high (left = 1-2 or 1-3).
  Loadouts store their convention; loading into a different convention remaps groups by
  (side, index within side), so players keep their side.
- Balance priority per half: tanks, healers, melee, ranged, then classes (Demon Hunter and Monk
  weigh more because of their raid debuffs). Target for 2T/4H/14D is 1/2/7 per half.
- Sort inside a group: tank, healer, melee, ranged, then name.
- Melee vs ranged needs the spec. Ambiguous classes: Hunter (Survival melee), Shaman, Druid,
  Demon Hunter (Devourer is ranged, spec 1480), Evoker is always ranged. Manual override exists.

## Verified API facts (12.1)
- `SetRaidSubgroup(raidIndex, group)` and `SwapRaidSubgroup(i, j)`: leader or assist, not in
  combat, server-async. Issue one move, wait for `GROUP_ROSTER_UPDATE`, recompute, repeat.
  Reference implementation: NorthernSkyRaidTools `SetupManager.lua` (installed locally).
- `GetInspectSpecialization` is deprecated in 12.1; use `C_SpecializationInfo.GetInspectSpecialization`.
- `C_EncodingUtil.SerializeCBOR / DeserializeCBOR / CompressString(s, 0) / DecompressString /
  EncodeBase64 / DecodeBase64` exist since 11.1.5 (BigWigs uses the same chain). No LibDeflate needed.
- Addon comms (`C_ChatInfo.SendAddonMessage`) are blocked during active encounters and M+ runs;
  check `C_ChatInfo.InChatMessagingLockdown()`. Each prefix has a 10 message allowance that
  refills over time; messages are max 255 bytes, prefix max 16 chars.
- Blizzard UI source for lookups: `resources/wow-ui-source` (shallow clone of Gethe/wow-ui-source,
  branch `live`, gitignored). Re-clone if missing.

## Conventions
- Lua 5.1, one addon namespace table, no globals except the SavedVariable and slash command
  globals Blizzard requires.
- ASCII only in every repo file.
- Features are lazy: frames are created on first open, events are registered only while the
  window is open or an operation (apply, inspect, transfer) is running. No OnUpdate polling.
- Drag and drop uses `StartMoving` on a floating card and a hit test on drop, not OnUpdate.

## Local folders
- `resources/` is gitignored: UI source clone, mockup, scratch material.
- `IDEAS.md` collects later features; add to it instead of growing scope.
