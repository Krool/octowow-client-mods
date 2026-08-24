# Classic WoW (1.12.1) + OctoWoW modding reference

Research compiled 2026-08-23 from web sources, the OctoLauncher source, string
dumps of this install's `WoW.exe`, and lessons already proven in this repo
(patch-9 glue mod, OctoChallenges, OnyLogoff). Facts that could not be
independently confirmed are marked UNVERIFIED. Everything targets client
build **1.12.1.5875 (x86, Windows)** as modified by Turtle WoW / OctoWoW.

---

## 0. The four modding layers

| Layer | What it can touch | Ships as | Risk when it breaks |
|---|---|---|---|
| **Addons** (Interface\AddOns) | In-world UI, everything the FrameXML Lua VM can see | folder + .toc | Lua error popup; worst case disable the addon |
| **MPQ data patches** | Textures, models, sounds, DBCs, FrameXML/GlueXML overrides | `Data\patch-X.mpq` | Broken login/char-select; delete the MPQ to recover |
| **DLL mods** | New Lua APIs, engine behavior, rendering, networking | DLL in game dir + `dlls.txt` entry | Client won't start / crashes; remove the dlls.txt line |
| **Exe patches** | Hardcoded engine constants (FoV, farclip, LAA) | modified `WoW.exe` | On OctoWoW the launcher owns this — see §5 |

On OctoWoW the first three are all live in this install; exe patching is the
launcher's job, not ours (it verifies `WoW.exe` against a stored SHA-1,
`expectedPatchedWowHash` in its settings.json — hand-patching the exe makes
the launcher re-patch or complain).

---

## 1. Addon development (the FrameXML VM)

### 1.1 Lua 5.0, not 5.1

The client embeds a cut-down Lua 5.0. Every modern habit that dies here:

