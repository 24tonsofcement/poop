from pathlib import Path
import sys
import tempfile
import unittest
import wave
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'importer'))
from timing import parse_timing_points, estimate_timing
from charting import generate_charts, DIFFICULTIES
from worker import parse_osu
from test_importer import MAP

class TimingTests(unittest.TestCase):
    def save(self,path,x,rate=22050):
        with wave.open(str(path),'wb') as f:
            f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate)
            f.writeframes((x*32767).astype('<i2').tobytes())

    def test_osu_tempo_meter_and_inherited_velocity(self):
        points=parse_timing_points(['-500,500,4,0,0,100,1,0','2000,-50,4,0,0,100,0,0','4000,750,3,0,0,100,1,0','nan,300,4,0,0,100,1,0'])
        self.assertEqual(points,[{'t':-.5,'beat_length':.5,'meter':4},{'t':4.,'beat_length':.75,'meter':3}])
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'test.osu'
            path.write_text(MAP.replace('[HitObjects]','[TimingPoints]\n0,400,3,0,0,100,1,0\n[HitObjects]'))
            meta,_=parse_osu(path)
            self.assertEqual(meta['timing'],[{'t':0.,'beat_length':.4,'meter':3}])

    def test_generated_timing_tracks_tempo_change(self):
        rate=22050;x=np.zeros(rate*24)
        times=list(np.arange(.5,12,.5))+list(np.arange(12,23.8,.375))
        for at in times:
            t=np.arange(round(rate*.05))/rate
            burst=.6*np.sin(2*np.pi*220*t)*np.exp(-t*50)
            a=round(at*rate);x[a:a+len(burst)]=burst
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'tempo.wav';self.save(path,x)
            points=estimate_timing(path)
        self.assertAlmostEqual(points[0]['beat_length'],.5,delta=.02)
        self.assertAlmostEqual(points[-1]['beat_length'],.375,delta=.02)
        self.assertTrue(all(p['meter']==4 for p in points))

    def test_silent_timing_has_defined_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'silence.wav';self.save(path,np.zeros(22050*3))
            self.assertEqual(estimate_timing(path),[{'t':0.,'beat_length':.5,'meter':4}])

    def test_six_difficulties_add_density_on_fast_audio(self):
        rate=22050;x=np.zeros(rate*5);times=np.concatenate([np.arange(.5,2.4,.095),np.arange(2.5,4.5,.065)])
        for j,at in enumerate(times):
            t=np.arange(round(rate*.025))/rate
            burst=.6*np.sin(2*np.pi*(440 if j%2 else 220)*t)*np.exp(-t*100)
            a=round(at*rate);x[a:a+len(burst)]=burst
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'fast.wav';self.save(path,x)
            charts=generate_charts(path,allow_holds=False,instrument='drums')
        self.assertEqual(list(charts),['Easy','Normal','Hard','Expert','Master','Insane'])
        self.assertLess(len(charts['Expert']),len(charts['Master']))
        self.assertLess(len(charts['Master']),len(charts['Insane']))
        previous=set()
        for difficulty,notes in charts.items():
            heads={n['t'] for n in notes}
            self.assertTrue(previous<=heads)
            previous=heads
            for note in notes:
                self.assertLess(min(abs(times-note['t'])),.035)
            self.assertTrue(all(b['t']-a['t']>=DIFFICULTIES[difficulty][0]-.001 for a,b in zip(notes,notes[1:])))
