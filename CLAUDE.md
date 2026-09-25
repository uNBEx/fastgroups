# FastGroups - notes for agents

World of Warcraft **retail** addon (Midnight, client 12.1.x, `## Interface: 120100`) for raid
leaders and assistants. Its only job is sorting players into the raid's built-in subgroups:
a raid-frame-style board with drag and drop, balanced halves (left/right), saved loadouts with
absent/new player reconciliation, planning rosters, and preset sharing (export strings and
hidden addon comms). Only the person arranging groups needs it installed.

## Status
- v0.1 implemented. All offline checks pass (`tools/check.sh`). **Not yet tested in game**;
  the first in-game session will surface layout and API details the mocks cannot.
- The approved UI mockup is `resources/mockup/index.html` (gitignored, local only). The addon
  follows it closely.
- Never push to the remote without the user's explicit approval. Local commits are fine.

## Layout
```
FastGroups.toc          load order; Interface 120100; SavedVariables FastGroupsDB
Libs/                   LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0
Media/                  TGA textures (Icons/, round6, ring6, round3, circle) + Inter fonts
Core/Init.lua           namespace, event dispatcher (ns.RegisterEvent per owner), messages
                        (ns.On / ns.Fire), DB defaults, slash commands, compartment globals
Core/Data.lua           spec table (specID -> class, role, melee), class lists, colors
Core/Players.lua        player model; Players.Get(key) resolves class/spec/role/pos/bucket
Core/Raid.lua           live roster snapshot (GetRaidRosterInfo), difficulty, rank
Core/Board.lua          the draft: sources (none/live/demo/roster/loadout), halves, moves,
                        live sync, loadout reconcile + Auto-fill
Core/Split.lua          Split.Compute (pure, tested) + Split.Run(board)
Core/Loadouts.lua       save/load/rename/duplicate/delete, export format + validation
Core/Rosters.lua        planning rosters + guild roster scan
Core/Apply.lua          Apply.NextMove (pure planner, tested) + event-driven driver
Core/Demo.lua           /fg demo fake raid and sample loadout
Core/Inspect.lua        event-driven inspect queue for unknown specs
Core/Serialize.lua      "!FG1!" + Base64(Deflate(CBOR(payload))) via C_EncodingUtil
Core/Comm.lua           addon messages: O(ffer) / A(ccept) / D(ecline) / C(hunk)
UI/Theme.lua            colors, fonts, accent hooks
UI/Widgets.lua          buttons, segmented, toggle, check, edit, scroll, slider, pill, menu
UI/Main.lua             window, title bar, sidebar + loadout list, modal, toasts, page host
UI/GroupsPage.lua       toolbar, halves, columns, cards, drag and drop, counters, tray, bench
UI/RostersPage.lua      rosters list/detail, guild picker
UI/SharePage.lua        export / import / send in game
UI/OptionsPage.lua      options
UI/Minimap.lua          LDB launcher + LibDBIcon (created only when shown)
tests/                  wow_stub.lua, run.lua (unit), ui_mock.lua + ui_smoke.lua (UI)
tools/                  check.sh, deploy.sh, gen_media.py
```

## Domain rules that drive the design
- A raid has 8 groups of 5. Mythic (difficulty 16) is a fixed 20 and **only groups 1-4 count**;
  groups 5-8 are the bench. Flex raids go up to 30 (groups 1-6); Mythic Flexible is 233.
  "Groups used: Auto" = 4 on Mythic, otherwise `2 * ceil(n / 10)` capped at 6.
- Split conventions: odd/even (left = 1,3,5; right = 2,4,6) or low/high (left = 1-2 or 1-3).
  Loadouts store their convention and group count; loading remaps groups by (side, index).
- Balance priority per half: tanks, healers, melee, ranged, then classes (Demon Hunter and Monk
  weigh 3x because of their raid debuffs). Target for 2T/4H/14D is 1/2/7 per half.
- Sort inside a group: tank, healer, melee, ranged, then name (or class).
- Melee vs ranged needs the spec. Ambiguous classes: Hunter, Shaman, Druid, Demon Hunter
  (Devourer 1480 is ranged). Unknown shows as "?" and is counted separately.
- Board players whose draft equals their previous live group follow live moves (Board:Sync);
  edited players keep their draft. During Apply nobody follows.

## Verified API facts (12.1)
- `SetRaidSubgroup(raidIndex, group)` / `SwapRaidSubgroup(i, j)`: leader or assist, not in
  combat, server-async. One move per `GROUP_ROSTER_UPDATE` (NorthernSkyRaidTools does the same).
- `GetInspectSpecialization` is deprecated in 12.1; use `C_SpecializationInfo.GetInspectSpecialization`.
- `C_EncodingUtil.SerializeCBOR / CompressString(s, 0) / EncodeBase64` and reverses (11.1.5+).
- Addon comms blocked during encounters and M+ (`C_ChatInfo.InChatMessagingLockdown()`); each
  prefix has a 10 message allowance; `SendAddonMessage` returns `Enum.SendAddonMessageResult`
  (3 and 8 = throttled). Messages max 255 bytes, prefix max 16 chars.
- Textures: `Texture:SetTextureSliceMargins` + `SetTextureSliceMode` for rounded nine-slices.
- Menus: `MenuUtil.CreateContextMenu(owner, function(owner, root) ... end)`.
- Blizzard UI source: `resources/wow-ui-source` (shallow clone of Gethe/wow-ui-source, branch
  `live`, gitignored). Re-clone if missing.

## Conventions
- Lua 5.1, one namespace table (`local _, ns = ...`), no globals except FastGroupsDB, the slash
  command globals and the three addon compartment functions.
- ASCII only in every repo file (checked by tools/check.sh).
- Features are lazy: the UI is built on first open; roster/combat/inspect events are registered
  only while the window is open; Apply registers its events only while running; the minimap
  button is only created when shown; the guild roster event only while the guild picker is open.
  CHAT_MSG_ADDON is registered unless sharing is set to "Ignore".
- No OnUpdate anywhere. Drag and drop uses `StartMoving` on a floating card and a hit test
  (`IsMouseOver`) on drop. Timers are only used for toast fade-out and to pace throttled sends.
- Pure logic (Split.Compute, Apply.NextMove, Board, Loadouts, Serialize, Comm parsing) is kept
  testable under plain Lua with the stub in tests/wow_stub.lua.
- When adding UI, run tools/check.sh: the smoke test clicks and hovers every widget.

## Local folders
- `resources/` is gitignored: UI source clone, mockup, library sources, font download.
- `IDEAS.md` collects later features; add to it instead of growing scope.
