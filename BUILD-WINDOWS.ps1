# Source build: requires Windows x64, Python 3.11 x64, and internet access.
# Outputs a portable game folder and ZIP. The result needs no Python or Godot install.
[CmdletBinding()]
param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-Location $PSScriptRoot
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
function RunGodot([string]$Program, [string[]]$Arguments) {
    $LogPath = Join-Path $PSScriptRoot 'build/godot-check.log'
    & $Program @Arguments '--log-file' $LogPath
    $Code = $LASTEXITCODE
    $Log = if (Test-Path $LogPath) { Get-Content $LogPath -Raw } else { '' }
    if ($Code -ne 0 -or $Log -match '(SCRIPT ERROR|Parse Error|ERROR:)') {
        throw "Godot check failed. See $LogPath"
    }
}
function Download([string]$Url, [string]$To) {
    if (!(Test-Path $To)) {
        Write-Host "Downloading $(Split-Path $To -Leaf)…"
        Invoke-WebRequest -Uri $Url -OutFile "$To.partial" -UseBasicParsing
        Move-Item "$To.partial" $To -Force
    }
}
Run $Python @('scripts/check_python.py')
$Build = Join-Path $PSScriptRoot 'build'
$Cache = Join-Path $Build 'downloads'
$Release = Join-Path $PSScriptRoot 'dist\PulseFour'
if (Test-Path $Release) { Remove-Item $Release -Recurse -Force }
New-Item -ItemType Directory -Force $Build,$Cache,$Release | Out-Null
# Hide tooling from the Godot resource importer.
New-Item -ItemType File -Force (Join-Path $Build '.gdignore'),(Join-Path $PSScriptRoot 'dist\.gdignore') | Out-Null
$Version = '4.4.1-stable'
$GodotZip = Join-Path $Cache 'godot.zip'
$TemplatesZip = Join-Path $Cache 'templates.zip'
Download "https://github.com/godotengine/godot-builds/releases/download/$Version/Godot_v${Version}_win64.exe.zip" $GodotZip
Download "https://github.com/godotengine/godot-builds/releases/download/$Version/Godot_v${Version}_export_templates.tpz" $TemplatesZip
Expand-Archive $GodotZip (Join-Path $Build 'godot') -Force
Copy-Item $TemplatesZip (Join-Path $Cache 'templates-expand.zip') -Force
Expand-Archive (Join-Path $Cache 'templates-expand.zip') (Join-Path $Build 'templates') -Force
$Godot = Join-Path $Build "godot\Godot_v${Version}_win64_console.exe"
$TemplateDir = Join-Path $env:APPDATA 'Godot\export_templates\4.4.1.stable'
New-Item -ItemType Directory -Force $TemplateDir | Out-Null
Copy-Item (Join-Path $Build 'templates\templates\*') $TemplateDir -Recurse -Force
if (!(Test-Path (Join-Path $Build 'venv\Scripts\python.exe'))) {
    Run $Python @('-m', 'venv', (Join-Path $Build 'venv'))
}
$VenvPython = Join-Path $Build 'venv\Scripts\python.exe'
Run $VenvPython @('-m','pip','install','--upgrade','pip')
Run $VenvPython @('-m','pip','install','torch==2.5.1','torchaudio==2.5.1','--index-url','https://download.pytorch.org/whl/cpu')
Run $VenvPython @('-m','pip','install','-r','importer/requirements.txt')
$ToolsDir = Join-Path $Build 'external-tools'
New-Item -ItemType Directory -Force $ToolsDir | Out-Null
Download 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' (Join-Path $ToolsDir 'yt-dlp.exe')
Download 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS' (Join-Path $Cache 'yt-dlp-checksums.txt')
$Expected = ((Get-Content (Join-Path $Cache 'yt-dlp-checksums.txt') | Where-Object { $_ -match '\s+yt-dlp\.exe$' }) -split '\s+')[0]
if (!$Expected -or (Get-FileHash (Join-Path $ToolsDir 'yt-dlp.exe') -Algorithm SHA256).Hash.ToLower() -ne $Expected.ToLower()) { throw 'yt-dlp checksum mismatch. Clear build/downloads and build/external-tools to refresh.' }
Download 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip' (Join-Path $Cache 'deno.zip')
Expand-Archive (Join-Path $Cache 'deno.zip') $ToolsDir -Force
# FFmpeg LGPL shared build; retain the complete distribution and its license.
Download 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-lgpl-shared.zip' (Join-Path $Cache 'ffmpeg.zip')
Expand-Archive (Join-Path $Cache 'ffmpeg.zip') (Join-Path $Build 'ffmpeg') -Force
$FFRoot = (Get-ChildItem (Join-Path $Build 'ffmpeg') -Directory | Select-Object -First 1).FullName
Copy-Item (Join-Path $FFRoot 'bin\*') $ToolsDir -Force
$env:PATH = "$ToolsDir;$env:PATH"
$ModelDir = Join-Path $Build 'models'
Run $VenvPython @('scripts/cache_models.py', $ModelDir)
Run $VenvPython @('scripts/make_demo.py','--audio-only')
Run $VenvPython @('scripts/make_video_smoke.py')
Run $VenvPython @('-m','unittest','discover','-s','tests','-p','test_*.py','-v')
RunGodot $Godot @('--headless','--path',$PSScriptRoot,'--editor','--import')
RunGodot $Godot @('--headless','--path',$PSScriptRoot,'--script','tests/smoke.gd','--quit-after','600')
RunGodot $Godot @('--headless','--path',$PSScriptRoot,'--export-release','Windows Desktop',(Join-Path $Release 'PulseFour.exe'))
Run $VenvPython @('-m','PyInstaller','--noconfirm','--clean','--onedir','--console','--name','PulseImporter',
    '--distpath',(Join-Path $Build 'frozen'),'--workpath',(Join-Path $Build 'pyinstaller'),'--specpath',$Build,
    '--paths',(Join-Path $PSScriptRoot 'importer'),'--collect-all','demucs','--collect-all','torch','--collect-all','torchaudio',
    '--collect-all','soundfile','--collect-all','dora','--collect-all','openunmix','--hidden-import','scipy.signal',
    (Join-Path $PSScriptRoot 'importer\worker.py'))
