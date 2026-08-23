# OctoWoW Client Mods

by **Krool**

Quality-of-life mods for the [OctoWoW](https://octowow.st) 1.12.1 client
(Turtle-based "Mysteries of Azeroth" exe). Two parts that work together:

## Features

### Character select screen (`patch-9.mpq`)
- **Reorder your characters** - up/down arrows on each row move characters in
  the list. The order is yours, not the server's, and survives creates,
  deletes and renames (matching is by character name).
- **Challenge icons per character** - each row shows the character's active
  leveling challenges (Hardcore, War Mode, Slow & Steady, ...) with the
  game's own challenge tooltips on hover. A character appears here after you
  have logged into it once with the OctoChallenges addon installed - the
  select screen never receives challenge data from the server, so the addon
  bridges it across.
- **Sound settings before login** - a "Sound" button on the login screen and
  on character select opens Music / Effects / Ambience volume sliders.

### In-game addon (`Addons/OctoChallenges`)
- Shows your own active challenges as an icon column on the character
  paperdoll (left of the model) with tooltips.
- `/octochallenges` lists them in chat.
- Feeds the character-select display above.

## Install

1. Copy `Addons/OctoChallenges` into `<WoW>/Interface/Addons/`.
2. Build and install the MPQ: run `powershell -File build.ps1` with the game
   closed. It packs `Interface/` into `<WoW>/Data/patch-9.mpq`.
   You need [Ladik's MPQ Editor](http://www.zezula.net/en/mpq/download.html)
   at `tools/MPQEditor.exe` (not redistributed here).
3. Start the game through VanillaFixes / the OctoLauncher as usual.

To uninstall, delete `<WoW>/Data/patch-9.mpq` and the addon folder.

## How it works (client-modding notes)

- The OctoWoW exe loads extra patch archives at LOWER priority than its
  built-in `patch-1..5` list, so stock UI files shipped in those archives
  cannot be overridden by ours. Instead `patch-9.mpq` overrides
  `Interface/GlueXML/CreditsFrame.xml` - which ships only in the base
  `interface.MPQ`, where extra archives DO win - and that XML side-loads
  `OctoGlue.lua`, which redefines the character-select functions after the
  server's own versions have loaded.
- The character-select screen runs in the glue Lua VM, which addons cannot
  touch and which gets no challenge data. Cvars are engine-global across the
  glue/world boundary, so the addon mirrors challenge masks into a cvar
  payload the glue code reads (the stock, registered `accountList` cvar -
  the glue VM has no pcall, so only registered cvars are safe there).
- Character order is rendered as a display permutation; the server's
  character indices are untouched, so rename/delete/enter-world all keep
  their stock behavior.

## Compatibility

Built against the OctoWoW client as of 2026-08-23 (server UI patch-4/5).
A server patch update that changes `CharacterSelect.lua` may need this
mod's redefinitions re-based; open an issue if the select screen misbehaves
after an update. If the character screen ever breaks outright, deleting
`Data/patch-9.mpq` restores stock instantly.
