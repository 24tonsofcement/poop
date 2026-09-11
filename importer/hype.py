"""Conservative audio-based highlights, not semantic chorus recognition.

Two-second loudness/spectral windows identify energy lifts, repeated energetic
phrases and stem dominance. Store confidence so sensitivity can change in-game.
"""
from pathlib import Path
import numpy as np
from charting import read_wav

STEP = 2.0


def features(path):
    audio, rate = read_wav(Path(path))
    count = int(np.ceil(len(audio) / (rate * STEP)))
    energy = np.zeros(count)
    bands = np.zeros((count, 8))
    for i in range(count):
        block = audio[int(i * rate * STEP):int((i + 1) * rate * STEP)]
        if not len(block):
            continue
        energy[i] = np.sqrt(np.mean(block ** 2))
        # Sample short frames across each window; don't allocate a song-size FFT.
        spectra = []
        for start in range(0, max(1, len(block) - 1024), 4096):
            frame = block[start:start + 1024]
            if len(frame) == 1024:
                spectra.append(np.abs(np.fft.rfft(frame * np.hanning(1024))))
        if spectra:
            spectrum = np.mean(spectra, axis=0)
            frequencies = np.fft.rfftfreq(1024, 1 / rate)
            edges = [35, 80, 180, 400, 900, 2000, 4500, 8000, rate / 2 + 1]
            for j in range(8):
                bands[i, j] = np.sum(spectrum[(frequencies >= edges[j]) & (frequencies < edges[j + 1])])
    bands /= np.maximum(np.linalg.norm(bands, axis=1, keepdims=True), 1e-9)
    return energy, bands, len(audio) / rate


def sections(scores, kinds, duration, minimum=4.0):
    result = []
    start = None
    for i in range(len(scores) + 1):
        enabled = i < len(scores) and scores[i] >= .5
        if enabled and start is None:
            start = i
        if not enabled and start is not None:
            end = min(i * STEP, duration)
            if end - start * STEP >= minimum:
                peak = start + int(np.argmax(scores[start:i]))
                result.append(dict(start=start * STEP, end=round(end, 3),
                                   confidence=round(float(np.mean(scores[start:i])), 3),
                                   kind=kinds[peak]))
            start = None
    return result


def detect_arrays(energy, bands, duration, stems=None):
    energy = np.asarray(energy, dtype=float)
    n = len(energy)
    output = {'schema': 1, 'global': [], 'instruments': {}}
    if n < 6 or np.max(energy) < .003:
        return output
    baseline = max(float(np.median(energy)), .001)
    spread = max(float(np.percentile(energy, 90) - np.percentile(energy, 20)), baseline * .4)
    lift = np.clip((energy - np.percentile(energy, 35)) / spread, 0, 1)
    scores = np.zeros(n)
    kinds = ['hype'] * n
    for i in range(n):
        # Require a substantial lift: constant loudness is not a whole-song bonus.
        if lift[i] < .5 or energy[i] < baseline * 1.12:
            continue
        before = np.mean(energy[max(0, i - 4):i]) if i else energy[i]
        drop = energy[i] > max(before * 1.55, .008)
        repeated = False
        if i + 3 <= n:
            phrase = bands[i:i + 3]
            for j in range(0, n - 2):
                if abs(j - i) < 6:
                    continue
                similarity = np.mean(np.sum(phrase * bands[j:j + 3], axis=1))
                contour = np.linalg.norm(energy[i:i+3] / max(energy[i:i+3].mean(), 1e-9)
                                         - energy[j:j+3] / max(energy[j:j+3].mean(), 1e-9))
                if similarity > .94 and contour < .35 and np.mean(energy[j:j+3]) > baseline * 1.1:
                    repeated = True
                    break
        scores[i] = min(.98, .48 + .20 * lift[i] + .16 * drop + .12 * repeated)
        kinds[i] = 'drop' if drop else 'chorus' if repeated else 'hype'
    output['global'] = sections(scores, kinds, duration)
    if stems:
        names = list(stems)
        values = np.array([np.pad(np.asarray(stems[k])[:n], (0, max(0, n-len(stems[k])))) for k in names])
        total = np.maximum(values.sum(axis=0), 1e-8)
        for index, name in enumerate(names):
            part = values[index]
            share = part / total
            normal = max(float(np.median(share)), .08)
            # Dominance must rise above this instrument's normal mix position.
            mask = ((share > .42) & (share > normal * 1.6) &
                    (part > max(float(np.median(part)) * 1.3, .004)))
            solo_scores = np.where(mask, np.minimum(.98, .65 + .3 * share), 0)
            output['instruments'][name] = sections(solo_scores, ['solo'] * n, duration)
    return output


def detect_hype(audio, stem_paths=None):
    energy, bands, duration = features(audio)
    stems = {name: features(path)[0] for name, path in (stem_paths or {}).items()}
    return detect_arrays(energy, bands, duration, stems)