$ImporterOut = Join-Path $Release 'importer'
New-Item -ItemType Directory -Force $ImporterOut | Out-Null
Copy-Item (Join-Path $Build 'frozen\PulseImporter\*') $ImporterOut -Recurse -Force
Copy-Item $ToolsDir (Join-Path $ImporterOut 'tools') -Recurse -Force
Copy-Item $ModelDir (Join-Path $ImporterOut 'models') -Recurse -Force
Copy-Item LICENSE,THIRD-PARTY.md,BUILD-STATUS.md $Release -Force
Copy-Item README.md (Join-Path $Release 'SOURCE-README.md') -Force
Run $VenvPython @('-m','PyInstaller','--noconfirm','--onefile','--console','--name','PulseLobby','--distpath',$Release,'--workpath',(Join-Path $Build 'lobby-pyinstaller'),'--specpath',$Build,'server/lobby_server.py')
Run $VenvPython @('scripts/run_online_smoke.py',$Godot,'--server-exe',(Join-Path $Release 'PulseLobby.exe'))
Copy-Item ONLINE-MULTIPLAYER.txt $Release -Force
New-Item -ItemType Directory -Force (Join-Path $Release 'shared-demo') | Out-Null
Copy-Item 'game/demo/audio.wav' (Join-Path $Release 'shared-demo/audio.wav') -Force
@'
PULSE FOUR
Extract this entire folder and run PulseFour.exe. Keep importer/ beside it.
Choose a song, 1-4 players, and each player's instrument and difficulty.
P1: A S D F   P2: J K L ;   P3: Q W E R   P4: U I O P
Click menu key buttons to rebind. Esc pauses. F5 restarts.
Tap at the glowing line; hold long notes until their tails arrive.
Import .osu with its audio, or .osz. Native 4-key osu!mania only.
YouTube imports generate drums, bass, vocals and accompaniment charts at four difficulties.
YouTube needs internet; completed songs play offline. CPU generation can take several minutes.
Positive timing offset makes notes arrive later. Use a rollover-capable keyboard for multiplayer.
SOURCE-README.md contains full controls, technical notes and the original source-delivery context.
BUILD-STATUS.md records this build's checks and remaining manual tests.
'@ | Set-Content (Join-Path $Release 'README.txt')
$Licenses = Join-Path $Release 'licenses'
Run $VenvPython @('scripts/collect_licenses.py', $Licenses)
Copy-Item $FFRoot (Join-Path $Licenses 'ffmpeg-distribution') -Recurse -Force
Download 'https://raw.githubusercontent.com/godotengine/godot/4.4.1-stable/LICENSE.txt' (Join-Path $Licenses 'GODOT-LICENSE.txt')
Download 'https://raw.githubusercontent.com/denoland/deno/main/LICENSE.md' (Join-Path $Licenses 'DENO-LICENSE.md')
Download 'https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/LICENSE' (Join-Path $Licenses 'YT-DLP-LICENSE.txt')
Run (Join-Path $ImporterOut 'PulseImporter.exe') @('--help')
# Exercise the frozen dependency graph and bundled weights on a tiny local clip.
$SmokeAudio = Join-Path $Build 'smoke.wav'
Run (Join-Path $ToolsDir 'ffmpeg.exe') @('-nostdin','-y','-i',(Join-Path $PSScriptRoot 'game\demo\audio.wav'),'-t','3',$SmokeAudio)
Run (Join-Path $ImporterOut 'PulseImporter.exe') @('--separate',$SmokeAudio,(Join-Path $Build 'smoke-stems'))
if (!(Test-Path (Join-Path $Build 'smoke-stems\htdemucs\smoke\drums.wav'))) { throw 'Frozen stem smoke test failed' }
# Stop a stale lobby process so a previous run cannot lock the release folder.
Get-Process -Name 'PulseLobby' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400
# Launch the exported executable headlessly so missing packs/runtime errors fail the build.
RunGodot (Join-Path $Release 'PulseFour.exe') @('--headless','--quit-after','3')
@'
Windows build completed by BUILD-WINDOWS.ps1.
Passed Python tests, Godot gameplay smoke tests, frozen stem separation, and headless exported launch.
Real keyboard/audio latency, visual layout, and live YouTube downloads still require manual testing.
'@ | Set-Content (Join-Path $Release 'BUILD-STATUS.md')
$Zip = Join-Path $PSScriptRoot 'dist\PulseFour-Windows-x64.zip'
if (Test-Path $Zip) { Remove-Item $Zip }
# Python ZipFile supports bundles larger than Compress-Archive's limits.
Run $VenvPython @('scripts/finish_repair.py','zip',$Release,$Zip)
Write-Host "Built: $Zip"
