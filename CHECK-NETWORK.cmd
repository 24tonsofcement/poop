@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CHECK-NETWORK.ps1"
echo.
echo Diagnostic saved to build\network-diagnostic.txt. Send that file if the check fails.
pause
