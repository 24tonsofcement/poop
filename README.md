# Pulse Four

A Godot 4.4.1 four-lane rhythm game with local keyboard players, manual LAN/internet lobbies, osu!mania imports and instrument-specific generated charts, plus the arcade visuals and audio visualizer.

## Play and update

Download **PulseFour-Launcher.exe** from [Releases](https://github.com/24tonsofcement/poop/releases/latest). Keep using that executable to start the game. No Python, Godot, administrator account, build script or manual ZIP extraction is required.

A small window checks the latest published stable release each time you launch. A new release downloads automatically, verifies its SHA-256 digest, unpacks into a separate version folder, and passes a headless game launch check before becoming active. If checking or updating fails, an already installed version still launches. First installation needs internet. The first download includes the large audio separation dependencies and models; subsequent releases currently download the complete bundle too.

App files are under `%LOCALAPPDATA%\PulseFour\app\versions`. Songs, settings and scores continue using Godot's existing `%APPDATA%\Godot\app_userdata\Pulse Four` folder. Updates never overwrite that data. Previous app versions remain available for recovery. The launcher does not overwrite running game or lobby executables. Use the launcher, rather than an executable inside a version folder, for update checks.

## Release a change

1. Edit source and run the relevant tests.
2. Increment `VERSION` (for example `1.0.1`).
3. Commit and push to `main`. GitHub publishes the new version after the build passes.

GitHub Actions builds on pushes to main and on version tags. It publishes only versions that do not already have a release. The **Run workflow** button can also publish the version in `VERSION`. Release assets remain a draft until both uploads finish; failed builds do not reach players. Never reuse or overwrite a published version. Pushing changes without incrementing VERSION produces build artifacts and leaves the existing release unchanged.

`launcher/` owns update/download/install logic; `game/` owns gameplay and menus; `importer/` owns chart generation; `server/` owns lobby networking; `scripts/` owns build and packaging. The stable launcher contract uses `PulseFour-update.zip`, semantic release tags and GitHub asset SHA-256 digests. Future launcher protocol changes require a compatible migration or a new launcher download.

## Development

Python 3.11 x64: install CPU torch/torchaudio 2.5.1 and `importer/requirements.txt`, then run `python -m unittest discover -s tests -p 'test_*.py'`. Open `project.godot` in Godot 4.4.1. Windows builds use `BUILD-WINDOWS.ps1`; CI runs the same script. Update engine versions in the build script and export presets together.

Windows runtime, real audio/key latency, live YouTube imports and remote internet connectivity still require real-device testing. Logs from failed update attempts are saved in `%LOCALAPPDATA%\PulseFour\app\update-error.log`.

## Hype moments and timing calibration (1.1.0)

New imports detect energy lifts, recurring energetic phrases and (for separated YouTube instruments) solos. These are audio heuristics, not guaranteed semantic chorus labels. In Settings, **Analyze hype for selected song** adds detection to older imports while preserving their notes, audio and scores; YouTube analysis repeats stem separation and can take several minutes.

Hype defaults to a 2× score multiplier on top of the existing streak multiplier. Missing a note or a released hold's required tail removes the extra bonus for the rest of that section; the next section restores eligibility. Releasing a hold early still preserves the streak. Overlapping sections merge, so a solo cannot silently restore a bonus lost in the same chorus. Solo bonuses affect only that instrument. Settings offer detection sensitivity, bonus enable/multiplier, beat glow, expanding beat rings and gentle shake; each effect slider at zero disables that effect. Beat timing drives pulses and the song spectrum modulates glow. Effect settings do not affect scores. Personal best keys separate hype scoring rules and detected sections; online uses fixed 2×/50% sensitivity and validates identical hype metadata between peers.

After finishing a song, Settings shows each player's early/late counts, median error and timing spread. **Apply recommended offset** sets the shared offset to the run's starting offset plus median signed hit error. Hold heads count once; recovery tails and misses are excluded. At least 12 hits and reasonably consistent timing are required. The recommendation is an estimate of timing bias, not a hardware latency measurement, and applying it repeatedly does not compound it. The last-song summary survives a restart.
