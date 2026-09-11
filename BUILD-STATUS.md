# Delivery validation — 2026-09-09

## Artifact status

**Source-only delivery. No Windows executable is included.**

Godot and Windows export templates were absent. A request to download build tools was blocked by the environment's network approval policy. Windows/Wine was also unavailable. No Windows export, graphical run, or Godot parser run was performed. The Windows build script and workflow are supplied, not certified as successful builds.

## Executed successfully

`python3 -m unittest discover -s PulseFour/tests -v`

**12 tests passed** in approximately 3.3 seconds:

- Mania lane mapping and hold duration parsing.
- Rejection of non-mania and non-4K maps.
- Rejection of invalid/overlapping holds.
- Archive path traversal rejection.
- Audio path traversal rejection.
- YouTube URL validation/canonicalization.
- Silence creates no fabricated notes.
- Synthetic onset alignment, spacing, difficulty density and deterministic generation.
- Real `.osz` extraction, FFmpeg WAV conversion, difficulty grouping and idempotent reimport.
- Structured importer errors.
- Cooperative cancellation signal.
- YouTube pipeline chart/category wiring with simulated downloader and separator, using real WAV analysis and pack commit code.

Python compilation checks also passed for importer, scripts and Python tests. The original 50-second demo WAV and 16 authored part/difficulty charts were generated and included.

## Not executed

- Godot loading, GDScript parsing, gameplay smoke tests and visual inspection.
- Real keyboard play, hold timing, audio synchronization or four-player rollover.
- Windows build/launch, PyInstaller freezing, or bundled model loading.
- Live YouTube download or actual Demucs source separation.

The mocked pipeline test does not establish that live downloading or model inference works. `tests/smoke.gd` and the Windows build's frozen separation test are provided to check those local runtime components when the required tools are available. Live YouTube and human gameplay still require manual testing after a successful build.
