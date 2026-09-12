"""Deterministic, stem-specific onset charts. No random/fabricated beat grids."""
from __future__ import annotations
import math
import bisect
import heapq
import hashlib
import wave
from pathlib import Path
from arrangement import phrase_onsets, flowing_lanes, add_supported_chords
import numpy as np
from scipy.ndimage import median_filter
from scipy.signal import find_peaks, resample_poly

DIFFICULTIES = {"Easy": (0.48, 70), "Normal": (0.30, 48), "Hard": (0.19, 27), "Expert": (0.115, 0), "Master": (0.085, 0), "Insane": (0.055, 0)}

def read_wav(path: Path):
    with wave.open(str(path), 'rb') as w:
        if w.getsampwidth() != 2:
            raise ValueError('Analysis expects PCM 16-bit WAV')
        rate = w.getframerate()
        channels = w.getnchannels()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(np.float32) / 32768
    x = x.reshape(-1, channels).mean(axis=1)
    if rate != 22050:
        g = math.gcd(rate, 22050)
        x = resample_poly(x, 22050 // g, rate // g).astype(np.float32)
    return x, 22050

def generate_charts(path: Path, allow_holds: bool = True, instrument: str = "melody"):
    x, sr = read_wav(path)
    n, hop = 1024, 220
    if len(x) < n or np.max(np.abs(x)) < 0.001:
        return {d: [] for d in DIFFICULTIES}
    # Stream FFT blocks to keep long tracks within bounded analysis memory.
    padded = np.pad(x, (n // 2, n // 2))
    frame_count = 1 + (len(padded) - n) // hop
    envelope = np.zeros(frame_count, np.float32)
    pitches = np.zeros(frame_count, np.int32)
    voice_bins = np.zeros((frame_count, 6), np.int32)
    voice_weights = np.zeros((frame_count, 6), np.float32)
    energies = np.zeros(frame_count, np.float32)
    bands = np.zeros((frame_count, 4), np.float32)
    previous = np.zeros(n // 2 + 1)
    window = np.hanning(n)
    frequencies = np.fft.rfftfreq(n, 1 / sr)
    band_masks = [(frequencies >= lo) & (frequencies < hi) for lo, hi in [(40, 160), (160, 1000), (1000, 5000), (5000, 12000)]]
    for start in range(0, frame_count, 512):
        ids = np.arange(start, min(start + 512, frame_count))
        frames = padded[ids[:, None] * hop + np.arange(n)]
        spec = np.abs(np.fft.rfft(frames * window, axis=1))
        log = np.log1p(spec * 10)
        delta = np.diff(np.vstack([previous, log]), axis=0)
        positive_flux = np.maximum(delta, 0)
        envelope[ids] = positive_flux.mean(axis=1)
        for band, mask in enumerate(band_masks):
            bands[ids, band] = positive_flux[:, mask].sum(axis=1) / math.sqrt(max(1, int(mask.sum())))
        previous = log[-1]
        energies[ids] = np.sqrt(np.mean(frames * frames, axis=1))
        spec[:, frequencies < 45] = 0
        # Keep several tonal candidates rather than switching to whichever
        # harmonic happens to be loudest in a single FFT window.
        tonal = spec.copy()
        tonal[:, 1:-1] *= (spec[:, 1:-1] >= spec[:, :-2]) & (spec[:, 1:-1] >= spec[:, 2:])
        tonal[:, frequencies > (1600 if instrument.lower() == 'bass' else 3000)] = 0
        peaks = np.argpartition(tonal, -6, axis=1)[:, -6:]
        amplitude = np.take_along_axis(tonal, peaks, axis=1)
        harmonic = amplitude.copy()
        for overtone, weight in [(2, .8), (3, .5), (4, .25)]:
            bins = np.minimum(peaks * overtone, spec.shape[1] - 1)
            harmonic += weight * np.take_along_axis(spec, bins, axis=1)
        harmonic *= amplitude >= np.max(amplitude, axis=1, keepdims=True) * .08
        voice_bins[ids] = peaks
        voice_weights[ids] = harmonic
        pitches[ids] = np.argmax(spec, axis=1)
    if instrument.lower() != 'drums':
        pitches = consistent_voice(voice_bins, voice_weights, energies, frequencies, pitches)
    # Remove slowly changing timbre/noise while retaining distinct attacks.
    envelope = np.maximum(envelope - median_filter(envelope, size=31) * 0.65, 0)
    positive = envelope[envelope > 0.00001]
    if not len(positive):
        return {d: [] for d in DIFFICULTIES}
    candidates, _ = find_peaks(envelope, distance=4, prominence=max(float(np.median(positive)) * .8, float(np.max(envelope)) * .03, .0005))
    candidates = [int(i) for i in candidates if energies[i] > max(.0015, float(np.max(energies)) * .025)]
    # Reject release-edge spectral changes: a falling envelope is not a new attack.
    candidates = [i for i in candidates if np.max(energies[i:min(frame_count, i + 4)]) >= .75 * np.max(energies[max(0, i - 3):i + 1])]
    # Vibrato and release edges can have spectral flux without a fresh attack.
    # Require an energy rise or a material melodic change, not flux alone.
    def fresh_attack(i):
        before = energies[max(0, i - 5):max(1, i - 1)]
        after = energies[i:min(frame_count, i + 4)]
        rise = float(np.max(after)) >= max(.0015, float(np.mean(before)) * 1.08)
        pre_pitch = float(np.median(pitches[max(0, i - 5):max(1, i - 1)]))
        post_pitch = float(np.median(pitches[i:min(frame_count, i + 6)]))
        melodic_change = abs(post_pitch - pre_pitch) > max(2, pre_pitch * .12)
        return rise or (instrument.lower() != 'drums' and melodic_change)
    candidates = [i for i in candidates if fresh_attack(i)]
    lanes = {}
    if candidates:
        if instrument.lower() == 'drums':
            scale = np.maximum(np.percentile(bands[candidates], 90, axis=0), .001)
            for i in candidates:
                lanes[i] = int(np.argmax(bands[i] / scale))
        else:
            # Map low-to-high pitches left-to-right. Repeated pitches stay put.
            midi = np.array([69 + 12 * math.log2(max(45., frequencies[int(np.median(pitches[i:min(frame_count, i + 6)]))]) / 440.) for i in candidates])
            low, high = np.percentile(midi, [10, 90])
            for i, pitch in zip(candidates, midi):
                lanes[i] = 1 if high - low < 1 else int(np.clip(round(3 * (pitch - low) / (high - low)), 0, 3))
    scores = rhythmic_salience(envelope, candidates, hop / sr)
    # Preserve song-wide dynamics instead of promoting every quiet local peak.
    smooth_energy = np.convolve(energies, np.ones(min(len(energies), 101)) / min(len(energies), 101), mode="same")
    intensity = np.clip(smooth_energy / max(float(np.percentile(smooth_energy, 85)), .002), 0, 1)
    scores = scores * (.2 + .8 * intensity)
    lanes = phrase_patterns(candidates, lanes, scores, hop / sr, instrument)
    result = {}
    pool = candidates
    # All levels draw from the same measured onsets; harder levels add density.
    for difficulty, (gap, percentile) in reversed(list(DIFFICULTIES.items())):
        chosen = phrase_onsets(pool, scores, gap, percentile, hop / sr, candidates, intensity)
        pool = chosen
        # Thinning can accidentally select the same motif step repeatedly.
        # Re-pattern those long runs at this difficulty before building holds.
        chosen_lanes = phrase_patterns(chosen, lanes, scores, hop / sr, instrument)
        chosen_lanes = flowing_lanes(chosen, chosen_lanes, hop / sr)
        chosen_lanes = reuse_riffs(chosen, chosen_lanes, pitches, hop / sr, frequencies, instrument)
        notes = []
        for i in sorted(chosen):
            # Centered FFT windows see attacks slightly early. Compensate half a hop.
            t = round(min(len(x) / sr, (i + .5) * hop / sr), 4)
            notes.append({'t': t, 'lane': chosen_lanes[i], 'end': t})
        add_supported_chords(notes, sorted(chosen), scores, bands, voice_bins, voice_weights,
                             frequencies, instrument, difficulty, hop / sr)
        if allow_holds:
            add_holds(notes, energies, hop / sr, len(x) / sr, difficulty)
            sparse_sustains(notes, pitches, candidates, hop / sr)
            limit_simultaneous_holds(notes, 2)
        result[difficulty] = notes
    return {d: result[d] for d in DIFFICULTIES}


def add_holds(notes, energies, frame_seconds, duration, difficulty):
    """Extend sustained onsets, without overlapping the next note in a lane.

    Require 80ms of quiet to detect a release; a breath/dip must not create
    jittering tails. Gaps between tails and following same-lane notes give
    players time to release and press again. Short/percussive events stay taps.
    """
    minimum = 0.28 if difficulty == 'Easy' else 0.16
    release_frames = max(1, round(0.08 / frame_seconds))
    next_in_lane = [duration + 0.10] * 4
    for note in reversed(notes):
        head = note['t']
        limit = min(duration, next_in_lane[note['lane']] - 0.10)
        next_in_lane[note['lane']] = head
        if limit - head < minimum:
            continue
        start = max(0, min(len(energies) - 1, round(head / frame_seconds)))
        attack_end = min(len(energies), start + max(2, round(0.08 / frame_seconds)))
        level = float(np.max(energies[start:attack_end]))
        threshold = max(0.002, level * 0.28)
        quiet, tail = 0, limit
        for frame in range(start, min(len(energies), int(limit / frame_seconds) + 1)):
            quiet = quiet + 1 if energies[frame] < threshold else 0
            if quiet >= release_frames:
                tail = max(head, (frame - quiet + 1) * frame_seconds)
                break
        if tail - head >= minimum:
            note['end'] = round(min(tail, limit), 4)


def limit_simultaneous_holds(notes, maximum=2):
    """Keep note heads intact; excess sustained notes become taps.

    Hold intervals are [head, tail), so a release at a new head frees a slot.
    Each difficulty/player chart is constrained independently.
    """
    active = []
    for note in sorted(notes, key=lambda n: (n['t'], n['lane'])):
        while active and active[0] <= note['t']:
            heapq.heappop(active)
        if note['end'] <= note['t']:
            continue
        if len(active) >= maximum:
            note['end'] = note['t']
        else:
            heapq.heappush(active, note['end'])


def rhythmic_salience(envelope, candidates, frame_seconds):
    """Rank measured attacks using local pulse support; never invent/snap notes.

    Re-estimate the pulse in eight-second neighborhoods so tempo changes can
    follow the recording. A supported attack receives a modest bonus, while
    offbeat accents remain eligible. Local normalization handles quiet sections.
    """
    scores = envelope.astype(float).copy()
    radius = max(1, round(4 / frame_seconds))
    tolerance = max(1, round(.035 / frame_seconds))
    block = max(1, round(2 / frame_seconds))
    cached = {}
    for i in candidates:
        key = i // block
        if key not in cached:
            center = key * block + block // 2
            lo, hi = max(0, center - radius), min(len(envelope), center + radius)
            region = envelope[lo:hi]
            lags = range(round(.3 / frame_seconds), round(.8 / frame_seconds) + 1)
            correlations = [(float(np.dot(region[:-lag], region[lag:])) / max(1, len(region) - lag), lag)
                            for lag in lags if lag < len(region)]
            pulse = max(correlations)[1] if correlations else 0
            level = max(float(np.percentile(region[region > 0], 90)), .0001) if np.any(region > 0) else 1.
            cached[key] = pulse, level
        pulse, level = cached[key]
        support = []
        for target in (i - pulse, i + pulse):
            if pulse and 0 <= target < len(envelope):
                support.append(float(np.max(envelope[max(0, target - tolerance):min(len(envelope), target + tolerance + 1)])) / level)
        scores[i] = float(envelope[i]) / level * (1 + .45 * min(1., max(support, default=0.)))
    return scores


def sparse_sustains(notes, pitches, attacks, frame_seconds):
    """Retain audible sustains without demanding a perfectly stationary pitch.

    Energy/release and same-lane overlap were checked by add_holds. Other-lane
    attacks no longer truncate sustained tones. Allow vibrato and gentle slides.
    Prefer short sustains around 450ms, cap continuous tails at 1.6 seconds,
    and distribute a modest hold budget across the song. The attacks argument remains for compatibility with previous callers.
    """
    eligible = []
    for note in notes:
        head, tail = note['t'], min(note['end'], note['t'] + 1.6)
        a, b = round((head + .06) / frame_seconds), round(tail / frame_seconds)
        pitch = pitches[a:b]
        stable = len(pitch) > 0 and np.percentile(pitch, 90) - np.percentile(pitch, 10) <= max(4, float(np.median(pitch)) * .45)
        if tail - head >= .16 and stable:
            eligible.append((tail - head, note, round(tail, 4)))
        note['end'] = head
    budget = max(1, math.ceil(len(notes) * .18)) if notes else 0
    # Round-robin through eight-second regions to spread holds across phrases.
    regions = {}
    for item in eligible:
        regions.setdefault(int(item[1]['t'] // 8), []).append(item)
    for region in regions.values():
        region.sort(key=lambda row: (abs(row[0] - .45), row[1]['t']))
    heads = []
    while regions and len(heads) < budget:
        for key in list(regions):
            _, note, tail = regions[key].pop(0)
            if all(abs(note['t'] - h) >= .8 for h in heads):
                note['end'] = tail
                heads.append(note['t'])
            if not regions[key]:
                del regions[key]
            if len(heads) >= budget:
                break


def phrase_patterns(candidates, lanes, scores, frame_seconds, instrument):
    """Turn 4+ consecutive same-lane attacks into deterministic phrase motifs.

    Preserve measured times and short repeated-note gestures. Rhythm and accent
    fingerprints select a repeating motif per phrase; instrument families use
    different vocabularies. Apply to the common attacks and again after
    difficulty thinning so sparse charts do not collapse onto one motif step.
    """
    mapped = dict(lanes)
    vocabularies = {
        'drums': [(0, 1), (0, 2, 0, 1), (0, 1, 2, 1), (0, 2)],
        'bass': [(0, 1, 2, 1), (0, 1, 0, 2), (0, 2, 1, 2), (0, 1)],
        'vocals': [(0, 1, 2, 3, 2, 1), (0, 1, 2, 1), (0, 2, 3, 2), (0, 1, 3, 1)],
        'other': [(0, 1, 2, 3), (0, 2, 1, 3), (0, 1, 3, 2), (0, 3, 1, 2)],
    }
    part = instrument.lower()
    vocabulary = vocabularies.get(part, vocabularies['other'])
    start = 0
    while start < len(candidates):
        end = start + 1
        while end < len(candidates) and lanes[candidates[end]] == lanes[candidates[start]] and (candidates[end] - candidates[end-1]) * frame_seconds <= 1.2:
            end += 1
        run = candidates[start:end]
        # Natural gaps split phrases; 16 attacks cap very long unbroken streams.
        if len(run) >= 4:
            typical = float(np.median(np.diff(run)))
            boundaries = [0]
            for j in range(1, len(run)):
                if run[j] - run[j-1] > typical * 2.2 or j - boundaries[-1] >= 16:
                    boundaries.append(j)
            boundaries.append(len(run))
            for left, right in zip(boundaries, boundaries[1:]):
                phrase = run[left:right]
                if len(phrase) < 4:
                    continue
                gaps = np.diff(phrase)
                unit = max(1., float(np.median(gaps)))
                rhythm = tuple(int(round(g / unit * 4)) for g in gaps)
                peak = max(.001, max(float(scores[i]) for i in phrase))
                accents = tuple(int(round(float(scores[i]) / peak * 3)) for i in phrase)
                # Loudness changes in a repeated riff must not choose a new motif.
                fingerprint = repr((part, rhythm)).encode('utf-8')
                digest = hashlib.sha256(fingerprint).digest()
                motif = vocabulary[int.from_bytes(digest[:4], 'little') % len(vocabulary)]
                origin = lanes[phrase[0]]
                direction = -1 if origin >= 2 else 1
                # Avoid joining the end of a new motif onto a neighboring
                # short run and accidentally making another long column.
                previous_lane = mapped[candidates[start + left - 1]] if start + left > 0 else None
                next_lane = lanes[candidates[start + right]] if start + right < len(candidates) else None
                pattern = []
                for shift in range(4):
                    pattern = [(origin + shift + direction * motif[j % len(motif)]) % 4 for j in range(len(phrase))]
                    if pattern[0] != previous_lane and pattern[-1] != next_lane:
                        break
                for i, lane in zip(phrase, pattern):
                    mapped[i] = lane
        start = end
    return mapped


def consistent_voice(candidates, weights, energies, frequencies, fallback):
    """Prefer persistent tonal sources and fundamental evidence within a stem.

    A broad whole-track register prior and a gentle continuity preference reduce
    voice/harmonic hopping. New energy attacks may still make real melodic leaps.
    No other instrument stem is substituted when this stem gets quiet.
    """
    strongest = np.maximum(weights.max(axis=1, keepdims=True), 1e-8)
    normalized = weights / strongest
    audible = energies > max(.0015, float(energies.max()) * .025)
    profile = np.bincount(candidates[audible].ravel(), weights=normalized[audible].ravel(), minlength=len(frequencies))
    profile = np.convolve(profile, [.2,.6,.2], mode='same')
    profile /= max(1., float(profile.max()))
    result = fallback.copy()
    previous = 0
    for i in range(len(candidates)):
        if not audible[i]:
            previous = 0
            continue
        bins = candidates[i]
        strength = normalized[i] * (.7 + .3 * profile[bins])
        # Fundamentals have a modest advantage over higher partials.
        strength /= np.maximum(1., frequencies[bins] / 220.) ** .12
        attack = i == 0 or energies[i] > energies[max(0,i-3)] * 1.12
        if previous > 0 and not attack:
            distance = np.abs(np.log2(np.maximum(1,bins) / previous))
            strength *= .78 + .22 * np.exp(-distance * 3)
        winner = int(bins[int(np.argmax(strength))])
        if winner > 0 and float(np.max(strength)) > 0:
            result[i] = winner
            previous = winner
    return result


def reuse_riffs(attacks, lanes, pitches, frame_seconds, frequencies, instrument):
    """Reuse the first arrangement of recurring 4/8/16-note musical phrases.

    Fingerprints use quantized rhythm and relative melodic intervals, not volume,
    absolute song position, or a fresh random seed. Templates are per instrument
    and per difficulty. Only existing measured note heads are rearranged.
    """
    result = dict(lanes)
    if len(attacks) < 4:
        return result
    midi = [round(69 + 12*math.log2(max(45., frequencies[int(np.median(pitches[i:i+6]))]) / 440.)) for i in attacks]
    templates = {}
    i = 0
    while i < len(attacks):
        matched = False
        for length in (16,8,4):
            if i + length > len(attacks):
                continue
            times = np.array(attacks[i:i+length]) * frame_seconds
            gaps = np.diff(times)
            typical = max(.04, float(np.median(gaps)))
            if np.max(gaps) > max(1.2, typical * 2.5):
                continue
            rhythm = tuple(int(round(g / typical * 4)) for g in gaps)
            contour = tuple(int(round((midi[j+1]-midi[j]) / 2)) for j in range(i,i+length-1))
            key = (instrument.lower(), length, rhythm, contour)
            if key in templates:
                for at,lane in zip(attacks[i:i+length],templates[key]):
                    result[at] = lane
                i += length
                matched = True
                break
            templates[key] = tuple(result[at] for at in attacks[i:i+length])
        if not matched:
            i += 1
    return result
