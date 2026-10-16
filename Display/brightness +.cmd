@echo off
rem Click to bring both monitors back to the brightness they had before "brightness -" dimmed them.
rem Calls the real script by full path, so this file can live anywhere.
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Flinm\Documents\02 Development\Scripts\Display\dim.ps1" up
if errorlevel 1 pause
