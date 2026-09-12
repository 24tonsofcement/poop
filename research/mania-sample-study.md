# Supplied osu!mania sample: findings and generator changes

Analyzed 2026-09-12. Source: the user's `beatmaps.rar`, not a verified most-played ranking. No source audio or beatmap note sequences are redistributed in the repository.

## What was in the archive

47 beatmapsets contained 375 distinct `.osu` files. The study uses **169 native 4-key charts from 43 sets**, containing **249,557 note heads**. Excluded: 165 charts for other game modes and 41 mania charts with other key counts. Exact duplicate files were removed by SHA-256. Map IDs, filenames, individual measurements, exclusions and the archive hash are in `mania-sample-analysis.json`.

These are multiple difficulties per song, not 169 independent songs or players. The sample is user-selected and includes demanding charts. Difficulty names are inconsistent, so the table below groups by measured note density, not claimed Easy/Expert labels or star ratings. No global population estimates or statistical significance claims are made.

## What the charts do

Statistics below are per-chart medians. A row means notes with exactly the same head timestamp; holds count once at their head.

| Density group | Charts | Notes per active second | Chord rows | Hold heads |
|---|---:|---:|---:|---:|
| Lowest quarter | 42 | 3.81 | 17.5% | 14.4% |
| Second quarter | 42 | 6.98 | 29.1% | 10.1% |
| Third quarter | 42 | 10.47 | 38.3% | 6.6% |
| Highest quarter | 43 | 14.09 | 41.9% | 3.9% |
| Whole sample | 169 | 8.81 | 32.2% | 9.3% |

The useful lesson is progression, not a quota: denser charts in this sample use more simultaneous heads, while their proportion of holds is lower. Our instrument-isolated charts should not automatically copy full-song chord density.

Among adjacent single-note rows at most one beat apart, the median chart has **63.4% cross-hand transitions** and **1.3% same-lane transitions** (168 charts with eligible pairs). This supports a soft preference against accidental rapid finger repeats. It does not justify deleting musically intentional jacks.

Among eligible four-single-note windows, the median chart has 6.6% complete four-lane rolls, 1.4% alternating two-lane trills, and 0.0% four-note same-lane runs (162 charts with eligible windows). The classifier requires near-uniform spacing and counts overlapping windows; these percentages do not sum to 100%, because most windows contain other patterns. They should not be read as percentages of entire songs or musical phrases.

Exact four-beat note-bin recurrence has a median of 7.0%. This is a strict note-layout comparison, not an audio riff detector: shifts, variations, tempo boundaries and different musical meter reduce the match rate. It cannot tell us how often a chorus repeats.

54 charts use more than two simultaneous holds. We deliberately do **not** copy that behavior: the game's two-active-hold rule is retained.

## Changes implemented in generator v8

1. **Supported doubles.** Previously, every detected attack produced one head. Drums can now add a second head when separate frequency regions attack together. Keys/Other/Synth can add one when strong non-harmonic peaks support polyphony. Bass and vocals remain single-voice charts. Doubles use different lanes at an existing detected time; no extra timestamps are invented. Harmonic rejection is heuristic, not perfect transcription.
2. **Difficulty-scaled ceilings.** Chord budgets range from a 6% ceiling for Easy to 36% for Insane, applied conservatively in local windows. They are ceilings, not targets: no evidence means no chord. Short windows may produce none. Only two-note chords are generated in this update.
3. **Finger-flow planning.** A small dynamic program discourages repeated columns and same-hand pressure during fast passages while retaining pitch-lane preferences. Slow repeated pitches remain unchanged. Existing recurring-riff templates are applied afterward.
4. **Consistent gesture thinning.** Onset groups split at natural rests and are capped at eight attacks. Repeated rhythm fingerprints reuse the same simplification mask at each difficulty instead of making a new salience decision for each occurrence. Lower difficulties remain subsets of higher-level onset times. This improves short-gesture consistency; it is not full musical phrase segmentation or tolerance to missing attacks.
5. **Existing safeguards remain.** No same-lane simultaneous duplicates; companion-note spacing checks; next-note-aware hold tails; sparse sustained notes; maximum two active holds. Existing songs and imported data cards are not rewritten.

## Validation and limits

70 Python tests pass, including existing onset-alignment, repeated-riff, density, hold, import/export and update checks. New tests cover chord evidence, harmonic rejection, distinct chord lanes, unchanged head timestamps, single-voice instruments, fast finger flow, slow pitch preservation and repeated thinning masks. The spacing test now evaluates distinct onset rows so legitimate chords are allowed.

Three deterministic 30-second clips (20–50 seconds) from the supplied songs were generated before and after the change using the **full mix as Other**, not separated stems. Results are diagnostic examples, not a listening/playability study:

| Clip | Chord rows, before → after | Rapid same-lane single-row pairs, before → after |
|---|---:|---:|
| Flower Dance | 0/107 → 26/107 | 8/43 → 0/24 |
| Marble Soda | 0/137 → 31/137 | 19/105 → 0/57 |
| Hitorigoto | 0/144 → 27/142 | 18/123 → 1/74 |

Here “rapid” means less than 250 ms. Chord rows are excluded from the single-row-pair metric, so its denominator changes; the reductions do not isolate the effect of lane planning. The reference sample's transition metric instead uses a one-beat maximum, so these two rates must not be compared directly. All timings, denominators and local runtimes are in `arrangement-benchmark.json`. No manually annotated audio alignment ground truth or Windows playtest was available.

## Using the update

New YouTube imports use generator v8. For an existing YouTube song, use **Regenerate chart** to apply it. PNG card import continues to preserve the sender's embedded charts. Saved preferences and the two-hold gameplay rule are unchanged.

## Reproducing the map analysis

Extract the RAR into a local directory, keeping its `.osz` files. Run:

```
python scripts/analyze_mania_patterns.py /path/to/maps --output analysis.json
```

The analyzer reads beatmap text inside ZIP-based `.osz` files without extracting music. Its named pattern classifiers use overlapping fixed windows and should not be reported as independent phrase counts. Chord/hold statistics are direct structural measurements, while semantic relationships to a song require audio analysis and listening.
