from pathlib import Path
import sys
import unittest
import tempfile
import wave
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'importer'))
from charting import generate_charts, sparse_sustains, rhythmic_salience

class RhythmTests(unittest.TestCase):
    def test_holds_are_sparse_spaced_and_do_not_cover_new_attacks(self):
        notes = [{'t': float(i), 'end': i + .9, 'lane': i % 4} for i in range(50)]
        sparse_sustains(notes, np.ones(5100) * 20, list(range(0, 5000, 100)), .01)
        holds = [n for n in notes if n['end'] > n['t']]
        self.assertGreater(len(holds), 0)
        self.assertLessEqual(len(holds), 9)
        self.assertTrue(all(b['t'] - a['t'] >= .8 for a,b in zip(holds, holds[1:])))
        self.assertTrue(all(n['end'] <= n['t'] + .94 for n in holds))

    def test_short_or_changing_tones_are_taps(self):
        for pitches, duration in [(np.ones(300)*20, .08), (np.arange(300), 1.5)]:
            notes = [{'t': .1, 'end': .1 + duration, 'lane': 0}]
            sparse_sustains(notes, pitches, [], .01)
            self.assertEqual(notes[0]['t'], notes[0]['end'])

    def test_recurring_pulse_beats_equal_strength_isolated_change(self):
        envelope = np.zeros(800)
        attacks = list(range(50,750,50)) + [323]
        envelope[attacks] = 1
        scores = rhythmic_salience(envelope, attacks, .01)
        self.assertGreater(scores[350], scores[323])

    def test_tempo_change_alignment_and_nested_difficulties(self):
        rate = 22050
        times = list(np.arange(.5,4,.5)) + list(np.arange(4,8,.375))
        samples = np.zeros(rate * 9)
        for i, t in enumerate(times):
            local = np.arange(int(.1*rate))/rate
            burst = (.8 if i % 2 == 0 else .4)*np.sin(2*np.pi*220*local)*np.exp(-local*40)
            start = round(t*rate)
            samples[start:start+len(burst)] += burst
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'tempo.wav'
            with wave.open(str(path),'wb') as w:
                w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate)
                w.writeframes((samples*32767).astype('<i2').tobytes())
            charts=generate_charts(path)
        previous=set()
        for difficulty in ['Easy','Normal','Hard','Expert']:
            heads={n['t'] for n in charts[difficulty]}
            self.assertTrue(previous <= heads)
            self.assertTrue(all(min(abs(t - n['t']) for t in times) < .035 for n in charts[difficulty]))
            previous=heads
        self.assertTrue(all(min(abs(n['t']-t) for n in charts['Expert']) < .035 for t in times))

    def test_short_holds_survive_and_long_holds_are_bounded(self):
        for length in [.18, .25, .5, 8.0]:
            notes = [{'t': .1, 'end': .1+length, 'lane': 0}]
            sparse_sustains(notes, np.ones(1000)*20, [], .01)
            self.assertGreater(notes[0]['end'], notes[0]['t'])
            self.assertLessEqual(notes[0]['end']-notes[0]['t'], 1.60001)

    def test_short_sustains_generated_from_audio(self):
        rate=22050; audio=np.zeros(rate*12)
        for t in np.arange(.5,11,.5):
            local=np.arange(int(.24*rate))/rate
            burst=.6*np.sin(2*np.pi*220*local)
            start=round(t*rate);audio[start:start+len(burst)] = burst
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'short.wav'
            with wave.open(str(path),'wb') as w:
                w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate)
                w.writeframes((audio*32767).astype('<i2').tobytes())
            notes=generate_charts(path,instrument='vocals')['Expert']
        holds=[n for n in notes if n['end']>n['t']]
        self.assertTrue(holds)
        self.assertTrue(all(.16 <= n['end']-n['t'] < .35 for n in holds))
