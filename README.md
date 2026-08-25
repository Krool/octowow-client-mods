# OctoWoW Client Mods

by **Krool**

Quality-of-life mods for the [OctoWoW](https://octowow.st) 1.12.1 client
(Turtle-based "Mysteries of Azeroth" exe). Two parts that work together:

## Features

### Login / character select screen (`patch-9.mpq`)
- **Reorder your characters** - up/down arrows on each row move characters in
  the list. The order is yours, not the server's, and survives creates,
  deletes and renames (matching is by character name).
- **Challenge icons per character** - each row shows the character's active
  leveling challenges (Hardcore, War Mode, Slow & Steady, ...) with the
  game's own challenge tooltips on hover. Data flows live from the
  OctoChallenges addon (via nampower's file API) - play a character once
  with the addon installed and its row fills in.
- **Server status** - a dialog-free ~1s probe with an UP/DOWN banner in the
  top-right corner of the login screen, auto-run at startup, re-run via the
  Check Server button. With the optional helper task installed it also shows
  REALM (world server) status pulled from the website - so "login up, worlds
  down" reads as DOWN, not green.
- **Music toggle** on the login screen and beside the char-select AddOns
  button.

### In-game addon (`AddOns/OctoChallenges`)
- Shows your own active challenges as an icon column on the character
  paperdoll (left of the model) with tooltips.
- `/octochallenges` lists them in chat.
- Feeds the character-select display above.

## Install (release zip)

1. Close the game.
2. Extract the zip anywhere and run:
   `powershell -ExecutionPolicy Bypass -File install.ps1 -WoWDir "C:\path\to\OctoWoW"`
   It copies `patch-9.mpq` into `Data/`, the addon into
   `Interface/AddOns/`, and (optional but recommended) registers a tiny
   scheduled task, "OctoGlue realm status", that refreshes realm status
   every 2 minutes for the login-screen banner.
3. Start the game through VanillaFixes / the OctoLauncher as usual.

Requires the **nampower** DLL (every launcher-managed OctoWoW install has
it) for challenge icons and crash-proof order saving; without it those
degrade gracefully and the rest still works.

**Heads-up:** the server check briefly logs in a throwaway account
(`octoprobe`) once per client start, swallowing its own dialogs. That is all
it does - no credentials of yours are involved.

To uninstall: delete `Data/patch-9.mpq`, `Interface/AddOns/OctoChallenges`,
the `OctoTools` folder, and run
`schtasks /delete /f /tn "OctoGlue realm status"`.

## Install (OctoLauncher git URL)

Adding this repo's git URL to OctoLauncher as an addon works, but gets you
the **in-game addon only** (paperdoll challenge icons, `/octochallenges`) -
a launcher-managed addon cannot install `patch-9.mpq`, so the login /
character-select features are not included. A one-time chat notice in-game
points at the release when it detects an addon-only install. For
everything, use the release zip above; the two coexist fine (the launcher
then keeps the addon half auto-updated).

## Install (from source)

As above, but build the MPQ yourself first: run `powershell -File build.ps1`
with the game closed - it packs `Interface/` into `<WoW>/Data/patch-9.mpq`.
You need [Ladik's MPQ Editor](http://www.zezula.net/en/mpq/download.html) at
`tools/MPQEditor.exe` (not redistributed here).

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
  templates live in our CreditsFrame.xml). Challenge masks reach it through
  `CustomData/octoglue-challenges`, written in-world by the addon through
  nampower's `WriteCustomFile` (the helper task mirrors SavedVariables into
  the same file as a fallback); the character order persists as a `#O=...`
  suffix on the saved account name (`Get/SetSavedAccountName` being the only
  stock persistent glue-writable storage), stripped before the login box
  displays it.
- Character order is rendered as a display permutation; the server's
  character indices are untouched, so rename/delete/enter-world all keep
  their stock behavior.

## Compatibility

Built against the OctoWoW client as of 2026-08-24 (server UI patch-4/5).
A server patch update that changes `CharacterSelect.lua` may need this
mod's redefinitions re-based; open an issue if the select screen misbehaves
after an update. If the character screen ever breaks outright, deleting
`Data/patch-9.mpq` restores stock instantly.
