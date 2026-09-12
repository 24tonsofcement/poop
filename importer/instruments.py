"""Select audible parts from six-source separation; never invent instruments.

Presence is an energy/activity heuristic, not a semantic classifier. Residual
strings/synths/etc remain honestly labelled Other instruments.
"""
import numpy as np
from charting import read_wav

MODEL = 'htdemucs_6s'
SOURCES = ('vocals', 'drums', 'bass', 'guitar', 'piano', 'other')
LABELS = {name: name.title() for name in SOURCES}
LABELS['other'] = 'Other instruments'


def strength(path):
    audio, rate = read_wav(path)
    if not len(audio): return (0., 0.)
    block = max(1, round(rate * .1))
    levels = np.array([np.sqrt(np.mean(audio[i:i+block]**2)) for i in range(0, len(audio), block)])
    return float(np.sqrt(np.mean(levels**2))), float(np.percentile(levels, 95))


def select_sources(measurements, mix):
    present = [name for name in SOURCES if name in measurements
               and measurements[name][0] >= max(.0003, mix[0]*.015)
               and measurements[name][1] >= max(.001, mix[1]*.025)]
    required = [name for name in ('vocals', 'drums') if name in present]
    others = sorted((name for name in present if name not in required),
                    key=lambda name: (-(.7*measurements[name][0]+.3*measurements[name][1]), name))
    return required + others[:2]


def selected_paths(audio, folder):
    paths = {name: folder / (name+'.wav') for name in SOURCES}
    missing = [name for name, path in paths.items() if not path.exists()]
    if missing: raise RuntimeError('Stem separation did not produce: '+', '.join(missing))
    chosen = select_sources({name: strength(path) for name,path in paths.items()}, strength(audio))
    return {name: paths[name] for name in chosen}
