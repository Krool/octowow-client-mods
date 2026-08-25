# Installs the OctoWoW client mods into an existing OctoWoW 1.12.1 install.
# Ship this next to a prebuilt patch-9.mpq (GitHub release zip) - it does NOT
# build the MPQ (that needs MPQEditor; see build.ps1 in the repo).
#
#   powershell -ExecutionPolicy Bypass -File install.ps1 -WoWDir "C:\Games\OctoWoW"
#
# -WoWDir may be omitted when this script already sits inside the WoW folder.
# Close the game first - Data\ archives are locked while it runs.
param([string]$WoWDir)

$here = $PSScriptRoot
if (-not $WoWDir) {
    # walk up from the script location (covers "extracted into the WoW dir")
    $probe = $here
    while ($probe -and -not (Test-Path (Join-Path $probe "realmlist.wtf"))) {
        $probe = Split-Path $probe
    }
    $WoWDir = $probe
}
if (-not $WoWDir -or -not (Test-Path (Join-Path $WoWDir "realmlist.wtf"))) {
    Write-Host "Could not find the WoW folder (no realmlist.wtf). Pass it explicitly:" -ForegroundColor Red
    Write-Host '  powershell -ExecutionPolicy Bypass -File install.ps1 -WoWDir "C:\path\to\OctoWoW"'
    exit 1
}
Write-Host "Installing into: $WoWDir"

# 1. patch-9.mpq -> Data
$mpq = Join-Path $here "patch-9.mpq"
if (-not (Test-Path $mpq)) {
    Write-Host "patch-9.mpq not found next to install.ps1 - download the release zip, or build it with build.ps1." -ForegroundColor Red
    exit 1
}
try {
    Copy-Item $mpq (Join-Path $WoWDir "Data\patch-9.mpq") -Force
    Write-Host "  installed Data\patch-9.mpq"
} catch {
    Write-Host "  Data\patch-9.mpq is locked - close the game and re-run." -ForegroundColor Red
    exit 1
}

# 2. OctoChallenges addon -> Interface\AddOns (left alone if it is a git
#    checkout - the owner's launcher manages that case)
$addonSrc = Join-Path $here "AddOns\OctoChallenges"
$addonDst = Join-Path $WoWDir "Interface\AddOns\OctoChallenges"
if (Test-Path $addonSrc) {
    if (Test-Path (Join-Path $addonDst ".git")) {
        Write-Host "  AddOns\OctoChallenges is a git checkout - not touched"
    } else {
        if (-not (Test-Path $addonDst)) { New-Item -ItemType Directory $addonDst | Out-Null }
        Copy-Item (Join-Path $addonSrc "*") $addonDst -Force
        Write-Host "  installed Interface\AddOns\OctoChallenges"
    }
}

# 3. realm-status helper -> <WoW>\OctoTools + scheduled task (every 2 min;
#    feeds the login screen's realm status line and mirrors challenge masks)
$toolsSrc = Join-Path $here "tools"
$toolsDst = Join-Path $WoWDir "OctoTools"
if (Test-Path (Join-Path $toolsSrc "realm-status.ps1")) {
    if (-not (Test-Path $toolsDst)) { New-Item -ItemType Directory $toolsDst | Out-Null }
    Copy-Item (Join-Path $toolsSrc "realm-status.ps1"), (Join-Path $toolsSrc "realm-status.vbs") $toolsDst -Force
    $vbs = Join-Path $toolsDst "realm-status.vbs"
    # Register-ScheduledTask, NOT schtasks /tr: embedded quotes in /tr get
    # mangled through PowerShell's native-arg escaping (the stored command
    # ends up as //B " path\ and the task fails with result 1 forever).
    $ok = $true
    try {
        $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "//B `"$vbs`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration (New-TimeSpan -Days 3650)
        Register-ScheduledTask -TaskName "OctoGlue realm status" -Action $action -Trigger $trigger -Force -ErrorAction Stop | Out-Null
    } catch { $ok = $false }
    if ($ok) {
        Write-Host "  scheduled task 'OctoGlue realm status' registered (every 2 min)"
        # prime both CustomData files now so the first launch already has data
        powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolsDst "realm-status.ps1")
    } else {
        Write-Host "  could not register the scheduled task - realm status line will stay hidden" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done. Notes:"
Write-Host "  - The login screen auto-checks the server ONCE per client start by"
Write-Host "    briefly logging in a throwaway account ('octoprobe'). Turn it off"
Write-Host "    by just not clicking Check Server; the auto-probe is quick and"
Write-Host "    swallows its own dialogs."
Write-Host "  - Uninstall: delete Data\patch-9.mpq (all glue features gone), the"
Write-Host "    OctoTools folder, Interface\AddOns\OctoChallenges, and run:"
Write-Host '      schtasks /delete /f /tn "OctoGlue realm status"'
Write-Host "  - If the login screen ever breaks after a server patch: delete"
Write-Host "    Data\patch-9.mpq and report it."
