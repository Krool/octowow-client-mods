' Silent wrapper for realm-status.ps1: a scheduled task running powershell
' directly flashes a console window every 2 minutes; wscript //B + hidden
' window style does not. Register via Register-ScheduledTask (see
' install.ps1) - NOT schtasks /tr, whose embedded quotes get mangled when
' invoked from PowerShell and leave the task failing with result 1.
Dim fso: Set fso = CreateObject("Scripting.FileSystemObject")
Dim here: here = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("Wscript.Shell").Run _
    "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
    & here & "\realm-status.ps1""", 0, False
