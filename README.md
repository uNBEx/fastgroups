# FastGroups

**Raid group sorting for World of Warcraft raid leaders.** See your raid as raid-frame cards,
drag players between groups, split the raid into balanced halves with one click, and save the
setup for next time.

> Status: **in design**. The UI is being reviewed as an interactive mockup; the addon itself is
> not written yet. Everything below describes the planned v0.1.

Only the raid leader (or an assistant who arranges groups) needs FastGroups. Nobody else in the
raid has to install anything.

## Why

When players join a raid they land in groups in join order, which is essentially random. Many
bosses need a clean split, usually two halves: left and right. Group placement matters twice:
players learn their side from their group number, and healers see players sorted by group in
their raid frames. FastGroups makes that setup fast and repeatable.

## Features (planned for v0.1)

- **Group board**: every player is a class-colored card with name, spec, role and a melee/ranged
  badge. Columns are the built-in raid groups. Drag onto an empty slot to move, onto a player to
  swap. Groups always sort tanks, healers, melee, ranged.
- **Halves and counters**: under each half you see tanks, healers, melee and ranged at a glance,
  plus class counts for the classes that matter (Demon Hunter, Monk) and any class that is uneven.
- **Your convention**: odd/even groups (1/3/5 vs 2/4/6) or low/high (1-3 vs 4-6). Switching keeps
  everyone on their side.
- **Mythic aware**: on Mythic only groups 1-4 are used; groups 5-8 are the bench.
- **Auto-split**: balances tanks, healers, melee, ranged and classes between the halves while
  moving as few players as possible.
- **Draft, then Apply**: edit freely, nothing changes in the real raid until you press Apply.
  FastGroups then moves players one at a time and stops if combat starts.
- **Loadouts**: save any number of setups (per boss, farm, progress). When you load one, the board
  shows who is missing today (greyed out), who is new, and who is returning. **Auto-fill** puts
  substitutes into the missing players' slots (same role, same melee/ranged, same class if
  possible) and sends returning players back to the half they used to be on.
- **Rosters**: keep hand-picked lists of guildmates and plan groups days before the raid. Save
  the plan as a loadout and load it when the raid forms.
- **Sharing**: export loadouts as a text string (compressed + base64) for Discord, or send them
  in game to another FastGroups user over the hidden addon channel. Personal settings are only
  included if you ask for it.
- **Looks**: flat, dark, modern window with a configurable accent color. Sidebar with pages
  (Groups, Rosters, Share, Options) and your saved loadouts.

## Usage

| Command | What it does |
| --- | --- |
| `/fg` or `/fastgroups` | Open or close the window |
| Minimap button | Same as `/fg` (can be hidden; also in the addon compartment) |

Typical raid night:

1. Open FastGroups, click the loadout for the boss.
2. Press **Auto-fill** if anyone is missing or new, adjust by dragging if needed.
3. Press **Apply**.

## Limits worth knowing

- Group changes are only possible for the raid leader or assistants, and not in combat.
- Blizzard blocks addon messages during boss encounters and Mythic+ runs, so in-game sharing is
  unavailable there. Export strings always work.
- Other players' specs come from inspecting them (done quietly while the window is open) or from
  a manual override in the card's right-click menu.

## Installation

Not released yet. When it is, install from CurseForge / Wago, or copy the `FastGroups` folder into
`World of Warcraft/_retail_/Interface/AddOns/`.

## Development

- Lua 5.1 (WoW's runtime), no external dependencies beyond the standard LibStub / LibDBIcon libs.
- `tools/check.sh` runs an ASCII check, a Lua syntax check, luacheck, and the unit tests.
- Later ideas live in [IDEAS.md](IDEAS.md). Notes for AI agents live in [CLAUDE.md](CLAUDE.md).

## License

To be decided.
