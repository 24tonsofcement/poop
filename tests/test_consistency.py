from pathlib import Path
import sys
import tempfile
import unittest
import wave
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'importer'))
from charting import generate_charts, phrase_patterns, reuse_riffs

class ConsistencyTests(unittest.TestCase):
    def write(self,path,x,rate):
        with wave.open(str(path),'wb') as f:
            f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate)
            f.writeframes((np.clip(x,-.99,.99)*32767).astype('<i2').tobytes())
    def test_same_flat_riff_ignores_loudness_fingerprint(self):
        attacks=list(range(20,420,25));lanes={i:1 for i in attacks}
        a=np.ones(500);b=np.ones(500)
        b[attacks]=np.linspace(.2,1.,len(attacks))
        self.assertEqual(phrase_patterns(attacks,lanes,a,.01,'bass'),phrase_patterns(attacks,lanes,b,.01,'bass'))
    def test_recurring_melody_keeps_pattern_with_different_loudness_and_harmonics(self):
        rate=22050;x=np.zeros(rate*13)
        sequence=[220,330,440,330,220,220,330,220]
        rhythm=np.array([0,.25,.5,1.,1.25,1.5,1.75,2.25])
        starts=[]
        for occurrence,start in enumerate([.5,5.5,9.]):
            starts.append(start+rhythm)
            for frequency,at in zip(sequence,start+rhythm):
                t=np.arange(round(rate*.13))/rate
                signal=np.sin(2*np.pi*frequency*t)
                if occurrence==1:signal=signal*.35+np.sin(4*np.pi*frequency*t)*.65
                signal*=.5*np.exp(-t*18)*(1 if occurrence!=2 else .6)
                a=round(at*rate);x[a:a+len(signal)]+=signal
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'riffs.wav';self.write(path,x,rate)
            notes=generate_charts(path,instrument='vocals')['Expert']
        patterns=[]
        for occurrence in starts:
            matched=[min(notes,key=lambda n:abs(n['t']-t)) for t in occurrence]
            self.assertTrue(all(abs(n['t']-t)<.04 for n,t in zip(matched,occurrence)))
            patterns.append([n['lane'] for n in matched])
        self.assertEqual(patterns[0],patterns[1])
        self.assertEqual(patterns[0],patterns[2])
    def test_template_reuses_arrangement_without_moving_note_times(self):
        first=[20,45,70,120,145,170,195,245]
        attacks=first+[i+400 for i in first]
        lanes={at:i%4 for i,at in enumerate(attacks)}
        for i in range(8):lanes[attacks[8+i]]=(i+1)%4
        pitches=np.full(800,10,dtype=int)
        for i,at in enumerate(attacks):pitches[at:at+6]=[10,12,15,12,10,10,12,10][i%8]
        mapped=reuse_riffs(attacks,lanes,pitches,.01,np.arange(100)*20,'vocals')
        self.assertEqual(set(mapped),set(attacks))
        self.assertEqual([mapped[i] for i in attacks[:8]],[mapped[i] for i in attacks[8:]])
