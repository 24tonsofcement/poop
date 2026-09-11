# Update the existing Pulse Four build using cached tools and dependencies.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
function Stop-LobbyServers {
    Get-Process -Name 'PulseLobby' -ErrorAction SilentlyContinue | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Milliseconds 400
}
function Copy-WithRetry([string]$Source, [string]$Destination) {
    for ($Attempt = 1; $Attempt -le 8; $Attempt++) {
        try { Copy-Item $Source $Destination -Force -ErrorAction Stop; return }
        catch {
            Stop-LobbyServers
            if ($Attempt -eq 8) { throw }
            Start-Sleep -Milliseconds (250 * $Attempt)
        }
    }
}
$Build = Join-Path $PSScriptRoot 'build'
$Release = Join-Path $PSScriptRoot 'dist\PulseFour'
$Python = Join-Path $Build 'venv\Scripts\python.exe'
$Godot = Join-Path $Build 'godot\Godot_v4.4.1-stable_win64_console.exe'
$Spec = Join-Path $Build 'PulseImporter.spec'
$Importer = Join-Path $Release 'importer'
$Tools = Join-Path $Importer 'tools'
$Models = Join-Path $Importer 'models'
$Helper = Join-Path $PSScriptRoot 'scripts\finish_repair.py'
$Game = Join-Path $Release 'PulseFour.exe'
$Stage = Join-Path $Build ('feature-update-' + [Guid]::NewGuid().ToString('N'))
foreach ($Required in @($Python,$Godot,$Spec,$Helper,$Game,(Join-Path $Tools 'ffmpeg.exe'),(Join-Path $Models 'hub\checkpoints'))) {
    if (!(Test-Path $Required)) { throw "Missing $Required. Extract this update into the original PulseFour project with its existing build and dist folders." }
}
New-Item -ItemType Directory -Force $Stage | Out-Null
$env:PATH = "$Tools;$env:PATH"
$env:TORCH_HOME = $Models
$env:PYTHONUTF8 = '1'
function GodotCheck([string[]]$Arguments) {
    $LogFile = Join-Path $Stage 'godot-check.log'
    if (Test-Path $LogFile) { Remove-Item $LogFile }
    & $Godot @Arguments '--log-file' $LogFile
    if ($LASTEXITCODE -ne 0) { throw 'Godot command failed.' }
    if (!(Test-Path $LogFile)) { throw 'Godot did not produce a validation log.' }
    if ((Get-Content $LogFile -Raw) -match '(SCRIPT ERROR|Parse Error|ERROR:)') { throw "Godot check failed. See $LogFile" }
}
Write-Host '[1/6] Testing chart timing, hold generation and existing imports...'
Run $Python @('-m','unittest','discover','-s','tests','-p','test_*.py','-v')
Run $Python @('scripts/make_video_smoke.py')
Write-Host '[2/6] Checking the Godot scripts, leaderboards, combo and video playback...'
GodotCheck @('--headless','--path',$PSScriptRoot,'--editor','--import')
# Use a separate Windows app-data folder for tests, preserving player settings/maps.
$OriginalAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $Stage 'test-appdata'
    New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
    GodotCheck @('--headless','--path',$PSScriptRoot,'--script','tests/smoke.gd','--quit-after','600')
    if ((Get-Content (Join-Path $Stage 'godot-check.log') -Raw) -notmatch 'Godot smoke failures: 0') { throw 'Gameplay smoke test did not finish successfully.' }
} finally {
    $env:APPDATA = $OriginalAppData
}
Write-Host '[3/6] Exporting the updated game to a staging folder...'
$StagedGame = Join-Path $Stage 'PulseFour.exe'
GodotCheck @('--headless','--path',$PSScriptRoot,'--export-release','Windows Desktop',$StagedGame)
Write-Host '[4/6] Rebuilding the importer with cached dependencies...'
Run $Python @('-m','PyInstaller','--noconfirm','--distpath',(Join-Path $Build 'frozen'),'--workpath',(Join-Path $Build 'pyinstaller'),$Spec)
Copy-Item (Join-Path $Build 'frozen\PulseImporter\*') $Importer -Recurse -Force
$Smoke = Join-Path $Stage 'smoke.wav'
Run (Join-Path $Tools 'ffmpeg.exe') @('-nostdin','-y','-i',(Join-Path $PSScriptRoot 'game\demo\audio.wav'),'-t','3',$Smoke)
Run (Join-Path $Importer 'PulseImporter.exe') @('--separate',$Smoke,(Join-Path $Stage 'stems'))
Run $Python @($Helper,'verify',(Join-Path $Stage 'stems\htdemucs\smoke'))
Write-Host 'Building the standalone lobby server...'
Run $Python @('-m','PyInstaller','--noconfirm','--onefile','--console','--name','PulseLobby','--distpath',$Stage,'--workpath',(Join-Path $Build 'lobby-pyinstaller'),'--specpath',(Join-Path $Build 'lobby-spec'),'server/lobby_server.py')
Write-Host 'Testing two network clients and host song/video transfer...'
$NetworkAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $Stage 'network-test-appdata'
    New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
    Run $Python @('scripts/run_online_smoke.py',$Godot,'--server-exe',(Join-Path $Stage 'PulseLobby.exe'))
} finally {
    $env:APPDATA = $NetworkAppData
}
Write-Host '[5/6] Testing the updated executable and installing it...'
$LaunchLog = Join-Path $Stage 'export-launch.log'
$Process = Start-Process -FilePath $StagedGame -ArgumentList @('--headless','--quit-after','3','--log-file',('"' + $LaunchLog + '"')) -Wait -PassThru
if ($Process.ExitCode -ne 0 -or !(Test-Path $LaunchLog)) { throw 'Updated executable failed its launch check.' }
if ((Get-Content $LaunchLog -Raw) -match '(SCRIPT ERROR|Parse Error|ERROR:)') { throw "Updated executable reported errors; see $LaunchLog" }
Copy-Item $Game (Join-Path $Stage 'previous-PulseFour.exe') -Force
Copy-Item $StagedGame $Game -Force
Stop-LobbyServers
Copy-WithRetry -Source (Join-Path $Stage 'PulseLobby.exe') -Destination (Join-Path $Release 'PulseLobby.exe')
Copy-Item (Join-Path $PSScriptRoot 'ONLINE-MULTIPLAYER.txt') $Release -Force
New-Item -ItemType Directory -Force (Join-Path $Release 'shared-demo') | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'game\demo\audio.wav') (Join-Path $Release 'shared-demo\audio.wav') -Force
Copy-Item (Join-Path $PSScriptRoot 'UPDATE-NOTES.txt') $Release -Force
@'
Feature update completed via UPDATE-GAME.ps1.
Features: LAN/internet lobbies, host pack download, recurring-riff consistency,
neon arcade graphics, per-lane colors and highway transparency.
Previous combos, personal bests, video and JSON recovery fix retained.
Existing uncapped speed and chart-generation improvements retained.
Passed Python tests, Godot gameplay/network/transfer tests, frozen stem separation, and exported launch.
Real gameplay/visual effects and live YouTube imports still need manual testing.
'@ | Set-Content (Join-Path $Release 'BUILD-STATUS.md')
Write-Host '[6/6] Creating the updated Windows ZIP...'
Run $Python @($Helper,'zip',$Release,(Join-Path $PSScriptRoot 'dist\PulseFour-Windows-x64.zip'))
Write-Host "Built: $(Join-Path $PSScriptRoot 'dist\PulseFour-Windows-x64.zip')"
Write-Host "Run: $Game"
