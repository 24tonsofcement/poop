"""Analyze local .osu/.osz files without audio or extracting archives.

This measures a supplied corpus; it does NOT certify a most-played ranking.
Usage: python scripts/analyze_mania_patterns.py MAP_DIRECTORY --output report.json
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import statistics
import zipfile

MAX_MAP = 8 * 1024 * 1024


def parse(text):
    section = ''
    metadata, notes, timing = {}, [], []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('//'): continue
        if line.startswith('['):
            section = line.strip('[]'); continue
        if section in ('General', 'Difficulty', 'Metadata') and ':' in line:
            key, value = line.split(':', 1); metadata[key] = value.strip()
        elif section == 'TimingPoints':
            fields = line.split(',')
            if len(fields) >= 2 and float(fields[1]) > 0 and (len(fields) < 7 or fields[6] == '1'):
                timing.append((float(fields[0]) / 1000, float(fields[1]) / 1000))
        elif section == 'HitObjects':
            fields = line.split(',')
            if len(fields) < 5: raise ValueError('Malformed hit object')
            at, flags = int(fields[2]), int(fields[3])
            end = int(fields[5].split(':')[0]) if flags & 128 else at
            if end < at: raise ValueError('Hold ends before its head')
            notes.append((at / 1000, int(fields[0]), end / 1000))
    if metadata.get('Mode') != '3': raise ValueError('Not native mania')
    keys = int(float(metadata.get('CircleSize', '0')))
    if keys != 4: raise ValueError('Not 4-key; excluded rather than mixed into 4K results')
    if not notes or not timing: raise ValueError('Missing notes or tempo')
    notes = sorted((at, min(keys - 1, max(0, x * keys // 512)), end) for at, x, end in notes)
    timing.sort()
    return metadata, notes, timing


def beat_clock(timing):
    origins = [0.0]
    for i in range(1, len(timing)):
        origins.append(origins[-1] + (timing[i][0] - timing[i - 1][0]) / timing[i - 1][1])
    def at(seconds):
        index = 0
        for i, (start, _) in enumerate(timing):
            if start > seconds: break
            index = i
        return origins[index] + (seconds - timing[index][0]) / timing[index][1]
    return at


def measure(metadata, notes, timing):
    beat = beat_clock(timing)
    rows = defaultdict(list)
    lanes = Counter()
    active, maximum_holds, held = [], 0, 0
    for at, lane, end in notes:
        rows[at].append(lane); lanes[lane] += 1
        active = [finish for finish in active if finish > at]
        if end > at:
            held += 1; active.append(end); maximum_holds = max(maximum_holds, len(active))
    events = [(at, tuple(sorted(columns))) for at, columns in sorted(rows.items())]
    chords = Counter(len(columns) for _, columns in events)
    patterns = Counter()
    windows = Counter()
    transitions = [[0] * 4 for _ in range(4)]
    for (ta, ca), (tb, cb) in zip(events, events[1:]):
        if beat(tb) - beat(ta) > 1: continue
        if len(ca) == len(cb) == 1:
            windows['single_pairs'] += 1
            transitions[ca[0]][cb[0]] += 1
            patterns['same_lane_pairs'] += ca == cb
            patterns['cross_hand_pairs'] += (ca[0] < 2) != (cb[0] < 2)
    for i in range(len(events) - 3):
        group = events[i:i + 4]
        gaps = [beat(group[j+1][0]) - beat(group[j][0]) for j in range(3)]
        if not all(0 < gap <= 1 for gap in gaps): continue
        windows['four_rows'] += 1
        if not all(len(columns) == 1 for _, columns in group): continue
        windows['four_single_rows'] += 1
        sequence = tuple(columns[0] for _, columns in group)
        # Heuristic classifiers; overlapping windows are not unique phrases.
        uniform = max(gaps) - min(gaps) <= .08
        patterns['four_note_jacks'] += len(set(sequence)) == 1 and uniform
        patterns['four_note_trills'] += sequence[0] == sequence[2] and sequence[1] == sequence[3] and sequence[0] != sequence[1] and uniform
        patterns['four_lane_rolls'] += sequence in ((0, 1, 2, 3), (3, 2, 1, 0)) and uniform
    # Four-beat bins are a fixed comparison unit, not inferred audio riffs.
    bars = defaultdict(list)
    for at, lane, end in notes:
        position = beat(at)
        bar = int(position // 4)
        bars[bar].append((round(position - bar * 4, 2), lane, round(beat(end) - position, 2)))
    fingerprints = Counter(tuple(value) for value in bars.values())
    repeated = sum(count for count in fingerprints.values() if count > 1)
    duration = max(end for _, _, end in notes) - notes[0][0]
    return dict(beatmap_id=metadata.get('BeatmapID'), title=metadata.get('Title'), artist=metadata.get('Artist'),
                mapper=metadata.get('Creator'), difficulty=metadata.get('Version'), notes=len(notes), onset_rows=len(events),
                hold_fraction=held / len(notes), max_active_holds=maximum_holds,
                chord_row_fraction=sum(count for size, count in chords.items() if size > 1) / len(events),
                chord_sizes=dict(chords), notes_per_active_second=len(notes) / max(1, duration),
                lane_shares=[lanes[i] / len(notes) for i in range(4)], transitions=transitions,
                patterns=dict(patterns), window_denominators=dict(windows),
                repeated_four_beat_bin_fraction=repeated / max(1, len(bars)))


def inputs(root):
    for path in sorted(root.rglob('*')):
        if path.suffix.lower() == '.osu':
            if path.stat().st_size <= MAX_MAP: yield str(path), path.read_bytes()
        elif path.suffix.lower() == '.osz':
            try:
                with zipfile.ZipFile(path) as archive:
                    for member in archive.infolist():
                        if member.filename.lower().endswith('.osu') and member.file_size <= MAX_MAP:
                            yield str(path) + '::' + member.filename, archive.read(member)
            except (OSError, zipfile.BadZipFile) as error:
                yield str(path), error


def analyze(root):
    maps, excluded, seen = [], [], set()
    for name, raw in inputs(root):
        try:
            if isinstance(raw, Exception): raise raw
            digest = hashlib.sha256(raw).hexdigest()
            if digest in seen: continue
            seen.add(digest)
            result = measure(*parse(raw.decode('utf-8-sig')))
            result.update(file=name, sha256=digest)
            maps.append(result)
        except (ValueError, OSError, IndexError, UnicodeError) as error:
            excluded.append({'file': name, 'reason': str(error)})
    fields = ['hold_fraction', 'chord_row_fraction', 'notes_per_active_second', 'repeated_four_beat_bin_fraction']
    summary = {field: {'map_weighted_mean': statistics.mean(m[field] for m in maps), 'median': statistics.median(m[field] for m in maps)} for field in fields} if maps else {}
    return dict(scope='Supplied native 4K corpus; play-count ranking NOT independently verified',
                map_count=len(maps), summary=summary, maps=maps, excluded=excluded,
                limitations=['No audio comparison: repeated note bins are not proof of repeated musical riffs.',
                            'Pattern counters use overlapping windows; report their denominators.',
                            'Popularity, star rating and mapper bias require separate metadata and stratification.'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(analyze(args.directory), indent=2), encoding='utf-8')
