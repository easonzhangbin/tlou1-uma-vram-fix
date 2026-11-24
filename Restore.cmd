@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch.ps1" -Action Restore %*
if errorlevel 1 echo Failed. Read the error above.
pause
