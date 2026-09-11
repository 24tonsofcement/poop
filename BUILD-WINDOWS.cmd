@echo off
cd /d "%~dp0"
echo This builds Pulse Four from source. Python 3.11 x64 and internet are required.
powershell.exe -NoProfile -File "%~dp0BUILD-WINDOWS.ps1"
if errorlevel 1 (
  echo Build failed. Read the error above and BUILD-WINDOWS.md.
  pause
  exit /b 1
)
echo Done. Extract dist\PulseFour-Windows-x64.zip and run PulseFour.exe.
pause
