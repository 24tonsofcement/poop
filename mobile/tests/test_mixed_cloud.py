import copy,io,json,sys,tempfile,threading,unittest,wave
from pathlib import Path
from unittest.mock import patch
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'importer'),str(ROOT/'mobile/native/python'),str(ROOT/'mobile/cloud')]
from charting import generate_charts
from ai_charting import evidence,refine,LEVELS
from song_card import encode,decode
from PIL import Image

class MixedTests(unittest.TestCase):
    def test_full_mix_has_all_difficulties_and_card_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            audio=Path(d)/'mix.wav';rate=22050;t=np.arange(rate*16)/rate
            # Low rhythm and independently offset high melodic attacks; rests at end.
            x=.25*np.sin(2*np.pi*90*t)*np.maximum(0,1-(t%.5)/.08)
            x+=.20*np.sin(2*np.pi*880*t)*np.maximum(0,1-((t+.17)%.75)/.12)
            x[t>14]=0
            with wave.open(str(audio),'wb') as w:
                w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes((x*32767).astype('<i2').tobytes())
            charts={'Mixed':generate_charts(audio,instrument='mixed')}
            self.assertEqual(set(charts['Mixed']),set(LEVELS))
            for notes in charts['Mixed'].values():
                self.assertTrue(notes);self.assertTrue(all(n['t']<14.1 for n in notes))
                self.assertTrue(all(0<=n['lane']<=3 for n in notes))
                self.assertEqual(len(notes),len({(n['t'],n['lane']) for n in notes}))
            measured=evidence(charts,audio,Path(d)/'stems')
            self.assertTrue(all('bpm' in s and 'energy_change' in s for s in measured['instruments']['Mixed']))
            song={'schema':1,'category':'YouTube','source':'https://www.youtube.com/watch?v=dQw4w9WgXcQ','duration':16,'charts':charts}
            stream=io.BytesIO();Image.new('RGB',(32,32)).save(stream,format='PNG')
            self.assertEqual(decode(encode(stream.getvalue(),song))['charts'],charts)
    def test_budget_does_not_call_generation_api(self):
        class Bridge:
            def get_model(self):return 'test'
            def api(self,path,body):
                self_path=path
                if path!='/v1/models':raise AssertionError('Paid request above budget')
                return json.dumps({'data':[{'id':'test'}]})
        class Job:
            def update(self,*args):pass
        families=['Mixed:'+str(i) for i in range(100)]
        measured={'families':families,'instruments':{},'timing':[]}
        charts={'Mixed':{d:[] for d in LEVELS}}
        out,_=refine(charts,None,None,Bridge(),Job(),measured=measured,candidate_hype={'global':[],'instruments':{}})
        self.assertEqual(out,charts)

class CloudTransportTests(unittest.TestCase):
    def test_authenticated_upload_poll_delete_and_no_claude_key(self):
        import server,http.client
        from cloud_client import analyze_remote
        token='test-'+('x'*32)
        chart={'Mixed':{level:[{'t':.5,'end':.5,'lane':0}] for level in LEVELS}}
        response={'schema':1,'duration':2,'charts':chart,'timing':[{'t':0,'beat_length':.5,'meter':4}], 'evidence':{},'hype':{'global':[],'instruments':{}}}
        def fake_analysis(entry):
            try:
                self.assertEqual((entry['folder']/'audio.wav').read_bytes(),b'0'*100)
                entry.update(state='done',result=response)
            finally:
                import shutil
                shutil.rmtree(entry['folder']);server.SLOTS.release()
        class Bridge:
            def isCancelled(self):return False
        class Job:
            def update(self,*args):pass
        with patch.object(server,'TOKEN',token),patch.object(server,'analyze',fake_analysis):
            httpd=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
            thread=threading.Thread(target=httpd.serve_forever,daemon=True);thread.start()
            try:
                with tempfile.TemporaryDirectory() as d:
                    audio=Path(d)/'audio.wav';audio.write_bytes(b'0'*100)
                    with patch('cloud_client.http.client.HTTPSConnection',http.client.HTTPConnection):
                        endpoint='https://127.0.0.1:'+str(httpd.server_port)
                        with self.assertRaises(ValueError):analyze_remote(audio,endpoint,'wrong',Job(),Bridge())
                        result=analyze_remote(audio,endpoint,token,Job(),Bridge())
                        self.assertEqual(result['charts'],chart)
                        self.assertFalse(server.JOBS)
            finally:httpd.shutdown();httpd.server_close();thread.join()
