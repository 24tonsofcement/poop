"""Measure-length metadata for hold scoring; generated songs assume 4/4."""
import math
import numpy as np
from charting import read_wav

DEFAULT_TIMING = [{'t': 0.0, 'beat_length': .5, 'meter': 4}]

def parse_timing_points(lines):
    points = {}
    for line in lines:
        fields = line.split(',')
        if len(fields) < 3:
            continue
        try:
            at, beat = float(fields[0]) / 1000, float(fields[1]) / 1000
            meter = int(fields[2])
            inherited = len(fields) >= 7 and fields[6].strip() == '0'
            if inherited or not math.isfinite(at) or not math.isfinite(beat) or beat <= 0 or not 1 <= meter <= 32:
                continue
            points[at] = {'t': at, 'beat_length': beat, 'meter': meter}
        except ValueError:
            continue
    return [points[t] for t in sorted(points)] or [dict(p) for p in DEFAULT_TIMING]


def estimate_timing(path):
    """Estimate a local pulse from full-mix energy attacks, not chart density.

    Eight-second sections use overlapping 12-second analysis windows. Choose
    the strongest 60-200 BPM recurrence. Ambiguous/silent audio uses 120 BPM.
    This estimates pulse only; automatic time-signature inference is not claimed.
    """
    x, rate = read_wav(path)
    hop = round(rate * .01)
    length = len(x) // hop
    if length < 100:
        return [dict(p) for p in DEFAULT_TIMING]
    rms = np.sqrt(np.mean(x[:length*hop].reshape(length,hop)**2,axis=1))
    attacks = np.convolve(np.maximum(np.diff(rms,prepend=0),0), [.25,.5,.25], mode="same")
    step = hop / rate
    points = []
    for at in range(0,length,max(1,round(8/step))):
        center = at + round(4/step)
        window = attacks[max(0,center-round(6/step)):min(length,center+round(6/step))]
        correlations = []
        best, lag = 0., round(.5/step)
        for candidate in range(round(.3/step),round(1./step)+1):
            if candidate >= len(window):
                continue
            a,b=window[:-candidate],window[candidate:]
            norm = float(np.linalg.norm(a)*np.linalg.norm(b))
            correlation = float(np.dot(a,b))/norm if norm > 1e-10 else 0.
            correlations.append((correlation,candidate))
        if correlations:
            best = max(c for c,_ in correlations)
            # Prefer the faster of similarly supported pulse/double-pulse lags.
            lag = min(candidate for c,candidate in correlations if c >= best * .92)
        beat = round(lag*step,6) if best >= .15 else .5
        if not points or abs(beat-points[-1]['beat_length']) / points[-1]['beat_length'] > .06:
            points.append({'t':round(at*step,4),'beat_length':beat,'meter':4})
    return points
