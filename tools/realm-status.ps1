# OctoGlue helper task (v23+; runs every 2 min from the "OctoGlue realm
# status" scheduled task, via realm-status.vbs so no console window flashes).
# Two jobs:
#
# 1. Realm status: fetches octowow.st's realm list into
#    CustomData\octoglue-realmstatus so OctoGlue can show WORLD server status
#    on the login screen. The glue VM has no network primitives beyond
#    DefaultServerLogin and the probe's throwaway account never reaches the
#    realm list, so the website is the only source, and only the nampower
#    ReadCustomFile API can carry it into glue. Format, one ASCII line:
#      v1|<HH:mm>|<online>/<total>|<Name>=<UP|DOWN>,...
#      v1|<HH:mm>|?|fetch failed        (site unreachable or markup changed)
#
# 2. Challenge-mask mirror (v25): copies per-character masks from the
#    OctoChallenges addon's SavedVariables into
#    CustomData\octoglue-challenges (v1|Realm/Name=mask,...) so char-select
#    icons work even where the world VM lacks WriteCustomFile. ADD-ONLY:
#    keys already in the file are the addon's live writes and always win -
#    SavedVariables can be staler than them (they only flush on logout).
#
# The WoW dir is found by walking up from this script (works both from
# patch-Z-src\tools inside the WoW dir and from <WoW>\OctoTools on a shared
# install, where install.ps1 puts it).
$wow = $PSScriptRoot
while ($wow -and -not (Test-Path (Join-Path $wow "realmlist.wtf"))) {
    $wow = Split-Path $wow
}
if (-not $wow) { exit 1 }
$dir = Join-Path $wow "CustomData"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }

# ---- 1. realm status ----
$out = Join-Path $dir "octoglue-realmstatus"
$stamp = Get-Date -Format "HH:mm"
try {
    $html = (Invoke-WebRequest -Uri "https://octowow.st/" -UseBasicParsing -TimeoutSec 15).Content
    $realms = @()
    $rx = '(?s)<div class="realm-row">.*?<div class="realm-name">\s*(.+?)\s*<span.*?<div class="realm-status (\w+)">'
    foreach ($m in [regex]::Matches($html, $rx)) {
        $name = $m.Groups[1].Value -replace '&#039;', "'" -replace '<[^>]+>', ''
        $name = ($name -replace '\s+', ' ').Trim()
        $st = if ($m.Groups[2].Value -ieq 'online') { 'UP' } else { 'DOWN' }
        $realms += "$name=$st"
    }
    if ($realms.Count -eq 0) { throw "no realm rows parsed" }
    $on = @($realms | Where-Object { $_ -match '=UP$' }).Count
    $line = "v1|$stamp|$on/$($realms.Count)|$($realms -join ',')"
} catch {
    $line = "v1|$stamp|?|fetch failed"
}
Set-Content -Path $out -Value $line -Encoding ASCII

# ---- 2. challenge-mask mirror (add-only) ----
try {
    $chalOut = Join-Path $dir "octoglue-challenges"
    $existing = @{}
    $order = @()
    if (Test-Path $chalOut) {
        $s = Get-Content $chalOut -Raw
        foreach ($m in [regex]::Matches($s, '([^=,|\r\n]+)=(\d+)')) {
            $k = $m.Groups[1].Value
            if (-not $existing.ContainsKey($k)) { $order += $k }
            $existing[$k] = $m.Groups[2].Value
        }
    }
    $added = 0
    $acctRoot = Join-Path $wow "WTF\Account"
    if (Test-Path $acctRoot) {
        Get-ChildItem $acctRoot -Directory | ForEach-Object {
            Get-ChildItem $_.FullName -Directory | Where-Object { $_.Name -ne "SavedVariables" } | ForEach-Object {
                $realm = $_.Name
                Get-ChildItem $_.FullName -Directory | ForEach-Object {
                    $sv = Join-Path $_.FullName "SavedVariables\OctoChallenges.lua"
                    if (Test-Path $sv) {
                        $m = Select-String -Path $sv -Pattern '\["mask"\]\s*=\s*(\d+)' | Select-Object -First 1
                        $key = "$realm/$($_.Name)"
                        if ($m -and -not $existing.ContainsKey($key)) {
                            $existing[$key] = $m.Matches[0].Groups[1].Value
                            $order += $key
                            $added++
                        }
                    }
                }
            }
        }
    }
    if ($added -gt 0) {
        $parts = $order | ForEach-Object { "$_=$($existing[$_])" }
        Set-Content -Path $chalOut -Value "v1|$($parts -join ',')" -Encoding ASCII
    }
} catch { }