- `string.match` / `string.gmatch` do not exist. Use `string.find` (with
  captures) and `string.gfind` (5.0's gmatch).
- No `#` operator. Use `table.getn(t)` / `string.len(s)`. `table.setn`
  exists; `getn` can go stale after nil-hole tricks.
- No `%` operator. Use `math.mod(a, b)`.
- No 5.1 varargs: `function f(...)` packs into the local table `arg`
  (`arg.n` = count); forward with `unpack(arg)`. No `select()`.
- `os.*`, `io.*`, `require`, `loadfile` are stripped; `loadstring`, `pcall`,
  `setmetatable`, `getfenv/setfenv` exist.
- WoW global aliases (`strfind`, `format`, `getn`, `tinsert`, `mod`,
  `getglobal`...) are the safest spellings — vanilla addons use them.
- The embedded parser is lenient beyond 5.0 (accepts `break;`). Lint with a
  permissive grammar (we use node `luaparse` with Lua 5.2 grammar).

### 1.2 Event model

- Handlers receive **globals**, not parameters: `this` (the frame), `event`,
  `arg1`..`arg9`. `function(self, event, ...)` signatures silently get nils.
- **Copy arg1..argN into locals at the top of every handler** — any function
  you call can re-enter the dispatcher and clobber the globals. This
  manifests as heisenbugs, not errors.
- `OnUpdate` gets elapsed time in global `arg1`; runs every frame per
  visible frame — always accumulate-and-throttle.
- Login order: `ADDON_LOADED` (arg1 = folder name, SavedVariables for that
  addon are readable) → `VARIABLES_LOADED` → `PLAYER_LOGIN` →
  `PLAYER_ENTERING_WORLD` (fires again on every loading screen). Much game
  state (quest log etc.) is not ready at `VARIABLES_LOADED`; gate world work
  on `PLAYER_ENTERING_WORLD`.
- SavedVariables flush to `WTF\` only on logout/quit/`ReloadUI()`;
  `PLAYER_LOGOUT` is the last chance to mutate them. **A crash loses
  everything since the last /reload** — this install crashes on exit often
  (see patch-Z-src v15 notes), so treat "save early, /reload to persist" as
  policy for anything important.
- Player auras: `PLAYER_AURAS_CHANGED` (no args); the `GetPlayerBuff*` index
  space differs from `UnitBuff("player", i)` ordering — classic off-by-one
  source.

### 1.3 TOC / XML

- `## Interface: 11200`; mismatched addons need "Load out of date AddOns".
  Directives: Title, Notes, Dependencies, OptionalDeps, LoadOnDemand,
  SavedVariables, SavedVariablesPerCharacter (both work in 1.12),
  DefaultState. TOC filename must equal the folder name. No UTF-8 BOM.
- Load order between addons is dependency-driven then alphabetical — use
  `OptionalDeps` to load after anything you hook.
- 1.12 has a per-addon script memory budget (slider on the char-select
  AddOns screen); big addons die with "not enough memory" until it's raised
  or set to 0.
- `CreateFrame(type, name, parent, template)` exists (since 1.10). Templates
  must be `virtual="true"` and loaded before anything inheriting them.
  `$parent` name expansion + `getglobal(frame:GetName().."Child")` is the
  child-lookup idiom (no parentKey). Frame names are globals — two addons
  using the same name silently collide.
- **Frames are immortal.** No deletion, ever. Creating frames in a loop is a
  permanent leak; pool and reuse. OnUpdate keeps running on alpha-0 frames —
  only `Hide()` stops it.

### 1.4 API surface and its holes

- **Nothing is protected.** No secure frames, no taint, no `hooksecurefunc`
  (nil in 1.12). `CastSpellByName`, `TargetUnit`, `UseAction` are all
  callable from addon code. Server policy, not the client, is the limit on
  automation.
- Hook pattern (the only one):
  `local orig = Fn; function Fn(a,b,c) ... return orig(a,b,c) end` —
  always return the original's returns; never call the global name inside
  the hook. For widget scripts: save `GetScript`, wrap, remember wrapped
  handlers still read `this`/`arg1` globals.
- `UnitBuff`/`UnitDebuff` return **texture path only** — no name, no spell
  ID (unless SuperWoW is loaded). Standard technique is **tooltip
  scanning**: hidden GameTooltip, `SetUnitBuff`/`SetPlayerBuff`, read
  `getglobal("MyTTTextLeft1"):GetText()`. Same trick for item stats.
  Texture paths are shared across ranks/spells — never a unique key.
- `GetItemInfo(id)` returns nil for anything not in the WDB item cache —
  including worn items right after login/WDB wipe (the exact cause of our
  Bagshui crash, and it recurs every launch because OctoLauncher wipes WDB).
  No `GET_ITEM_INFO_RECEIVED` event in 1.12; retry on `BAG_UPDATE` or
  accept nil. **Never prime via `GameTooltip:SetHyperlink("item:ID")` on an
  unseen ID — it disconnects the 1.12 client.**
- Combat log = ~30 localized `CHAT_MSG_COMBAT_*`/`CHAT_MSG_SPELL_*` chat
  events. No GUIDs, no spell IDs; parsers convert `GlobalStrings` format
  strings to patterns and are locale-specific. Same-name/pet ambiguity is
  unresolvable without SuperWoW's `RAW_COMBATLOG`.
- Consult 1.12-specific references only (vanilla-wow-archive, shagu's
  wow-vanilla-api, the townlong-yak build-5875 FrameXML dump — the best
  primary source). Modern wiki pages describe post-2.0 signatures.

### 1.5 Performance

- Lua 5.0's GC is stop-the-world; garbage spikes are visible hitches. No
  string concat/`format`/table constructors in per-frame or combat-log
  paths; wipe-and-reuse tables; localize hot globals.
- `GetAddOnMemoryUsage` exists for leak hunting.

### 1.6 Debugging

- `/console scriptErrors 1` shows runtime errors; `seterrorhandler()` for a
  custom catcher. **Runtime Lua errors are never written to disk** —
  `Logs\FrameXML.log` holds load-time XML/TOC problems only (glue
  equivalent: `Logs\GlueXML.log`).
- `DEFAULT_CHAT_FRAME:AddMessage()` is printf. No `/dump`. In-game editors:
  WowLua 1.12 port, shagu's pfStudio.
- `/reload` = edit-test loop + SavedVariables flush. New addon folders need
  a client restart (TOC scan happens at login).

### 1.7 SendAddonMessage / CHAT_MSG_ADDON

- `SendAddonMessage(prefix, text, type)`; types PARTY / RAID / GUILD /
  BATTLEGROUND only (no WHISPER until 2.1). Prefix ≤16 chars, no tab;
  prefix + `\t` + body ≤254 bytes total.
- Received as `CHAT_MSG_ADDON`: arg1 prefix, arg2 body, arg3 type, arg4
  sender. No prefix registration — you see everything, filter on arg1.
- No client throttle, but the server chat-flood limiter applies; keep to
  ~10 msg/s (ChatThrottleLib convention). Don't rely on receiving an echo
  of your own messages.
- **Turtle/OctoWoW quirk (proven by OctoChallenges): the server's TW_UI
  responses come back with the RESPONSE NAME as the prefix** (arg1 =
  `RESPONSE_PLAYER_CHALLENGES`), not `TW_UI`. Requests go out as
  `SendAddonMessage("TW_UI", "COMMAND;args", "GUILD")` and are delivered
  even unguilded on this core. GUIDs come from Turtle's extended
  `UnitExists` (second return). Full command set: extract patch-4 and grep
  `TW_UI` in `Turtle_General.lua`. Also proven: a server that never answers
  looks identical to "no data" — always distinguish "no response" from
  "empty response" in caches (v15 lesson: 3 of 5 chars had silently empty
  challenge caches).

---

## 2. MPQ data patching

### 2.1 Load order — stock vs OctoWoW

- **Stock 1.12.1**: the exe enumerates `patch.MPQ` plus `patch-?.MPQ` where
  `?` is exactly ONE character — so `patch-2..9` and `patch-A..Z` all load
  (verified in exe strings), `patch-10.mpq` never loads. Later name wins;
  numbers sort before letters. The old folk claim "vanilla only loads
  patch/patch-2" is false.
- **OctoWoW's exe (proven in-game here)**: its built-in `patch-1..5` list
  loads at HIGHER priority than every extra archive regardless of name —
  extra archives (our patch-9) can only override files that ship solely in
  the base archives (interface.MPQ etc.), never patch-1..5 content. That is
  why the glue mod hooks `CreditsFrame.xml` (base-only) instead of
  overriding `CharacterSelect.lua` (patch-4). Lettered patches load at even
  LOWER priority than numbered ones on this exe (build.ps1 header note).
  Turtle's stock exe likely behaves the same (UNVERIFIED).
- Vanilla has NO locale subfolder MPQs (`Data\enUS\` starts with TBC);
  locale content is baked into interface/speech MPQs. enUS vs enGB glue
  files differ — building an MPQ from the wrong locale's files can produce
  "login interface files are corrupt" on checking exes.

### 2.2 Archive format rules

- **MPQ v1 only** (32-bit offsets, 4 GB cap). Ladik's/StormLib can create
  v2+ — the 1.12 client can't read those. zlib compression for everything
  (ADPCM/huffman are WAV-only and lossy; no LZMA/sparse).
- No filenames are stored — three hashes of the uppercased,
  backslash-normalized path. Hence: paths case-insensitive, `/`≡`\`, and a
  missing/stale `(listfile)` makes contents unrecoverable garbage names.
  Keep the listfile in sync (Ladik's UI does it automatically).
- Hash table size is a power of two fixed at creation — it caps file count.
- Deletion never reclaims space; only Compact does. **Compacting without a
  complete listfile destroys the unlisted files.** Safe habit for mod
  archives: delete `(attributes)` entirely rather than let it desync.
- The game holds its MPQs open — copy out, edit, swap back with the client
  closed (our build.ps1 already builds in %TEMP% then copies).

### 2.3 Interface (FrameXML/GlueXML) via MPQ

- Two fully isolated Lua VMs: glue (login/realm/char screens,
  `GlueXML.toc`) and game (`FrameXML.toc` + addons). No stock bridge;
  addons can never touch glue.
- **The 1.12 binary contains signature/integrity checks for BOTH trees**
  ("GlueXML is modified or corrupt", "...has corrupt signature", same for
  FrameXML — present in this exe's string table too). Private-server exes
  (Turtle/OctoWoW) ship with these relaxed/removed, which is the only
  reason patch-4/5/9 UI overrides work. **Never assume a glue/FrameXML mod
  is portable to an unmodified client.**
- TOC files load in order; later global definitions silently replace
  earlier — that's the whole override technique. TOCs are read once at
  startup.
- Glue VM facts (proven here, v6–v15): `CreateFrame` and `pcall` exist; NO
  `Get/SetCVar`; no SavedVariables; the only persistent storage is
  `Get/SetSavedAccountName` (and it only reaches Config.wtf on a clean
  flush — a crash on exit loses it; v15 falls back to nampower's
  Write/ReadCustomFile Lua APIs where present). Lua-created buttons don't
  render; template-inherited ones do. The char-row highlight texture is
  anchored 20px left of its 256-wide button — right-anchored art needs an
  extra -20.
- A glue Lua/XML error = blank or broken login screen; only clue is
  `Logs\GlueXML.log` (load errors only). Recovery: delete the mod MPQ.
  Keep that one-step rollback property in every MPQ mod we ship.

### 2.4 DBC / models / textures

- DBCs (`DBFilesClient\*.dbc`, WDBC format) control spells, item display,
  maps, creature models, talents. Tools: WDBX Editor (use 1.12
  definitions), MyDbcEditor, stoneharry's Spell Editor (1.12 support).
  **The server extracts its own copy of the DBCs** — client-only edits to
  gameplay rows (cast times, speeds, taxi paths) desync; display-info edits
  are sync-safe.
- Textures: **BLP2** (BLP1 is Warcraft 3 — won't load), palettized or
  DXT1/3/5, **power-of-two dimensions mandatory**, mipmaps precomputed.
  Tools: BLPConverter, BLP Lab.
- Models: M2 version **256** with render profiles embedded in the file
  (separate .skin files are WotLK+). Porting newer models requires a
  converter (jM2converter), never a rename. Model packs override DBCs too —
  two packs touching the same DBC conflict.

### 2.5 WDB cache

- `WDB\*.wdb` = server-data cache (item/creature/quest/npc/guild/petition
  names and stats). Safe to delete when closed; OctoLauncher wipes it every
  launch. Stale WDB shows old tooltips after server-side changes; fresh WDB
  means `GetItemInfo` nil-windows right after login (design addons for
  this — it happens EVERY launch here).
- Sharing one install across servers cross-contaminates WDB.

---

## 3. DLL mods

### 3.1 Loading

- `VanillaFixes.exe` starts WoW suspended, injects `VfPatcher.dll` (fixes
  the unstable timer source that causes stutter), loads every DLL listed in
  `dlls.txt` (one per line; blank-line separation also parses), resumes,
  and unloads itself by the login screen. It pops a message box when the
  active DLL set changes.
- dxvk is NOT injected — `d3d9.dll` drop-in, loaded by normal DLL search
  order, configured by `dxvk.conf`. If launch silently fails, renaming
  `d3d9.dll` away is diagnostic step one. (`d3d9.enableDialogMode = True`
  fixes alt-tab black screens.) Our v15 notes suspect dxvk in the
  exit-crash cycle — unresolved.
- Alternative loader: namreeb's wowreeb (XML config, per-realm DLL lists).

### 3.2 The ecosystem (all target stock build 5875 offsets)

- **nampower** (pepopo fork, v4.x here): spell queueing — GCD queue,
  non-GCD queue (6), on-swing queue, auto-retry, ~55 ms cast buffer tuned
  for Turtle's server tick. ~25 `NP_*` CVars; NampowerSettings companion
  addon. Adds Lua: `QueueSpellByName`, `GetCurrentCastingInfo`,
  `IsSpellInRange(name, unitOrGuid)`, `GetSpellIdForName`,
  `GetNampowerVersion` (the detection hook), events `SPELL_QUEUE_EVENT`,
  `SPELL_CAST_EVENT`, `SPELL_DAMAGE_EVENT_SELF/OTHER`. Known addon clashes:
  QuickHeal/HealBot/Quiver (they model the cast lock themselves), pfUI
  `/pfcast` mouseover race (patched mouseover.lua gists exist, need
  SuperWoW). Also registers Write/ReadCustomFile Lua APIs per
  nampower_debug.log (our v15 uses them for glue persistence).
- **SuperWoW** (closed source): the big API extender — GUIDs as unit tokens
  everywhere, `UnitExists`→GUID second return, `CastSpellByName(name,
  unitOrGuid)` true mouseover casting, `UNIT_CASTEVENT`, `RAW_COMBATLOG`
  (GUID combat log!), `SpellInfo(id)`, `UnitPosition`, aura spell IDs from
  UnitBuff, `ImportFile`/`ExportFile` (disk I/O from Lua), new CVars
  (FoV, NameplateRange...), macro limit 511. Detect via `SUPERWOW_VERSION`
  global. Requires DEP exception sometimes; wants the exe named `WoW.exe`
  (fixed-offset assumptions). **Currently disabled on this install — broke
  game load on the Octo exe** (octowow.st forum t=28 documents manual
  dlls.txt install as the workaround some users run).
- **UnitXP_SP3**: camera offset, nameplate occlusion behind terrain, better
  tab-target, LoS + distance queries from Lua. One entry point, always
  pcall-guarded: `local ok, r = pcall(UnitXP, "inSight", "player",
  "target")`. Its `timer` callback runs on a SEPARATE THREAD — re-entrancy
  footgun for Lua. Disabled here (load failures on Octo exe).
- **vanilla-tweaks** (brndd): on-disk exe patcher (FoV, farclip, nameplate
  range 41, LAA, sound channels). On OctoWoW: DON'T — the launcher already
  applies equivalent tweaks and hash-checks the exe. SuperWoW conflicts
  with brndd's FoV/sound patches; the tubtubs fork is the SuperWoW-safe
  one.
- Small fry: VanillaMultiMonitorFix (hooks EnumDisplayDevicesA; conflicts
  with no1600x1200.dll), transmogfix, VanillaHelpers (required by HD
  texture packs), AuctionQueryThrottle (pairs with aux-addon),
  perf_boost.dll (selective render distances).

### 3.2b ClassicAPI — the high-value candidate (found 2026-08-23)

github.com/brues-code/ClassicAPI (GPLv3, C++), mirrored on OctoWoW's own
Gitea (octowow.st/git/brues/ClassicAPI) where the community pfUI fork and
SuperCleveRoidMacros REQUIRE it — strong evidence it runs on the Octo exe,
unlike SuperWoW/UnitXP. Actively maintained (release v1.12.1 on
2026-08-23). Single self-contained `ClassicAPI.dll` via dlls.txt; its
companion addon ships embedded in the DLL.

What it adds (per README):
- **Backports 550+ modern API functions and 50+ events** (C_Item,
  C_Container, C_Spell, secure templates, `|T|t` texture markup, real
  nameplate events) plus **much of Lua 5.1** (transpiles `#`, `%`, hex
  literals, modern handler args).
- **Glue VM mirroring — the part that matters for patch-9**: account
  persistence (`SaveAccount`/`GetSavedAccounts`), **character order
  storage**, a **CVar bridge**, `RunScript`, `IsFirstLoadThisSession`.
  This would replace the fragile SavedAccountName-suffix persistence
  (which dies with exit crashes) and could revive the dropped pre-login
  sound sliders.
- `/dump`, `/framestack`, `/etrace` via an embedded DebugTools backport.

**TESTED 2026-08-24: v1.12.1 FAILS on the OctoWoW exe** — VanillaFixes
reports "DLL entry point returned an error (0). Make sure you have a
compatible game client (1.6.1-1.12.1)" and the client never starts. Same
failure class as SuperWoW/UnitXP/transmogFix/multiMonitorFix: the DLL's
entry point rejects (or crashes on) this server's modified 5875 image.
Removed from dlls.txt; the DLL remains in the game dir for retesting.
Worth rechecking on new releases (active project; the octowow.st Gitea
pfUI fork requires it, so Octo users presumably run SOME build — an
issue asking about modified-exe support, or the Gitea mirror having an
Octo-patched build, are both plausible leads).

Verified in OctoLauncher source (`dllsTxt.ts`): the launcher preserves
foreign dlls.txt lines — a manual entry survives launcher updates.

Retest protocol: add `ClassicAPI.dll` to dlls.txt alone (with the
existing three), launch, confirm login screen → char select → world; in
glue check `SaveAccount`/CVar bridge existence; in-game check `/dump`.
If load fails: remove the dlls.txt line, done. If it works, migrate
OctoReorder persistence and re-evaluate baked-vs-live challenge data.

### 3.3 Compatibility and fragility

- dlls.txt line order does not matter for the mainstream trio (per
  SuperWoW's own install guide). The real killers: exe-patcher bytes vs
  runtime detours on the same function, and **custom server exes shifting
  the hardcoded 5875 offsets** — which is exactly why
  SuperWoW/UnitXP/transmogFix/multiMonitorFix failed to load on the Octo
  exe. A DLL working on stock Turtle is not evidence it loads here. Test
  protocol for any new DLL: add to dlls.txt alone, launch, check it
  reaches login, then char select, then world.
- Startup-crash red herrings that are NOT offsets: Windows DEP (add
  exception), antivirus quarantining injected DLLs, missing VC++ x86
  redist.
- Addon graceful degradation idioms: `if SUPERWOW_VERSION then`,
  `if GetNampowerVersion then`, `pcall(UnitXP, "version", ...)`. None of
  these DLL APIs exist in the glue VM (except nampower's file APIs —
  UNVERIFIED, being tested by v15).
- **Ecosystem rot (2026)**: after the Blizzard v. Turtle lawsuit, upstream
  repos vanished (allfoxwy/UnitXP_SP3 deleted, avitasia nampower gitea
  gone). Community archive: github.com/RetroCro/TurtleWoW-Mods. **Keep
  local copies of every DLL version that works on this exe** — we cannot
  count on re-downloading them.
- Building DLLs: 32-bit only (x86), MSVC/MinGW + CMake; namreeb's hadesmem
  is the detours library of choice; offsets come from IDA/Ghidra on 5875 +
  published address maps; vmangos source is the semantic reference for
  protocol/enum meanings.

---

## 4. Warden / server policy

- Warden exists in the 1.12 client but only does what the server core asks.
  vmangos/cmangos cores ship it; checks include memory/module scans and
  **MPQ_CHECK — hashing a named file THROUGH the MPQ chain**, so a patch
  archive overriding that file changes the answer. Cosmetic ≠ undetectable.
- Risk gradient: texture/sound/UI-skin swaps (sync-safe, policy-dependent) <
  silhouette-changing model swaps / effect removal (gray) < collision or
  gameplay DBC edits (visible desync, reads as cheating everywhere).
- Turtle/OctoWoW de facto whitelist what their launchers bundle
  (VanillaFixes, nampower, dxvk, + Turtle offers SuperWoW/UnitXP). Safe
  reading: launcher-listed = allowed; anything else = at your own risk.
  SuperWoW's own README: it makes no attempt to hide from Warden.
- OctoWoW-specific comfort: the launcher itself manages dlls.txt and ships
  DLL mods, and community repos on octowow.st/git include SuperWoW-dependent
  addons — the server is mod-friendly. Still: cosmetic-only for anything we
  distribute.

---

## 5. OctoWoW / launcher specifics

- Lineage: OctoWoW = fork of Turtle WoW at patch 1.17.2 (+ restored 1.18.1
  content), on the classic modified-1.12.1 binary. It does NOT track
  Turtle's newer clients; Turtle's UE5 "2.0" is irrelevant. Community mods
  built against Turtle's *current* patch MPQs may diverge from Octo's
  frozen fork.
- Archive stack here: base MPQs < patch-1..5 (built-in list: 1-3 Turtle
  content, 4 Turtle custom UI incl. TW_UI dispatcher, 5 Octo UI override)
  < patch-O (launcher-managed raid visuals) — and OUR extra archives below
  all of them (§2.1). patch-9.mpq is ours.
- **OctoLauncher** (Electron, open source at octowow.st/git): torrent-syncs
  against a SHA-1 manifest, sidecars patch-5/patch-O, rewrites
  Config.wtf/realmlist each launch, wipes WDB each launch, manages dlls.txt
  and DLL mod installs, patches the exe (FoV/farclip/LAA/nameplate) and
  verifies its hash, auto-updates git addons.
- **Verified in launcher source: `pruneStaleArchives` deletes a Data MPQ
  only if it matches a hardcoded legacy name AND exact byte size** — player
  mod archives reusing a name are deliberately never touched. patch-9.mpq
  is safe across updates.
- Git-addon auto-update FAILS (does not clobber) on checkouts with local
  changes — pfUI/pfQuest/Bagshui local patches survive but log
  merge-conflict errors; a later clean update could silently revert them.
  Keep local diffs mirrored somewhere (or upstream them — the Bagshui
  nil-concat fix is PR-worthy).
- After every server content patch: re-extract patch-4/5 and re-diff our
  overridden files (patch-Z-src carries redefinitions of their functions).

---

## 6. Master pitfall checklist (new project pre-flight)

1. Writing addon Lua? It's Lua 5.0 + globals event model — see §1.1/1.2.
   Copy args to locals; pool frames; throttle OnUpdate; expect
   `GetItemInfo` nil on every launch (WDB wipe).
2. Talking to the server? TW_UI request prefix, response-name reply prefix,
   ≤254 bytes, distinguish no-response from empty-response, retry.
3. Building an MPQ? v1 + zlib + listfile, game closed, late-loading name is
   meaningless on this exe — you can only override base-archive files;
   verify the override actually took effect in-game.
4. Touching glue? No CVars, no SavedVariables, SavedAccountName suffix (or
   nampower file APIs) for persistence, template-inherited widgets only,
   syntax-check with a lenient parser, keep the delete-one-MPQ rollback.
5. Adding a DLL? Test alone first; expect Octo's custom exe to break
   stock-offset DLLs; keep a local binary archive; check DEP/AV before
   blaming offsets.
6. Never patch WoW.exe by hand here — the launcher owns and hash-checks it.
7. Anything gameplay-affecting (DBC timing, collision, automation) is off
   the table for distribution; cosmetic + UI + QoL only.
8. After a server patch: re-diff against new patch-4/5; after a launcher
   update: check its log for addon merge-conflicts and re-verify local
   addon patches survived.

---

## 7. Primary sources worth bookmarking

- townlong-yak.com/framexml/5875 — Blizzard's own 1.12 FrameXML; the
  single best API reference. When in doubt, read what their code does.
- github.com/shagu/wow-vanilla-api (events/API dump) and
  refaim/Vanilla-WoW-Lua-Definitions (IDE autocomplete).
- vanilla-wow-archive.fandom.com — 1.12 API wiki archive.
- wowdev.wiki — MPQ/BLP/M2/DBC formats (use Vanilla category pages).
- turtle-wow.fandom.com — Client Mods, Client Fixes and Tweaks, addon API
  pages for the Turtle dialect.
- github.com/RetroCro/TurtleWoW-Mods — archived DLL binaries + READMEs
  (post-lawsuit rescue archive).
- octowow.st/git — OctoLauncher source, LeviFix, community addons; the
  launcher source answers "what will the updater do to my files"
  definitively.
- Locally: extracted patch-4/5 sources (Ladik's MPQEditor at
  patch-Z-src\tools), `WoW.exe` string dumps, `Logs\GlueXML.log` /
  `FrameXML.log`, OctoLauncher `%APPDATA%\octo-launcher\logs\main.log`.
