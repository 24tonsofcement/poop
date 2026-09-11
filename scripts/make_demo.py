"""Create an original 48-second, four-part electronic practice song."""
import json
import sys
from pathlib import Path
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]

def main():
    out = ROOT / 'game' / 'demo'
    out.mkdir(parents=True, exist_ok=True)
    sr, duration, beat = 44100, 50, 0.5
    mix = np.zeros(sr * duration, dtype=np.float32)
    rng = np.random.default_rng(8024)
    events = {p: [] for p in ['Drums', 'Bass', 'Synth', 'Keys']}
    def add(part, at, lane, sound, hold=0):
        pos = round(at * sr)
        count = min(len(sound), len(mix) - pos)
        mix[pos:pos + count] += sound[:count]
        events[part].append({'t': round(at, 4), 'lane': lane, 'end': round(at + hold, 4)})
    def tone(freq, length, gain):
        t = np.arange(int(length * sr)) / sr
        env = np.minimum(t / .009, 1) * np.minimum((length - t) / .08, 1)
        return (np.sin(2 * np.pi * freq * t) + .25 * np.sin(4 * np.pi * freq * t)) * env * gain
    for tick in range(92):
        at = 1 + tick * beat
        t = np.arange(int(.24 * sr)) / sr
        if tick % 2 == 0:
            kick = np.sin(2 * np.pi * (48 * t + 9 * (1 - np.exp(-t * 32)))) * np.exp(-t * 20)
            add('Drums', at, 0, kick * .48)
        else:
            add('Drums', at, 2, rng.normal(0, .22, len(t)) * np.exp(-t * 22))
        t2 = np.arange(int(.07 * sr)) / sr
        add('Drums', at + .25, 3, rng.normal(0, .07, len(t2)) * np.exp(-t2 * 60))
        root = [55, 65.406, 49, 73.416][(tick // 8) % 4]
        add('Bass', at, (tick // 8) % 4, tone(root, .40, .19), .30 if tick % 4 == 0 else 0)
        if tick % 2 == 0:
            for k, semitone in enumerate([0, 7, 12, 7]):
                add('Synth', at + k * .125, (tick // 2 + k) % 4, tone(root * 4 * 2 ** (semitone / 12), .11, .075))
        if tick % 4 == 0:
            chord = sum(tone(root * 4 * 2 ** (s / 12), 1.4, .035) for s in [0, 3, 7])
            add('Keys', at, (tick // 4) % 4, chord, 1.1)
    mix = np.tanh(mix) * .88
    with wave.open(str(out / 'audio.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((mix * 32767).astype('<i2').tobytes())
    if '--audio-only' in sys.argv:
        return
    charts = {}
    for part, notes in events.items():
        notes.sort(key=lambda n: (n['t'], n['lane']))
        charts[part] = {name: notes[::stride] for name, stride in [('Easy', 4), ('Normal', 3), ('Hard', 2), ('Expert', 1)]}
    (out / 'song.json').write_text(json.dumps({'schema': 1, 'id': 'demo-first-light', 'title': 'First Light', 'artist': 'Pulse Four / original demo', 'category': 'Built-in', 'duration': duration, 'audio': 'audio.wav', 'charts': charts}, indent=2))

if __name__ == '__main__':
    main()
