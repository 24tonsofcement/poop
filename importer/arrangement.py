"""Conservative musical arrangement: no invented note times or random lanes.

Policies informed by the supplied 169-chart 4K sample, not trained on/copied
from its charts. See research/mania-sample-study.md for measurements and limits.
"""
import bisect
import math
import numpy as np


def phrase_onsets(pool, scores, gap, percentile, step, reference=None, intensity=None):
    """Simplify recurring short rhythmic gestures consistently at each level.

    A natural rest splits a gesture; eight attacks cap dense passages. This is
    onset-phrase grouping, not a claim to detect semantic audio riffs. All lower
    difficulties remain subsets of the previous level's measured onset pool.
    """
    if not pool: return []
    typical = float(np.median(np.diff(pool))) * step if len(pool) > 1 else .5
    cutoff = float(np.percentile([scores[i] for i in (reference if reference is not None else pool)], percentile))
    groups, current = [], []
    for at in pool:
        if current and ((at - current[-1]) * step > max(.7, typical * 2.5) or len(current) == 8):
            groups.append(current); current = []
        current.append(at)
    if current: groups.append(current)
    chosen, templates = [], {}
    for group in groups:
        rhythm = tuple(round((b - a) * step / .02) for a, b in zip(group, group[1:]))
        level = float(np.mean([intensity[at] for at in group])) if intensity is not None else 1.0
        key = (len(group), rhythm, int(level * 4))
        local_gap = gap * (1.0 + .8 * (1.0 - level))
        mask = templates.get(key)
        if mask is None:
            eligible = [j for j, at in enumerate(group) if scores[at] >= cutoff]
            local = []
            for j in sorted(eligible, key=lambda j: (-float(scores[group[j]]) * (1.15 if j == 0 else 1.0), j)):
                if all(abs(group[j] - group[k]) * step >= local_gap for k in local): local.append(j)
            mask = tuple(sorted(local))
            templates[key] = mask
        for j in mask:
            at = group[j]
            if not chosen or (at - chosen[-1]) * step >= gap: chosen.append(at)
    return chosen


def flowing_lanes(attacks, desired, step):
    """Use a phrase-local four-lane DP to avoid fast accidental finger repeats.

    Slow repeated pitches remain in their lanes. Fast hand alternation is a
    soft preference, so melodic movement and readable rolls can still win.
    """
    result = dict(desired)
    groups, group = [], []
    for at in attacks:
        if group and ((at - group[-1]) * step > .6 or len(group) >= 64):
            groups.append(group); group = []
        group.append(at)
    if group: groups.append(group)
    for group in groups:
        costs = [2.0 * abs(lane - desired[group[0]]) for lane in range(4)]
        parents = []
        for previous, at in zip(group, group[1:]):
            interval = (at - previous) * step
            choices, updated = [], []
            for lane in range(4):
                alternatives = []
                for before in range(4):
                    repeat = (5.0 if interval < .16 else 2.8 if interval < .25 else 0.0) if lane == before else 0
                    same_hand = .5 if interval < .23 and (lane < 2) == (before < 2) else 0
                    alternatives.append(costs[before] + repeat + same_hand + abs(lane - desired[at]) * 2.0)
                best = min(range(4), key=lambda k: (alternatives[k], k))
                updated.append(alternatives[best]); choices.append(best)
            parents.append(choices); costs = updated
        lane = min(range(4), key=lambda k: (costs[k], k))
        for j in range(len(group) - 1, -1, -1):
            result[group[j]] = lane
            if j: lane = parents[j-1][lane]
    return result


def tone_count(bins, weights, frequencies):
    """Require two strong non-harmonic spectral peaks; harmonics aren't chords."""
    order = sorted(range(len(bins)), key=lambda j: -weights[j])
    if not order or weights[order[0]] <= 0: return 0
    selected = []
    for j in order:
        frequency = float(frequencies[int(bins[j])])
        if frequency < 90 or weights[j] < weights[order[0]] * .45: continue
        if any(abs(frequency - other) < 65 for other in selected): continue
        if any(abs(max(frequency, other) / min(frequency, other) - round(max(frequency, other) / min(frequency, other))) < .045 for other in selected): continue
        selected.append(frequency)
    return len(selected)


def independent_tones(bins, weights, frequencies):
    return tone_count(bins, weights, frequencies) >= 2


def add_supported_chords(notes, attacks, scores, bands, voice_bins, voice_weights, frequencies, instrument, difficulty, step):
    """Add evidence-supported chords at measured attacks, with rare wide accents.

    Budgets are ceilings, never targets. Bass/vocals stay single voice. Per-stem
    charts deliberately use fewer chords than the full-song reference maps.
    """
    part = instrument.lower()
    if part not in ('drums', 'other', 'keys', 'synth', 'piano') or not attacks: return
    budget = {'Easy': .06, 'Normal': .12, 'Hard': .20, 'Expert': .28, 'Master': .32, 'Insane': .36}[difficulty]
    scale = np.maximum(np.percentile(bands[attacks], 90, axis=0), .0001)
    groups = {}
    for note, at in zip(notes, attacks): groups.setdefault(int(note['t'] // 4), []).append((note, at))
    extras = []
    last_triple = last_quad = -100.
    triple_count = quad_count = 0
    for group in groups.values():
        limit = int(len(group) * budget)
        if not limit: continue
        cutoff = float(np.percentile([scores[at] for _, at in group], 60))
        previous = -100.
        for note, at in group:
            if limit <= 0: break
            if scores[at] < cutoff or note['t'] - previous < (.6 if difficulty in ('Easy', 'Normal') else .25): continue
            if part == 'drums':
                strong = [b for b in range(4) if bands[at, b] >= scale[b] * .6 and bands[at, b] >= np.max(bands[at]) * .25]
                supported = any(abs(a-b) >= 2 for a in strong for b in strong)
                voices = len(strong)
            else:
                voices = tone_count(voice_bins[at], voice_weights[at], frequencies)
                supported = voices >= 2
            if not supported: continue
            # A cross-hand double has a predictable placement and avoids adding
            # a rapid repeat immediately next to another head in that lane.
            choices = [(note['lane'] + 2) % 4, 3 - note['lane']]
            lane = next((lane for lane in choices if all(other['lane'] != lane or abs(other['t'] - note['t']) >= .15 for other in notes[max(0, bisect.bisect_left(attacks, at)-3):bisect.bisect_left(attacks, at)+4])), None)
            if lane is None: continue
            extras.append({'t': note['t'], 'end': note['t'], 'lane': lane})
            size = 2
            if difficulty in ('Hard', 'Expert', 'Master', 'Insane') and voices >= 3 and note['t'] - last_triple >= 3 and triple_count < int(len(attacks) * .06):
                size = 3
            if difficulty in ('Expert', 'Master', 'Insane') and voices >= 4 and note['t'] - last_quad >= 8 and quad_count < int(len(attacks) * .02):
                size = 4
            occupied = {note['lane'], lane}
            for extra_lane in range(4):
                if len(occupied) >= size: break
                if extra_lane in occupied: continue
                if any(n['lane'] == extra_lane and abs(n['t'] - note['t']) < .15 for n in notes): continue
                extras.append({'t': note['t'], 'end': note['t'], 'lane': extra_lane})
                occupied.add(extra_lane)
            if len(occupied) >= 3: last_triple = note['t']; triple_count += 1
            if len(occupied) == 4: last_quad = note['t']; quad_count += 1
            limit -= 1; previous = note['t']
    notes.extend(extras)
    notes.sort(key=lambda n: (n['t'], n['lane']))
