# OctoWoW Client Mods

by **Krool**

Quality-of-life mods for the [OctoWoW](https://octowow.st) 1.12.1 client
(Turtle-based "Mysteries of Azeroth" exe). There are **two parts**, and which
you need depends on what you want — see [Installing](#installing) below.

| Part | File / source | Gives you |
|------|---------------|-----------|
| **Client mod** | `patch-9.mpq` | Login & character-select features: server-status lamp, per-character challenge icons on the character list, character reordering, music toggle |
| **Addon** | `OctoChallenges` | In-game challenge icons on your character sheet, and the data feed for the character-list icons above |

The two work together but each is useful on its own. The addon can only be a
normal addon; the client mod is an MPQ that must sit in `Data\`.

## Features

### Client mod — login / character-select screen (`patch-9.mpq`)
- **Character reordering** — up/down arrows on each character row. The order
  is yours, not the server's, and survives creates, deletes and renames
  (matched by character name). Arrows idle dimmed and brighten on hover.
- **Challenge icons per character** — each row on the character list shows
  that character's active challenges (Hardcore, War Mode, Slow & Steady, ...)
  with the game's own tooltips on hover. The data comes from the
  **OctoChallenges addon** (below): play a character once with the addon
  installed and its row fills in.
- **Server-status lamp** — a small green/yellow/red dot, top-right of the
  login screen. **Hover** it for details (login-server latency, per-realm
  status, when the web check last ran); **click** it to re-check. Green =
  login up and realms up; yellow = still checking or a partial realm outage;
  red = login down or every realm down. (Realm status needs the optional
  helper task — without it the lamp judges the login server only.)
- **Music toggle** — a small horn icon under the lamp (and beside the
  character-select AddOns button). Click to mute/unmute the login music; the
  choice sticks across sessions.

### Addon — in-game challenge icons (`OctoChallenges`)
- Shows **your own** active challenges as an icon column on your character
  sheet (press **C** — the icons sit just left of the model), each with a
  hover tooltip.
- `/octochallenges` lists them in chat.
- Reads your challenges from the server over the game's existing `TW_UI`
  addon channel — it only ever reads your own, and sends nothing elsewhere.
- Also feeds the character-select icons in the client mod above.
- Maintained as its own repo:
  [github.com/Krool/OctoChallenges](https://github.com/Krool/OctoChallenges).

## Installing

Three routes, easiest first. All are safe to combine; to uninstall the client
mod at any time just delete `Data\patch-9.mpq`.

### 1. Everything, with the installer (recommended)
Get the **`octowow-client-mods` release zip** from the
[Releases page](https://github.com/Krool/octowow-client-mods/releases/latest),
then:
1. Close the game.
2. Extract the zip and run:
   `powershell -ExecutionPolicy Bypass -File install.ps1 -WoWDir "C:\path\to\OctoWoW"`
   It installs `patch-9.mpq` into `Data\`, the OctoChallenges addon into
   `Interface\AddOns\`, and registers a small scheduled task
   ("OctoGlue realm status", every 2 min) that feeds the lamp's realm info.
3. Launch as usual.

### 2. Just the client mod, by hand (no installer)
If you only want the login / character-select features and would rather not
run a script: download the standalone **`patch-9.mpq`** asset from the
[latest release](https://github.com/Krool/octowow-client-mods/releases/latest),
close the game, and drop it into your `WoW\Data\` folder. That's the whole
install. (You skip the realm-status helper, so the lamp judges only the login
server. Challenge icons on the character list still work as long as the addon
is installed — see below.)

### 3. Just the addon
The **OctoChallenges** addon (in-game character-sheet icons) installs like any
other addon and updates itself through the launcher:
- **In OctoLauncher:** Addons tab → **Install Addon** → paste
  `https://github.com/Krool/OctoChallenges`.
- **Or manually:** copy the addon folder to
  `Interface\AddOns\OctoChallenges` and restart the client.

> **Note on adding *this* repo's URL to the launcher:** you *can* paste
> `octowow-client-mods` into the launcher's Install Addon box, but a
> launcher-managed addon can only install files under `Interface\AddOns` — it
> **cannot** place `patch-9.mpq`, so you'd get the in-game addon only, not the
> login/character-select features. A one-time in-game chat notice points this
> out and links the release. For the full set use route 1 or 2 above. (For a
> true one-click install of everything, the client mod would need to be added
> to the launcher's own mod list — see `LAUNCHER-PROPOSAL.md`.)

### Requirements & notes
- **nampower** (standard on every launcher-managed OctoWoW install) powers the
  live challenge-icon feed and crash-proof order saving. Without it those
  degrade gracefully and everything else still works.
- The server-status lamp briefly logs in a throwaway account (`octoprobe`)
  once per client start to test the login server, swallowing its own dialogs.
  None of your credentials are involved.
- **Uninstall:** delete `Data\patch-9.mpq` (removes all client-mod features),
  `Interface\AddOns\OctoChallenges`, the `OctoTools` folder, and run
  `schtasks /delete /f /tn "OctoGlue realm status"`.

### Build from source
Prefer to build the MPQ yourself: run `powershell -File build.ps1` with the
game closed — it packs `Interface\` into `<WoW>\Data\patch-9.mpq`. You need
[Ladik's MPQ Editor](http://www.zezula.net/en/mpq/download.html) at
`tools\MPQEditor.exe` (not redistributed here).

## How it works (client-modding notes)

- The OctoWoW exe loads extra patch archives at LOWER priority than its
  built-in `patch-1..5` list, so stock UI files shipped in those archives
  cannot be overridden by ours. Instead `patch-9.mpq` overrides
  `Interface/GlueXML/CreditsFrame.xml` — which ships only in the base
  `interface.MPQ`, where extra archives DO win — and that XML side-loads
  `OctoGlue.lua`, which redefines the character-select functions after the
  server's own versions have loaded.
- The character-select screen runs in the glue Lua VM, which addons cannot
  touch, has NO cvar API, and only renders template-inherited widgets (the
  templates live in our CreditsFrame.xml). Challenge masks reach it through
  `CustomData/octoglue-challenges`, written in-world by the addon through
  nampower's `WriteCustomFile` (the helper task mirrors SavedVariables into
  the same file as a fallback); the character order persists as a `#O=...`
  suffix on the saved account name (`Get/SetSavedAccountName` being the only
  stock persistent glue-writable storage), stripped before the login box
  displays it.
- Character order is rendered as a display permutation; the server's
  character indices are untouched, so rename/delete/enter-world all keep their
  stock behavior.

## Compatibility

Built against the OctoWoW client as of 2026-08-25 (server UI patch-4/5).
A server patch update that changes `CharacterSelect.lua` may need this mod's
redefinitions re-based; open an issue if the select screen misbehaves after an
update. If the character screen ever breaks outright, deleting
`Data/patch-9.mpq` restores stock instantly.
