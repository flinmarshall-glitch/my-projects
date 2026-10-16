' Starts the brightness tray icon with no console window.
' Safe to run twice: the tray app lets only one copy live.
Option Explicit

Dim sh, fso, ps1
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

ps1 = fso.GetParentFolderName(WScript.ScriptFullName) & "\brightness-tray.ps1"
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & ps1 & """", 0, False
