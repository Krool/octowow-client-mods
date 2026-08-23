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
  game's own challenge tooltips on hover. The select screen has no live
  channel to the server, so `build.ps1` bakes the data from the
  OctoChallenges addon's SavedVariables: log a character out once with the
  addon installed, run the build, and its row fills in.
- **Server status** - a dialog-free ~1s probe with an UP/DOWN banner in the
  top-right corner of the login screen, auto-run at startup, re-run via the
  Check Server button. (Pre-login sound sliders were dropped: the glue VM
  exposes no volume APIs - that one needs a DLL.)

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
  touch, has NO cvar API, and only renders template-inherited buttons (the
  templates live in our CreditsFrame.xml). Challenge masks are baked from
  the addon's SavedVariables at build time; the character order persists as
  a `#O=...` suffix on the saved account name (`Get/SetSavedAccountName`
  being the only persistent glue-writable storage), stripped before the
  login box displays it.
- Character order is rendered as a display permutation; the server's
  character indices are untouched, so rename/delete/enter-world all keep
  their stock behavior.

## Compatibility

Built against the OctoWoW client as of 2026-08-23 (server UI patch-4/5).
A server patch update that changes `CharacterSelect.lua` may need this
mod's redefinitions re-based; open an issue if the select screen misbehaves
after an update. If the character screen ever breaks outright, deleting
`Data/patch-9.mpq` restores stock instantly.
