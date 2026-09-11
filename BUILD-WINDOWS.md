# Building the Windows executable

The delivered source ZIP does not contain an executable. The build recipe below has not been executed in the authoring environment.

## Requirements on the build machine

- Windows 10/11 x64.
- Python **3.11 x64** installed with `python` on PATH. Download: https://www.python.org/downloads/release/python-3119/
- Internet access to GitHub, PyPI, PyTorch's CPU package index, and the Demucs model host.
- Several GB of free space for Godot templates, PyTorch, model weights, and bundled dependencies.

Open PowerShell in the extracted `PulseFour` folder and run:

```powershell
.\BUILD-WINDOWS.ps1
```

Or double-click `BUILD-WINDOWS.cmd`. The script does not change your execution policy. If Windows marks downloaded scripts as blocked, review the script and use the file's Properties → Unblock if your local policy permits. Managed policy restrictions must be resolved by the machine's administrator.

If Python has a different path:

```powershell
.\BUILD-WINDOWS.ps1 -Python 'C:\Path\To\Python311\python.exe'
```

The script downloads Godot **4.4.1** and matching export templates, creates a local build virtual environment, installs CPU PyTorch and the importer, downloads yt-dlp/Deno/FFmpeg, caches Demucs weights, exports the game, freezes the importer, and packages the result. Those runtimes are included in the output folder, so the target player should not need Python, Godot, or separate dependency installs. The final ZIP is much larger than the source because it includes PyTorch and model weights.

## Build gates

The script stops on a failed command. It runs:

1. Python parser, chart analysis, archive import, cancellation and error tests.
2. Godot resource import and gameplay smoke tests.
3. Windows game export with an embedded PCK.
4. Frozen importer startup and real three-second Demucs separation using bundled tools/weights.
5. Headless launch of the exported game.

Only after these checks does it create:

```text
dist/PulseFour-Windows-x64.zip
```

Extract the entire ZIP and run `PulseFour/PulseFour.exe`. Keep the `importer` directory with it. The executable alone is not the complete game package.

The build checks do not test real keyboard rollover, speakers/latency, visual layout, or a live YouTube download. Before considering the result a tested release, play the demo with 1–4 people, test holds/pause/restart/rebinding, import a known 4K `.osz`, and generate a permitted YouTube video. Verify all four instrument parts and four difficulties. A build that fails should be treated as failed; this source package does not certify a working Windows release.

## Editor-only development

The built-in demo needs only Godot 4.4.1. To import in the editor, use a Python 3.11 environment with:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install torch==2.5.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cpu
.venv\Scripts\python -m pip install -r importer\requirements.txt
$env:PULSE_PYTHON = "$PWD\.venv\Scripts\python.exe"
```

Put `ffmpeg.exe`, its DLLs, `ffprobe.exe`, `yt-dlp.exe`, and `deno.exe` in `importer/tools/` or on PATH. The editor must inherit `PULSE_PYTHON`, so launch Godot from that shell. The first separation downloads weights into `importer/models/` unless `TORCH_HOME` is supplied. The full build caches and bundles the model instead.

## CI option

Commit the extracted project contents to a repository you control. Run the included **Windows release build** workflow from Actions. It runs the same script and uploads the ZIP if successful. No repository was created and no workflow was run as part of this delivery.

## Updating or retrying

The build caches downloads in `build/downloads/` and tools in `build/external-tools/`. For a yt-dlp refresh, remove both cached downloader files and its checksum file before rebuilding. The Godot and Python package versions are pinned; the external downloader/runtime/FFmpeg downloads follow upstream releases, so the recipe is automated but not byte-for-byte reproducible.
