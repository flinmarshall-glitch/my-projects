' Runs dim.ps1 (same folder) with no console window, for taskbar buttons.
' Usage: wscript.exe brightness.vbs down|up|toggle
Option Explicit

Dim sh, fso, ps1, action, cmd, rc
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

ps1 = fso.GetParentFolderName(WScript.ScriptFullName) & "\dim.ps1"
If WScript.Arguments.Count > 0 Then action = WScript.Arguments(0) Else action = "toggle"

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """ " & action
rc = sh.Run(cmd, 0, True)

If rc <> 0 Then
    MsgBox "The brightness change failed (exit code " & rc & ")." & vbCrLf & _
           "Run  dim.ps1 status  in a terminal to see why.", 48, "Brightness"
End If
