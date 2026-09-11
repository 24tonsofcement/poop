$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$Python = Join-Path $PSScriptRoot 'build\venv\Scripts\python.exe'
$Godot = Join-Path $PSScriptRoot 'build\godot\Godot_v4.4.1-stable_win64_console.exe'
$Server = Get-ChildItem (Join-Path $PSScriptRoot 'build\feature-update-*\PulseLobby.exe') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (!$Server) { throw 'No built lobby server found. Run UPDATE-GAME.cmd first.' }
$OriginalAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $PSScriptRoot ('build\network-diagnostic-appdata-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
    & $Python 'scripts/run_online_smoke.py' $Godot '--server-exe' $Server.FullName
    if ($LASTEXITCODE -ne 0) { throw 'Network check failed. Send build\network-diagnostic.txt.' }
} finally { $env:APPDATA = $OriginalAppData }
