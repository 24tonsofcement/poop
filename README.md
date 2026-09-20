## Batch card import and remembered folders — 1.10.1

**Import song cards** allows selecting multiple PNGs. Dropping one or several PNG cards onto the game window uses the same sequential batch importer. Invalid cards are reported without stopping the rest; cancelling keeps completed imports and stops remaining work. Importing is available outside active gameplay and lobbies while the importer is idle.

The last import folder and last successful export folder are saved independently across restarts. **Open export folder**, beside Export card, opens the saved destination in the system file manager. Missing remembered folders fall back to the file picker's normal location. Existing settings remain compatible.

Validation includes batch isolation, invalid-card continuation, duplicate paths, cancellation and independent folder persistence/multi-selection in the Godot smoke suite.

## SoundCloud imports and Song Manager — 1.10.0

The shared **Import song** box accepts individual YouTube and SoundCloud links. Songs are filed under their actual source category; osu!mania retains its own category. SoundCloud uses the same instrument/chart generator, with optional track artwork and no YouTube video request. Regeneration and PNG source cards support both providers. Spotify, Bandcamp, Audius and local audio import are not included. Restricted/unavailable tracks can still fail through the provider/downloader.

Open **Settings → Storage → Song Manager** to see each installed song's total MB, background MB and thumbnail MB. Delete an entire song, only its video/still background, or only its thumbnail. Artwork removal preserves audio/charts; song removal preserves leaderboard history. Thumbnail removal is saved as an opt-out to prevent immediate redownloading. Sizes use decimal MB and include a song's legacy shared cover cache where applicable. The bundled demo is excluded. Leave multiplayer before managing files; previews stop during maintenance.

Validation: 97 Python tests cover source/category validation, SoundCloud card round trips, background-download bypass, size totals, deletion boundaries and thumbnail opt-out. Godot checks include the new category, Storage tab and manager navigation. Live SoundCloud downloads and packaged UI validation require the release environment.

## Grades, adaptive instruments and storage cleanup — 1.9.0

