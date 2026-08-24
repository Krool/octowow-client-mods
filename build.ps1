# Rebuild Data\patch-9.mpq from the files under patch-Z-src\Interface\.
# (Numeric name on purpose: this exe gives lettered patches LOWER priority
# than numbered ones - a patch-Z.mpq loads but loses to patch-4/5.)
# Run from anywhere: powershell -File C:\Users\junk7\WoW\patch-Z-src\build.ps1
# The game must be CLOSED (it holds Data\ archives open on some operations).
$src = $PSScriptRoot
$wow = Split-Path $src
$mpq = Join-Path $env:TEMP "patch-9-build.mpq"
$editor = Join-Path $src "tools\MPQEditor.exe"

# Keep the distribution copy of the addon in sync with the live one.
$liveAddon = Join-Path $wow "Interface\Addons\OctoChallenges"
if (Test-Path $liveAddon) {
    Copy-Item "$liveAddon\OctoChallenges.lua","$liveAddon\OctoChallenges.toc" (Join-Path $src "Addons\OctoChallenges\") -Force
}

# Challenge masks are NOT baked any more (v25): the char-select icons read
# CustomData\octoglue-challenges live (written in-world by the addon, or
# mirrored from SavedVariables by tools\realm-status.ps1), so the MPQ built
# here is user-agnostic - safe to publish as a release asset as-is.
# OctoGlueData.lua is a committed static fallback; do not generate it.

if (Test-Path $mpq) { Remove-Item $mpq -Force }
& $editor n $mpq | Out-Null
Get-ChildItem -Recurse -File (Join-Path $src "Interface") | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length + 1)  # e.g. Interface\GlueXML\CharacterSelect.lua
    & $editor a $mpq $_.FullName $rel | Out-Null
    Write-Host "added $rel"
}
Copy-Item $mpq (Join-Path $wow "Data\patch-9.mpq") -Force
Remove-Item $mpq -Force
Write-Host "installed $(Join-Path $wow 'Data\patch-9.mpq')"
