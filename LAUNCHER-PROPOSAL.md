# Proposal: ship "OctoGlue" client mods as an optional OctoLauncher mod

**To:** OctoLauncher maintainers (OctoWoW/OctoLauncher)
**From:** Krool — github.com/Krool/octowow-client-mods
**What I'm asking:** add one entry to the launcher's `MODS` list so players can
enable a set of cosmetic login/character-select UI mods with a checkbox,
instead of a manual file copy.

## What it is

A pure client-side UI mod, two cooperating halves:

- **`patch-9.mpq`** — glue-screen (login + character select) features: a
  green/yellow/red server-status lamp, per-character challenge icons on the
  character list, up/down character reordering, and a music on/off toggle.
  Cosmetic + QoL only; no gameplay, timing, DBC, collision, or automation
  changes. It overrides only `Interface\GlueXML\CreditsFrame.xml` (a base-
  archive file), which side-loads our Lua — it never touches `patch-1..5`.
- **`OctoChallenges` addon** — the in-game paperdoll counterpart that queries
  the player's own challenges over the existing `TW_UI` addon channel and
  feeds the character-select icons.

Source and full write-up: github.com/Krool/octowow-client-mods
Rollback for a player is always "delete `Data\patch-9.mpq`".

## Why it needs you

The features that live in `patch-9.mpq` cannot be delivered any other way. An
addon (or the launcher's git-addon flow) can only write to `Interface\AddOns`;
nampower's file APIs are sandboxed to `CustomData\`/`Imports\`; the exe only
loads patch archives from `Data\`. So the only paths to the MPQ are a manual
copy or a launcher mod. This makes it a one-click, hash-verified, update-safe
install for everyone.

## The change (matches your existing schema)

Two edits in `src/common/mods.ts`. First, add the id to `ModIdSchema`:

```ts
export const ModIdSchema = z.enum([
	'dxvk', 'nampower', 'multiMonitorFix', 'superWow', 'transmogFix',
	'unitXp', 'vanillaFixes', 'vanillaHelpers',
	'octoGlue'            // <-- add
]);
```

Then one `MODS` entry. It reuses your `archive` source + `extractMap` exactly
as dxvk/SuperWoW do — I verified `installMod` writes each `extractMap` value
via `path.join(clientDir, dst)` with `fs.ensureDir(path.dirname(target))`, so
a `Data/…` destination lands in the Data folder and subdirs are created:

```ts
{
	id: 'octoGlue',
	name: 'OctoGlue UI',
	version: 'v27',
	description:
		'Login & character-select QoL: server-status lamp, per-character ' +
		'challenge icons, character reordering, music toggle. Cosmetic only.',
	repoUrl: 'https://github.com/Krool/octowow-client-mods',
	requires: ['nampower'],   // used for the live challenge-mask bridge + crash-safe saves; degrades gracefully without it
	source: {
		kind: 'archive',
		url: 'https://github.com/Krool/octowow-client-mods/releases/download/v27/octoglue-launcher.tar.gz',
		apiUrl: 'https://api.github.com/repos/Krool/octowow-client-mods/releases/latest',
		parseLatest: 'githubRelease',
		pinnedTag: 'v27',
		format: 'tar.gz',
		sha256: '46f0a14b5992208821df3bfe75f9ee8bc853f63e9a4d39d6542179ca0a117d2c',
		extractMap: {
			'patch-9.mpq': 'Data/patch-9.mpq',
			'OctoChallenges/OctoChallenges.lua':
				'Interface/AddOns/OctoChallenges/OctoChallenges.lua',
			'OctoChallenges/OctoChallenges.toc':
				'Interface/AddOns/OctoChallenges/OctoChallenges.toc'
		}
	}
}
```

The archive `octoglue-launcher.tar.gz` is a purpose-built asset on the v27
release (forward-slash `ustar` entries, so `tar.x` maps them cleanly):

```
patch-9.mpq
OctoChallenges/OctoChallenges.lua
OctoChallenges/OctoChallenges.toc
```

No other launcher code changes are needed — the Mods tab, install/uninstall,
`installedFiles` tracking, and `sha256` verification all already handle it.

## Safety review (I checked your source, not just claimed it)

- **Prune-safe.** `pruneStaleArchives` (aria2.ts) deletes an MPQ only when its
  name *and exact byte size* match a hardcoded `LEGACY_ARCHIVES` entry.
  `patch-9.mpq` is in neither, so the torrent sync never removes it.
- **Clean uninstall.** You record `installedFiles: written`, so unchecking the
  mod removes exactly `Data/patch-9.mpq` and the two addon files.
- **Integrity pinned.** `sha256` above is enforced by `#downloadTo`.
- **Load order.** Extra archives load below `patch-1..5` on this exe, so the
  mod can only override base-archive files — it cannot shadow your custom UI
  in `patch-4/5`. After any server UI patch I re-diff and re-release.
- **Not a DLL.** No `registerInDllsTxt`; nothing injected. `requires:
  ['nampower']` is only because nampower's `WriteCustomFile`/`ReadCustomFile`
  (present in both the world and glue VMs, per its SCRIPTS.md) carry challenge
  masks live and make order-saves crash-proof; with nampower absent the mod
  still loads and every feature degrades gracefully.

## Alternatives, if you'd rather

- **MPQ-only mod + curated addon.** Drop the two addon lines from `extractMap`
  and instead add `OctoChallenges` to your curated addon sources
  (`addons-sources.ts`) so the addon half auto-updates via git while the MPQ
  ships as the mod. One extra list entry; two moving parts instead of one.
- **Different default.** I'd suggest it ship **not** `recommended` (opt-in),
  like the non-essential mods. Happy to follow whatever bar you set for
  third-party UI.

I'll keep the release tag, archive layout, and sha256 stable, and ping you on
any version bump. Thanks for considering it.