- Results and personal-best tables show osu!mania-style accuracy grades: SS = 100%, S > 95%, A > 90%, B > 80%, C > 70%, otherwise D. Grade uses unrounded raw judgement accuracy, independent of hold/combo/hype points; old records gain grades automatically. [Threshold reference](https://osu.ppy.sh/wiki/en/Gameplay/Grade).
- Long holds have no fixed duration ceiling. They require strong pitch and energy continuity throughout the tail, remain limited by same-lane releases, and use a separate 2% head budget with eight seconds between long-hold starts. Short holds remain the default; at most two holds can be active.
- Six-source separation selects detected vocals and drums, plus the two strongest remaining audible sources among bass, guitar, piano and Other instruments. Missing parts are not filled with silent charts. Presence/ranking use energy/activity heuristics; separation leakage can cause mistakes. Unrecognised instruments remain grouped as Other instruments. Demucs specifically documents imperfect piano separation; this is not arbitrary instrument recognition. [Model reference](https://github.com/facebookresearch/demucs).
- After a successful normal launch, obsolete managed versions under `%LOCALAPPDATA%/PulseFour/app/versions` are removed. Running versions are skipped and retried later. This works with the existing launcher. Portable copies elsewhere, songs, scores and settings are not deleted.
- Successful PNG export verifies embedded data before saving and deletes temporary chart requests/thumbnails afterward. The exported PNG retains its data; the playable library song is preserved. Failed exports retain recoverable inputs.
- Song folders use their titles plus a short identity suffix; existing folders migrate when they can be renamed. Internal audio/metadata filenames remain stable for multiplayer and card compatibility.
- YouTube storyboard frames are checked before video download. Consistent still previews use a PNG background; moving, sparse or missing previews retain video. Preview sampling can miss brief motion. Still images use the same dimming control and transfer with multiplayer packs.
- Removed duplicate FFmpeg executable packaging from the license directory (notices/docs remain); model caching retains only the active model; research files are excluded from game resources. Runtime scripts, sprites and the shared demo were audited and retained because they are referenced.

Use **Regenerate chart** to get the new instrument selection and hold rules on existing songs. Card imports retain shared charts unchanged. Existing downloaded videos are not mass-deleted or redownloaded.

Validation: 89 Python tests, including selection, long sustains, update cleanup, PNG still detection/download bypass and title collisions. Grade boundary checks are included in the Godot smoke suite. Real six-stem inference and Windows/Godot packaging are verified in CI; local fixtures mock the separator/downloader.

## Dynamic chart accents and shorter holds — 1.8.0

Generator v9 allows supported three-note accents on Hard and above, and rare four-note accents on Expert and above (at most 2% of measured rows, at least eight seconds apart). Bass/vocals remain single-voice charts. Holds can now be as short as 160ms outside Easy, prefer shorter sustained sounds, and cap continuous tails at 1.6 seconds. The two-active-hold cap and existing release/scoring rules remain unchanged.

Song-relative energy now influences onset selection and spacing; repeated rhythm templates distinguish intensity levels so a quiet pattern does not suppress a louder repeat. Hype combines audio energy lifts with representative chart activity, and instrument solos require chart activity when charts are available. This is signal-based analysis, not guaranteed chorus recognition.

Use **Regenerate chart** for existing songs to receive the new notes and hype analysis. Hype-only analysis preserves notes. Imported PNG cards preserve their author's embedded charts and hype metadata.

Validation: 76 Python tests; [three supplied audio clip measurements](research/dynamics-benchmark.json). Clip measurements use full mixes, not isolated stems, and do not replace listening/playtesting. Windows packaging and Godot validation run in GitHub Actions.

## Sample-informed chart generation — 1.7.0

Analyzed 169 native 4K charts from the supplied 47-set archive. Generator v8 adds conservative audio-supported doubles, fast finger-flow planning, and consistent simplification of repeated rhythmic gestures. The two-active-hold cap remains. New YouTube imports use the update; use **Regenerate chart** for existing songs. PNG card imports keep the shared charts unchanged.

Read [the findings, measurements and limitations](research/mania-sample-study.md). This was a user-supplied sample, not a verified top-100 ranking.

## Card export refinements — 1.6.1

Card export remembers the folder of the last successful export across restarts, and defaults to the selected song title followed by `.png`. Exported artwork shows the title and DATA CARD label without the game name. Existing cards remain compatible.

## PNG data cards and fullscreen fix — 1.6.0

Open **Song Library → Export card** for a YouTube song. The card shows its thumbnail, title, and DATA CARD label. Charts for every instrument and difficulty, timing and hype metadata are embedded with the canonical YouTube link. Audio/video are not included. Send the original PNG as a file/document; re-encoding it as a photo may remove its chart data.

Use **Import song card**, or drop one PNG onto the menu. The receiving computer downloads audio and attempts the video, then installs the shared charts without generating replacements. If video is unavailable, audio remains playable; use Download video later. Unavailable audio or a changed duration stops installation. Different chart variants get separate library entries; importing the same card again reuses the installed copy. Thumbnail export requires its artwork to have loaded.

Fullscreen now expands the canvas to the display aspect ratio instead of adding side bars. Layout checks cover 16:9, ultrawide, and 5:4.

## Midnight cabinet redesign — 1.5.0

The music carousel now occupies a dedicated stage beside a scrollable player-entry dock. Library filters sit above the stage, records below it, and import tools live in an expandable bottom drawer. The early-2000s cabinet direction uses smoked blue panels, metallic trim, amber indicators, segmented meters, a chrome CD and beveled notes. Existing settings, multiplayer, previews, calibration and the carousel overlap fix remain intact.

## Record-cabinet redesign — 1.4.0

A new ivory, ink-black, vermilion and cobalt visual system replaces the navy/neon interface. Bold typography, printed panels, catalogue-style song jackets, a record transport button, new switch/slider controls and flat graphic notes retain the existing control positions. Carousel cards are opaque and their borders stay behind cards in front of them. Motion, fullscreen, settings categories and all gameplay features remain available.

## Arcade interface update — 1.3.0

Fullscreen is available in Settings → Display and with F11, and is remembered between launches. Settings now has seven categories: Display, Timing, Audio, Notes & Video, Effects, Hype, and Accessibility. The carousel remains central, with animated selection frames, orbital backgrounds, sharper layered panels, a framed CD play button and coordinated transitions. Reduced motion stops decorative animation. Existing songs, multiplayer, calibration and scoring features remain available.

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

## Fluid interface (1.2.0)

The menu, settings, leaderboards and lobby share softer panels, consistent depth and animated screen changes. Buttons lift on hover or keyboard focus and compress on press. The Play control is a vector CD: clicking it spins the disc, fades the preview audio, then fades into the selected song. A launch lock prevents repeated clicks from starting multiple rounds. Search, carousel selection and live lobby refreshes do not replay whole-screen transitions. Missing artwork uses an original disc-themed placeholder.

Settings includes **Reduced motion**, which disables menu sliding, hover scaling, disc rotation, moving backgrounds, carousel travel and gameplay screen shake. Short opacity fades remain. UI transitions are covered by the Windows build's new interaction smoke test, including rapid navigation, outgoing input blocking, double clicks and reduced-motion launching.
