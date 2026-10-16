@echo off
rem Click to dim both monitors to their lowest brightness (remembers the previous level for "brightness +").
rem Calls the real script by full path, so this file can live anywhere.
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Flinm\Documents\02 Development\Scripts\Display\dim.ps1" down
if errorlevel 1 pause
