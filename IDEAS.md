# Ideas for later

Not planned for v0.1. Kept here so they are not lost. Every item must follow the same rule as the
rest of the addon: nothing costs anything until the user turns it on.

## Group setup
- **Pins / locks**: pin a player to a group or a half so Auto-split and Auto-fill never move them.
- **Undo / redo** for board edits (small ring buffer of draft snapshots).
- **More split shapes**: thirds (3 soak groups), "N soak groups of K", or a custom side per group.
  Loadouts already store sides, so this is mostly UI.
- **Bench helper for Mythic 20**: when more than 20 are online, suggest who sits based on class,
  role and buff coverage (the user decides, the addon only highlights).
- **Buff coverage per half**: show which raid buffs / debuffs each half has (for example the DH
  and Monk damage-taken debuffs) instead of plain class counts.
- **Minimal-move solver**: replace the greedy placement with a small assignment solver so Apply
  needs the fewest possible swaps.

## Loadouts
- **Boss linking**: tie a loadout to an encounter and offer to load it when the raid leader
  targets or pulls toward that boss (only if enabled; one cheap event, no polling).
- **Loadout history**: keep the last few versions of each loadout, restore with one click.
- **Attendance memory**: remember who usually shows up to pre-fill likely absentees.
- **Folders / tags** for loadouts per raid tier.

## Rosters
- **Invite from roster**: mass invite everyone on a roster, whisper the ones who are offline.
- **Import from a raid sign-up tool** (for example a pasted CSV / WoWAudit style list).

## Sharing
- **Share spec cache** between leaders so inspects do not have to be repeated.
- **Plain text export** for Discord ("Left: A, B, C / Right: D, E, F").
- **Raid note export** in a format note addons (MRT / NSRT) can read.

## Quality of life
- Keybinding to toggle the window.
- Localization (strings are already kept in one table).
- Raid markers per half (for example Star = left, Circle = right) set on Apply.
