# FastGroups

**Raid group sorting for World of Warcraft raid leaders.** See your raid as raid-frame cards,
drag players between groups, split the raid into balanced halves with one click, and save the
setup for next time.

> Status: **v0.1, first build.** Everything below is implemented and covered by offline tests,
> but it has not been tested in the live game yet. Expect rough edges; please report them.

Only the raid leader (or an assistant who arranges groups) needs FastGroups. Nobody else in the
raid has to install anything.

## Why

When players join a raid they land in groups in join order, which is essentially random. Many
bosses need a clean split, usually two halves: left and right. Group placement matters twice:
players learn their side from their group number, and healers see players sorted by group in
their raid frames. FastGroups makes that setup fast and repeatable.

## Features

- **Group board**: every player is a class-colored card with name, spec icon, role and a
  melee/ranged badge. Columns are the built-in raid groups. Drag onto an empty slot to move,
  onto a player to swap. Groups always sort tanks, healers, melee, ranged.
- **Halves and counters**: under each half you see tanks, healers, melee and ranged at a glance,
  plus class counts for Demon Hunters and Monks (raid debuffs) and any class that is uneven.
  A toolbar chip tells you whether the halves are even.
- **Your convention**: odd/even groups (1/3/5 vs 2/4/6) or low/high (1-3 vs 4-6). Switching keeps
  everyone on their side. Half names are configurable.
- **Mythic aware**: on Mythic only groups 1-4 count; groups 5-8 are shown as the bench.
- **Auto-split**: balances tanks, healers, melee, ranged and classes between the halves while
  moving as few players as possible (2 tanks / 4 healers / 14 dps become 1/2/7 per half).
- **Draft, then Apply**: edit freely; nothing changes in the real raid until you press Apply.
  FastGroups then moves players one at a time, waiting for the server to confirm each move,
  and stops if combat starts.
- **Loadouts**: save any number of setups (per boss, farm, progress). Loading one shows who is
  missing today (greyed ABSENT cards), who is new and who is returning. **Auto-fill** puts
  substitutes into the missing players' slots (same role, same melee/ranged, same class if
  possible) and sends returning players back to the half they were on before.
- **Rosters**: hand-picked lists of guildmates (from the guild roster, your current raid or by
  name). Plan groups days ahead, save the plan as a loadout, load it when the raid forms.
- **Sharing**: export loadouts as a text string for Discord, or send them in game to another
  FastGroups user over the hidden addon channel (the receiver gets an accept prompt). Your
  personal settings are only included when you ask for it.
- **Specs**: learned by quietly inspecting raid members while the window is open, remembered
  between sessions, and settable by hand (right-click a card).
- **Looks**: flat, dark window with a configurable accent color, bundled Inter font, sidebar with
  pages (Groups, Rosters, Share, Options) and your saved loadouts.

## Usage

| Command | What it does |
| --- | --- |
| `/fg` or `/fastgroups` | Open or close the window |
| `/fg demo` | Fill the board with a fake 20 player raid to try everything solo |
| `/fg live` | Back to the real raid |
| `/fg reset` | Reset window position and size |
| Minimap button | Left-click: board. Right-click: options. Also in the addon compartment. |

Typical raid night:

1. Open FastGroups and click the loadout for the boss in the sidebar.
2. If anyone is missing or new, press **Auto-fill**; adjust by dragging if needed.
3. Press **Apply**.

Right-click a card to set its spec, override melee/ranged, move it to the other half, bench it
or unassign it. Right-click a loadout to rename, duplicate, share or delete it.

## Limits worth knowing

- Group changes are only possible for the raid leader or assistants, and not in combat.
- Blizzard blocks addon messages during boss encounters and Mythic+ runs, so in-game sharing is
  unavailable there. Export strings always work.
- If the server drops a move, Apply shows "Waiting for the server"; click Apply to nudge it.

## Installation

Not on CurseForge / Wago yet. Copy the repository folder into
`World of Warcraft/_retail_/Interface/AddOns/FastGroups` (the folder must be named
`FastGroups`). From WSL, `tools/deploy.sh` does exactly that.

## Development

- Lua 5.1 (WoW's runtime). Libraries: LibStub, CallbackHandler, LibDataBroker, LibDBIcon (in
  `Libs/`). Serialization uses the game's own `C_EncodingUtil`.
- `tools/check.sh` runs an ASCII check, a Lua 5.1 syntax check, luacheck, the unit tests
  (`tests/run.lua`) and a UI smoke test (`tests/ui_smoke.lua`) that builds every page against a
  mock frame API and clicks every widget.
- `tools/gen_media.py` regenerates the textures in `Media/` (icons are drawn from SVG).
- `tools/deploy.sh` copies the addon into the WoW AddOns folder.
- Later ideas live in [IDEAS.md](IDEAS.md). Notes for AI agents live in [CLAUDE.md](CLAUDE.md).

## Credits

- Inter font by Rasmus Andersson, SIL Open Font License (`Media/Fonts/Inter-LICENSE.txt`).
- LibDBIcon, LibDataBroker, LibStub and CallbackHandler by their respective authors.

## License

To be decided.
