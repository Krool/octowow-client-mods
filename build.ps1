# Rebuild Data\patch-9.mpq from the files under patch-Z-src\Interface\.
# (Numeric name on purpose: this exe gives lettered patches LOWER priority
# than numbered ones - a patch-Z.mpq loads but loses to patch-4/5.)
# Run from anywhere: powershell -File C:\Users\junk7\WoW\patch-Z-src\build.ps1
# The game must be CLOSED (it holds Data\ archives open on some operations).
$src = $PSScriptRoot
$wow = Split-Path $src
$mpq = Join-Path $env:TEMP "patch-9-build.mpq"
$editor = Join-Path $src "tools\MPQEditor.exe"

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
