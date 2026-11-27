# Shady Business

A "suspicious activity detector" for group play in World of Warcraft: Forever. It watches the group you are in and warns **you** (nobody else) when something looks like trouble.

**0.1-test.XX is an early test version.** Every alert is shown only to you, as a raid-warning style message on your screen plus a line in your chat. Nothing is sent to the group.

## What it watches

- **Loot rules:** any change of the loot method by someone else (e.g. Group Loot to Free for All), and, when you join, a group already set to Free for All, Master Looter or Round Robin. Entering a dungeon or raid with one of those still set reminds you (unless you are the leader).
- **Leader changes** inside a dungeon or raid: a chat line.
- **Healers** (only members assigned the Healer role, level 12 and up):
  - a Healer that is not a Druid, Paladin, Priest or Shaman;
  - a Healer whose gear doesn't look like healing gear. "Healer pieces" are items with any healer stat (Intellect, Spirit, MP5, spell power or healing); "healing power" is spell power and "+healing" from the gear added together.
    - Levels 12-29: 20 or more healing power, or 4 or more healer pieces, checks out; exactly 3 pieces "meets the bare minimum"; fewer gives an alert. Healers below level 20 who fail get an extra note that characters that low usually aren't well geared yet.
    - Levels 30+: at least 3 healer pieces **and** at least 30 healing power (40 from level 40, 50 from 50, 60 at 60), otherwise an alert.
    - The result comes as a header line (player and verdict) with detail lines below it: the piece count, the stats, and the healer's talent points per tree with their spec (the tree with the most points), shown as **yellow** for Holy or Discipline (Paladin, Priest), **green** "Resto" for Restoration (Druid, Shaman), and **red** for any other tree (the talents use the short names "Resto", "Ret", "Prot" and "Feral"). The spec is only reported; it never causes an alert. The healer is inspected automatically, every few seconds until it works.
  - Re-checked when their gear changes, when you enter a dungeon or raid, and on a ready check (never in combat). A re-check only says something when the result changes: worse is an alert, better a chat line.

## Install

With [WowUp](https://wowup.io): install from this repository's URL. Or download the `-forever.zip` from the latest release and unzip it into `_forever_/Interface/AddOns/`.

## Use

- `/shady`: settings (watch parties: on; watch raids: off). Also under Options > AddOns > Shady Business.
- `/shady status`: what it sees in your current group.

## License

MIT, see `LICENSE`.
