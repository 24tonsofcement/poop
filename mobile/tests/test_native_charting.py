import copy
import io
import sys
import unittest
from pathlib import Path
sys.path[:0]=[str(Path(__file__).resolve().parents[2]/'importer'),str(Path(__file__).resolve().parents[1]/'native/python')]
from ai_charting import apply_plan,validate_plan,LEVELS
from song_card import encode,decode
from PIL import Image

class NativeChartTests(unittest.TestCase):
    def setUp(self):
        self.measured={'families':['Drums:0'],'instruments':{'Drums':[{'family':'Drums:0','start':0,'end':4},{'family':'Drums:0','start':4,'end':8}]}}
        self.plan={'motifs':[{'family':'Drums:0','pattern':'roll','density':[1]*6,'hold_length':.5}]}
    def test_repeated_phrase_timing_and_lanes(self):
        notes=[{'t':t,'end':t,'lane':0} for t in [.25,.5,1,1.5,2,2.5,4.25,4.5,5,5.5,6,6.5]]
        charts={'Drums':{level:copy.deepcopy(notes) for level in LEVELS}}
        out=apply_plan(charts,self.measured,self.plan)['Drums']
        for level in LEVELS:
            self.assertEqual([n['t'] for n in out[level]],[n['t'] for n in notes])
            self.assertEqual([n['lane'] for n in out[level]][:6],[n['lane'] for n in out[level]][6:])
        self.assertTrue(all(n['lane']==0 for n in charts['Drums']['Easy']))
    def test_held_lanes_never_collide_and_max_two_holds(self):
        notes=[{'t':i/10,'end':i/10+2,'lane':i%4} for i in range(70)]
        out=apply_plan({'Drums':{'Expert':notes}},self.measured,self.plan)['Drums']['Expert']
        for i,n in enumerate(out):
            active=[v for v in out[:i] if v['end']>n['t']+.015]
            self.assertLessEqual(len(active)+int(n['end']>n['t']),2)
            self.assertNotIn(n['lane'],[v['lane'] for v in active])
            self.assertLessEqual(n['end']-n['t'],1.00001)
    def test_untrusted_ai_response_rejected(self):
        for change in [{'family':'invented'},{'pattern':'random'},{'density':[1,.5,1,1,1,1]},{'density':[float('nan')]*6},{'hold_length':20}]:
            p=copy.deepcopy(self.plan);p['motifs'][0].update(change)
            with self.assertRaises(ValueError):validate_plan(p,self.measured)
    def test_cards_preserve_every_difficulty_and_hype(self):
        song={'schema':1,'category':'YouTube','source':'https://www.youtube.com/watch?v=dQw4w9WgXcQ','title':'Card test','duration':8,
              'charts':{'Drums':{level:[{'t':1,'end':1.5,'lane':0},{'t':3,'end':3,'lane':2}] for level in LEVELS}},
              'hype':{'global':[{'start':2,'end':5,'confidence':.9}],'instruments':{}},'timing':[{'t':0,'beat_length':.5,'meter':4}]}
        stream=io.BytesIO();Image.new('RGB',(64,64)).save(stream,format='PNG')
        result=decode(encode(stream.getvalue(),song))
        for field in ['charts','hype','timing','source','title']:self.assertEqual(result[field],song[field])
        self.assertNotIn('api_key',result)
        damaged=bytearray(encode(stream.getvalue(),song));damaged[-20]^=1
        with self.assertRaises(ValueError):decode(damaged)
if __name__=='__main__':unittest.main()
