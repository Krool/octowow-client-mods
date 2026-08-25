# For an AI assistant installing this on someone's PC

You were pointed at this repo to install these OctoWoW client mods for the
user. Follow this exactly; it is the canonical procedure. Windows + PowerShell.

## What you're installing
- `patch-9.mpq` — the client mod (login/character-select features). Must go in
  `<WoW>\Data\`. No addon or launcher can place it; only a file copy.
- `OctoChallenges` — an in-game addon (character-sheet challenge icons + the
  data feed for the character-list icons). Goes in `<WoW>\Interface\AddOns\`.

## Steps
1. **Find the WoW folder.** It contains `realmlist.wtf` and a `Data\` folder.
   Ask the user if you can't locate it (common: a path with `WoW`/`OctoWoW`).
   Everything below is relative to it; call it `<WoW>`.

2. **The game must be closed.** Check for a `WoW.exe` process. If it's running,
   ask the user to close it — do **not** kill it yourself.

3. **Download the latest release assets** (needs `gh`, or use the browser URLs):
   - Easiest: `gh release download --repo Krool/octowow-client-mods --pattern "octowow-client-mods-*.zip"`
   - Then extract and run the bundled installer — it does everything:
     `powershell -ExecutionPolicy Bypass -File install.ps1 -WoWDir "<WoW>"`
   - The installer copies `patch-9.mpq` to `Data\`, the addon to
     `Interface\AddOns\`, and registers the "OctoGlue realm status" scheduled
     task (feeds the status lamp's realm info). That is the full install.

4. **If you can't/don't want to run the installer**, do it by hand:
   - Copy `patch-9.mpq` into `<WoW>\Data\`.
   - Copy the `AddOns\OctoChallenges` folder into `<WoW>\Interface\AddOns\`
     (so files land at `Interface\AddOns\OctoChallenges\OctoChallenges.toc`).
   - The realm-status task is optional; skipping it just means the lamp judges
     the login server only. To add it, register the two files in `tools\` per
     `install.ps1` (use `Register-ScheduledTask`, not `schtasks /tr`).

5. **Verify.** `<WoW>\Data\patch-9.mpq` and
   `<WoW>\Interface\AddOns\OctoChallenges\OctoChallenges.toc` exist. Tell the
   user to launch through their OctoLauncher/VanillaFixes as usual; on the
   login screen a small green/yellow/red status lamp appears top-right.

## Notes
- Requires the **nampower** DLL (standard on every launcher-managed OctoWoW
  install). Without it, challenge icons and crash-proof saves degrade; the
  rest still works.
- Install is **one-time**. It survives game/torrent updates (the launcher
  never touches `patch-9.mpq`). Only re-run for a new release here.
- Uninstall: delete `<WoW>\Data\patch-9.mpq`,
  `<WoW>\Interface\AddOns\OctoChallenges`, the `<WoW>\OctoTools` folder, and
  run `schtasks /delete /f /tn "OctoGlue realm status"`.
- Do not build from source unless asked — that needs MPQEditor, not shipped
  here. The release has a prebuilt `patch-9.mpq`.
- Full details and how-it-works: `README.md`.
