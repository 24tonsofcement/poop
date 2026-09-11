from pathlib import Path
import sys
import unittest
import tempfile
import wave
import math
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'importer'))
from charting import generate_charts, phrase_patterns, sparse_sustains

class PhraseTests(unittest.TestCase):
    def test_long_runs_repeat_motifs_without_altering_times(self):
        attacks=list(range(25,425,25))
        lanes={i:1 for i in attacks}
        scores=np.ones(450)
        for part in ['bass','drums','vocals','other']:
            arranged=phrase_patterns(attacks,lanes,scores,.01,part)
            self.assertEqual(set(arranged),set(lanes))
            self.assertEqual(arranged,phrase_patterns(attacks,lanes,scores,.01,part))
            result=[arranged[i] for i in attacks]
            self.assertTrue(all(a!=b for a,b in zip(result,result[1:])))
            self.assertTrue(any(all(result[i]==result[i%period] for i in range(len(result))) for period in [2,4,6]))
            self.assertTrue(all(0<=lane<4 for lane in result))
        self.assertEqual(set(lanes.values()),{1}, 'Original pitch lanes must remain untouched')

    def test_short_gestures_and_melodic_movement_preserved(self):
        attacks=list(range(0,250,25));lanes={i:j//2%4 for j,i in enumerate(attacks)}
        self.assertEqual(phrase_patterns(attacks,lanes,np.ones(250),.01,'bass'),lanes)

    def test_other_attacks_do_not_destroy_audible_sustain(self):
        notes=[{'t':.1,'end':.8,'lane':0}]
        pitch=20+2*np.sin(np.arange(200)*.1)
        sparse_sustains(notes,pitch,[10,30,50,70],.01)
        self.assertEqual(notes[0]['end'],.8)

    def test_vibrato_and_shorter_sustains_generate_holds_end_to_end(self):
        rate=22050
        starts=np.arange(.4,16.4,.8)
        x=np.zeros(rate*17)
        for j,start in enumerate(starts):
            t=np.arange(round(rate*.56))/rate
            frequency=[220,330,440,550][j%4]
            phase=2*np.pi*frequency*t-1.5*np.cos(2*np.pi*5*t)
            envelope=np.clip(t/.015,0,1)*np.clip((.56-t)/.025,0,1)
            signal=.55*np.sin(phase)*envelope
            a=round(start*rate);x[a:a+len(signal)]=signal
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'sustains.wav'
            with wave.open(str(path),'wb') as f:
                f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate)
                f.writeframes((x*32767).astype('<i2').tobytes())
            charts=generate_charts(path,instrument='vocals')
        self.assertTrue(any(n['end']>n['t'] for n in charts['Expert']))
        for notes in charts.values():
            holds=[n for n in notes if n['end']>n['t']]
            self.assertLessEqual(len(holds),max(1,math.ceil(len(notes)*.18)))
            for lane in range(4):
                same=[n for n in notes if n['lane']==lane]
                self.assertTrue(all(a['end']<b['t'] for a,b in zip(same,same[1:])))
            for note in notes:
                self.assertLess(min(abs(starts-note['t'])),.04)

    def test_thinning_does_not_restore_a_column_of_repeated_notes(self):
        rate=22050
        starts=np.arange(.5,8.5,.25)
        x=np.zeros(rate*9)
        for start in starts:
            t=np.arange(round(rate*.09))/rate
            burst=.6*np.sin(2*np.pi*220*t)*np.exp(-t*40)
            a=round(start*rate);x[a:a+len(burst)]=burst
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'repeated.wav'
            with wave.open(str(path),'wb') as f:
                f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate)
                f.writeframes((x*32767).astype('<i2').tobytes())
            charts=generate_charts(path,instrument='bass')
        for difficulty,notes in charts.items():
            self.assertGreaterEqual(len(notes),4)
            count=1
            for a,b in zip(notes,notes[1:]):
                count=count+1 if a['lane']==b['lane'] and b['t']-a['t'] <= 1.2 else 1
                self.assertLess(count,4,difficulty)
