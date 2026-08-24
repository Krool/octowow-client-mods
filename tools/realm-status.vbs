' Silent wrapper for realm-status.ps1: a scheduled task running powershell
' directly flashes a console window every 2 minutes; wscript //B + hidden
' window style does not. Registered by:
'   schtasks /create /f /tn "OctoGlue realm status" /sc minute /mo 2
'     /tr "wscript.exe //B \"<this file>\""
Dim fso: Set fso = CreateObject("Scripting.FileSystemObject")
Dim here: here = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("Wscript.Shell").Run _
    "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
    & here & "\realm-status.ps1""", 0, False
