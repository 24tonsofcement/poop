Superseded by [the supplied-sample study](mania-sample-study.md), completed after the user provided beatmaps.rar. The following records the earlier data-access attempt.

# Chart-generation study: collection blocked, generator review complete

Date: 2026-09-12. No top-100 map corpus has been downloaded or analyzed. No empirical frequency claims are made here.

## Data access and study scope

The requested most-played listing did not expose map rows in the available web response. The official search endpoint timed out; two mirror API requests returned HTTP 403. The official API documents OAuth authentication. Public data snapshots exist, but a top-player performance snapshot is not the same as a list of the most-played charts.

A beatmapset is a collection of difficulties, not one chart. A rigorous top-100-chart study needs individual native mania difficulty IDs, per-chart play counts, the snapshot date, key count and ranked status. The game uses four lanes, so native 4K results must be analyzed separately from 7K and other key counts. Popularity is a sampling criterion, not proof of good mapping; difficulty and mapper concentration should be reported too.

## Verified generator limitations

Review of `importer/charting.py`, not findings from the requested corpus:

1. `generate_charts` appends exactly one lane at each selected onset. It cannot represent simultaneous chords or jumpstreams, even if the music has simultaneous attacks.
2. Difficulty thinning greedily selects onset salience under a minimum gap. It does not select complete musical phrases or preserve a phrase's accent structure as a unit.
3. `phrase_patterns` repairs long same-lane runs, and `reuse_riffs` matches fixed 4/8/16-event windows. These are useful heuristics, but they do not demonstrate that the chart follows recurring audio phrases consistently when onset detection adds or misses notes.
4. Adding visual pattern variety cannot repair inaccurate audio onsets or inconsistent voice selection. Audio alignment and lane arrangement need separate evaluation.

## Source-supported mapping principles

osu!'s official mania ranking criteria call for correspondence between notes and musical sounds, predictable rhythms, appropriate difficulty spikes and restrained patterns on easier levels. They distinguish chords, streams, rolls, trills, anchors and jacks. These are mapping guidelines, not measured top-100 frequencies.

Proposed generation work, pending corpus measurement:

- Preserve a stable instrument/voice and detected musical phrase boundaries before assigning lanes.
- Reuse rhythm plus lane templates for verified returning phrases; tolerate small detection differences.
- Add chords only where multiple musical attacks support them; never manufacture them just to meet a percentage.
- Make easier difficulties simplify whole rhythmic gestures and retain strong accents.
- Use speed-aware limits on repeated fingers and uncomfortable hold transitions. Keep intentional repetition when the sound supports it.
- Retain the game's two-active-hold limit and existing early-release scoring behavior.

## Analyzer prepared

`python scripts/analyze_mania_patterns.py PATH_TO_MAPS --output analysis.json`

Reads `.osu` and `.osz` files without extracting audio. Excludes non-native-mania and non-4K files, deduplicates exact files, and records provenance. Measures chord sizes, lane transitions, hold proportions/concurrency, same-lane and cross-hand pairs, heuristic trill/jack/roll windows, and exact repeated four-beat note bins. Reports per-map statistics and map-weighted aggregates. Pattern counters overlap; they are not unique phrase counts. The analyzer does not label an arbitrary folder as the top 100, and cannot infer musical riffs without audio.

Next required input: the maps to analyze plus a dated play-count/ID list if the study must substantiate the exact top-100 claim. A user-supplied sample can still support a useful study if clearly labeled as a sample.

Sources:
- https://osu.ppy.sh/beatmapsets?m=3&sort=plays_desc
- https://osu.ppy.sh/docs/index.html
- https://data.ppy.sh/
- https://osu.ppy.sh/wiki/en/Ranking_criteria/osu!mania
