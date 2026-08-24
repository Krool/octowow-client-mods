# Fetches octowow.st's realm status into CustomData\octoglue-realmstatus so
# OctoGlue (v23+) can show WORLD server status on the login screen. The glue
# VM has no network primitives beyond DefaultServerLogin, and the probe's
# throwaway account is rejected at auth - it can never reach the realm list.
# The website is the only realm-status source, and only the nampower
# ReadCustomFile API can carry it into glue. Runs from a scheduled task
# ("OctoGlue realm status", every 2 min, via realm-status.vbs so no console
# window flashes). File format, one ASCII line:
#   v1|<HH:mm>|<online>/<total>|<Name>=<UP|DOWN>,...
#   v1|<HH:mm>|?|fetch failed          (site unreachable or markup changed)
$src = Split-Path $PSScriptRoot
$wow = Split-Path $src
$dir = Join-Path $wow "CustomData"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
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
