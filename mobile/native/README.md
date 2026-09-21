# Standalone Android importer

Android branch only. The PC checkout and releases are not modified.

The APK bundles Python, NumPy/SciPy, yt-dlp, FFmpeg, Demucs.cpp and the six-source
htdemucs weights. No companion computer is needed. Downloads and optional Claude
requests need internet; installed songs work offline.

## Generation

The adapter reuses the PC `charting`, `arrangement`, `instruments`, `timing`,
`hype`, `sources` and `song_card` modules. Native separation uses the pinned
Demucs.cpp implementation with bounded-memory overlap-add and whole-song
normalization. The emulator gate compares its output against upstream inference
on an eight-second signal crossing a segment boundary. This is a numerical
regression check, not proof of subjective chart quality or a benchmark on a
physical phone. CPU imports can take much longer than the song; performance
varies with temperature, RAM and phone CPU. Temporary stems are removed after
completion/cancellation. A foreground service keeps ongoing jobs visible.

## Claude assistance

Keys are entered on-device and encrypted using Android Keystore. They are never
in Git, APK assets, logs, prompts or exported cards. Available model IDs come
from the user's authenticated Models API. No model is silently substituted.

The model receives measured per-instrument attack contours, ordered pitch-class
contours, phrase families, tempo, density, supported sustains, candidate hype
windows, and aggregate measurements from the user's 169-chart mania study.
The study is not a verified most-played ranking and this is not model training.
Pattern priors use measured lane transition counts. Claude selects phrase
policies with whole-song context, in bounded batches for long songs. Generation
validates each returned family, pattern and difficulty policy. Edits cannot
invent note timings, add unsupported holds or overlap more than two holds.
Hype decisions may only retain measured candidates and must pass a second
post-edit audio/chart check. Invalid or failed AI calls stop without replacing
a saved chart; ordinary generation is always available without AI.

This is AI-assisted arrangement of measured candidates, not direct audio input
to Claude. API usage is billed to the entered key. Live paid API quality needs
user listening/playtesting and is not certified by offline tests.

## Cards

Android's Storage Access Framework opens PNG cards and exports original PNGs.
Import and export remember separate locations. Export filenames use song titles.
The same bounded, checksummed PNG codec as PC preserves all note timings,
difficulties and hype sections. Import retrieves referenced media without
regenerating the shared chart, and rejects changed audio durations. Temporary
card files are deleted after the picker/import finishes. Share as an original
file: image messengers may strip its private data chunk.

## Runtime updates

Native additions require the new `org.pulsefour.standalone` APK. It uses
`android-standalone` and `godot-4.4.1-android-2`, isolated from the older companion
APK and PC. PCK updates cannot add or change native libraries or bundled Python.
Native updates must be signed with the same retained private signing identity;
Android asks the user to confirm installation. Never commit a signing key.
