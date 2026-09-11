@echo off
cd /d "%~dp0"
echo Close PulseFour.exe before continuing with this update.
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UPDATE-GAME.ps1"
if errorlevel 1 (
  echo Update stopped. Send the error displayed above.
  pause
  exit /b 1
)
echo Update complete. Run dist\PulseFour\PulseFour.exe.
pause
