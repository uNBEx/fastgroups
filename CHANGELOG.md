# Changelog

All notable changes to FastGroups. Newest first. Versions follow
[Semantic Versioning](https://semver.org); the format follows
[Keep a Changelog](https://keepachangelog.com).

## Unreleased

### Changed
- Auto-split keeps players on their half when the raid changes between pulls. Players an earlier
  split placed only move for tanks, healers, half sizes or a Monk / Demon Hunter on each half;
  newcomers even out melee, ranged and classes. Before, a new class mix could reshuffle the raid.
  Shift-click Auto-split to rebalance everyone from scratch.
- Auto-split spreads each half's healers over its groups.
- The balance chip only warns about what Auto-split evens out.
- Loadouts remember the "Groups used" setting (Auto / 4 / 6) and restore it when loaded. Loadouts
  saved before this keep the current setting.

### Added
- Option "Strict melee/ranged balance" (off by default): Auto-split also moves placed players to
  even out melee and ranged.
- Option "Whisper players who switch halves" (on by default): after Apply, players a later
  Auto-split had to send to the other half get a whisper with their new group. Never more than
  three at once.

## v0.2.0 - 2026-09-27

First public release.

### Added
- Group board: every raid member as a class-colored card with spec, role and a melee/ranged
  badge. Drag onto an empty slot to move, onto a player to swap.
- Balanced halves with odd/even or low/high groups, counters under each half and a balance chip.
- Auto-split: balances tanks, healers, melee, ranged and classes while moving as few players as
  possible.
- Shared odd group (opt-in): with 11-15 or 21-25 players the last group is split between the
  halves, and the sides are announced in raid chat.
- Simple mode: plain groups without halves.
- Draft, then Apply: nothing changes in the raid until you press Apply; moves go one at a time
  and stop in combat.
- Mythic aware: only groups 1-4 count, groups 5-8 are the bench.
- Loadouts: save setups per boss, see who is absent, new or returning, and Auto-fill substitutes.
- Rosters: plan groups from guild members before the raid forms.
- Sharing: export strings for Discord and in-game sending to other FastGroups users.
- Specs from LibSpecialization broadcasts (BigWigs and others) and paced inspects.
- Raid leader and assistant crowns, promote and remove options, offline markers.
- Configurable accent color, square or rounded corners, resizable window, minimap button and
  addon compartment entry.
