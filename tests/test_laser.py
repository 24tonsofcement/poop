import io,json,sys,tempfile,unittest,wave
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'importer'))
import numpy as np
from PIL import Image
from laser_charting import generate,validate
from song_card import encode,decode
import worker
class LaserTests(unittest.TestCase):
    def test_generation_and_card_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            audio=Path(d)/'audio.wav';rate=22050;t=np.arange(rate*40)/rate
            x=.25*np.sin(2*np.pi*(220+110*np.floor(t%4))*t)*np.maximum(0,1-(t%.25)/.18)
            with wave.open(str(audio),'wb') as w:
                w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes((x*32767).astype('<i2').tobytes())
            base=worker.generate_charts(audio)
            charts=generate(audio,base)
            self.assertEqual(len(charts),6)
            self.assertTrue(any(c['lasers'][0] for c in charts.values()))
            self.assertTrue(any(c['lasers'][1] for c in charts.values()))
            for chart in charts.values():
                for side,paths in enumerate(chart['lasers']):
                    occupied=(0,1,4) if side==0 else (2,3,5)
                    for path in paths:
                        start,end=path['points'][0]['t'],path['points'][-1]['t']
                        self.assertFalse(any(v['lane'] in occupied and v['end']>start and v['t']<end for v in chart['buttons']))
            pack={'schema':1,'category':'YouTube','source':'https://www.youtube.com/watch?v=dQw4w9WgXcQ','duration':40,'charts':{'Full mix':base},'laser_charts':charts,'mode':'laser'}
            image=io.BytesIO();Image.new('RGB',(32,32)).save(image,format='PNG')
            result=decode(encode(image.getvalue(),pack))
            self.assertEqual(result['laser_charts'],charts)
            self.assertEqual(result['mode'],'laser')
    def test_invalid_laser_payload(self):
        for x in [float('nan'),-1,2]:
            with self.assertRaises(ValueError):validate({'Easy':{'buttons':[], 'lasers':[[{'points':[{'t':0,'x':0},{'t':1,'x':x}]}],[]]}},2)
    def test_mode_separation_does_not_run_demucs(self):
        class Job:
            def update(self,*args):pass
        with patch.object(worker,'ACTIVE_MODE','laser'),patch.object(worker,'generate_charts',return_value={'Easy':[]}),patch.object(worker,'separate_stems',side_effect=AssertionError('Laser import should analyze full mix')):
            self.assertEqual(worker.instrument_charts(None,None,Job()),{'Full mix':{'Easy':[]}})
        self.assertEqual(worker.ACTIVE_MODE,'arcade')
