# OctoGlue helper task (v23+; runs every 2 min from the "OctoGlue realm
# status" scheduled task, via realm-status.vbs so no console window flashes).
# Two jobs:
#
# 1. Realm status: probes the world-server TCP ports on play.octowow.st into
#    CustomData\octoglue-realmstatus so OctoGlue can show WORLD server status
#    on the login screen. The glue VM has no network primitives beyond
#    DefaultServerLogin and the probe's throwaway account never reaches the
#    realm list, so an outside check is the only source, and only the
#    nampower ReadCustomFile API can carry it into glue. Format, one ASCII
#    line:
#      v1|<HH:mm>|<online>/<total>|<Name>=<UP|DOWN>,...
#      v1|<HH:mm>|?|net down            (our own uplink is down, not theirs)
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
# 2026-08-31: octowow.st moved behind a BlazingFast JS challenge that plain
# HTTP cannot pass (the page only renders in a real browser), so the old
# website scrape is dead. Realm status now comes from direct TCP probes of
# the world-server ports on the game host: a port accepts connections only
# while its world server process is listening, which is exactly the layer
# the 2026-08-24 outage broke (auth up, worlds down). Ports found from the
# live client connection (N'Zoth = 8091 confirmed in netstat); the
# C'Thun=8090 / Y'Shaarj=8092 assignment follows the website's realm order
# and is UNVERIFIED - confirm the names during the next partial outage.
# Caveat (same as the glue probe's v22 lesson): a dying host that still
# accepts TCP reads UP; only a dead listener reads DOWN.
$out = Join-Path $dir "octoglue-realmstatus"
$stamp = Get-Date -Format "HH:mm"
$gameHost = "play.octowow.st"
$realmPorts = @(
    @{ Name = "C'Thun";   Port = 8090 },
    @{ Name = "N'Zoth";   Port = 8091 },
    @{ Name = "Y'Shaarj"; Port = 8092 }
)

function Test-TcpPort($tcpHost, $port, $timeoutMs) {
    $t = New-Object Net.Sockets.TcpClient
    try { return ($t.ConnectAsync($tcpHost, $port).Wait($timeoutMs) -and $t.Connected) }
    catch { return $false }
    finally { $t.Close() }
}

$realms = @()
$on = 0
foreach ($r in $realmPorts) {
    if (Test-TcpPort $gameHost $r.Port 4000) {
        $realms += "$($r.Name)=UP"
        $on++
    } else {
        $realms += "$($r.Name)=DOWN"
    }
}
if ($on -eq 0 -and -not (Test-TcpPort "one.one.one.one" 443 4000)) {
    # Nothing reachable AND a known-good host is also unreachable: that is
    # OUR network being down, not the realms - report unknown, never 0/3
    # (glue paints 0/3 as a red "realms are DOWN" override).
    $line = "v1|$stamp|?|net down"
} else {
    $line = "v1|$stamp|$on/$($realmPorts.Count)|$($realms -join ',')"
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
