from pathlib import Path
import sys
import base64
import hashlib
import json
import threading
import unittest
import urllib.request
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'server'))
from lobby_server import LobbyService,LobbyError,Server,PROTOCOL

class OnlineTests(unittest.TestCase):
    def setUp(self):
        self.now=1000.
        self.service=LobbyService(lambda:self.now)
        self.base={'protocol':PROTOCOL,'room':'Band room','password':'test password','name':'Host','song':'a'*64,'title':'Song'}
        self.host=self.service.call('create',dict(self.base))
        self.guest=self.service.call('join',dict(self.base,name='Guest'))
    def tearDown(self):self.service.storage.cleanup()
    def call(self,action,who,**kw):
        return self.service.call(action,dict(protocol=PROTOCOL,room='Band room',token=who['token'],**kw))
    def ready(self,who):return self.call('ready',who,song='a'*64,instrument='Bass',difficulty='Expert',ready=True)
    def test_password_and_session_isolation(self):
        with self.assertRaises(LobbyError):self.service.call('join',dict(self.base,password='wrong'))
        self.assertNotIn('password',self.host)
        self.assertTrue(all('token' not in p and 'seen' not in p for p in self.host['players']))
        with self.assertRaises(LobbyError):self.call('poll',{'token':'made up'})
        self.assertNotEqual(self.host['token'],self.guest['token'])
    def test_mismatched_song_can_join_but_cannot_ready(self):
        peer=self.service.call('join',dict(self.base,name='Missing song',song='b'*64))
        self.assertFalse(peer['players'][-1]['matched'])
        with self.assertRaises(LobbyError):self.call('ready',peer,song='b'*64,instrument='Bass',difficulty='Expert',ready=True)
        self.assertTrue(self.ready(peer)['players'][-1]['matched'])
    def test_host_start_authority_readiness_and_scores(self):
        with self.assertRaises(LobbyError):self.call('start',self.host)
        self.ready(self.host);self.ready(self.guest)
        with self.assertRaises(LobbyError):self.call('start',self.guest)
        state=self.call('start',self.host)
        self.assertEqual(state['start_at'],1006.)
        report={'score':600,'combo':2,'accuracy':100,'finished':True}
        self.assertEqual(self.call('poll',self.guest,round=1,report=report)['players'][1]['score'],0)
        self.now=1007.
        state=self.call('poll',self.guest,round=1,report=report)
        self.assertEqual(state['players'][1]['score'],600)
        self.assertTrue(state['players'][1]['finished'])
        self.assertEqual(self.call('poll',self.host)['players'][0]['score'],0)
        with self.assertRaises(LobbyError):self.call('ready',self.guest,song='a'*64,instrument='Bass',difficulty='Easy',ready=True)
    def test_disconnect_cancels_round_and_host_closes_room(self):
        self.ready(self.host);self.ready(self.guest);self.call('start',self.host)
        self.call('leave',self.guest)
        self.assertEqual(self.call('poll',self.host)['start_at'],0)
        self.call('leave',self.host)
        with self.assertRaises(LobbyError):self.call('poll',self.guest)
    def test_stale_peers_expire(self):
        self.now+=13
        with self.assertRaises(LobbyError):self.call('poll',self.host)
    def upload(self,name,contents,who=None,offset=0,size=None):
        return self.call('upload',who or self.host,file=name,offset=offset,size=size or len(contents),data=base64.b64encode(contents).decode())
    def publish_pack(self):
        metadata={'schema':1,'audio':'audio.wav','video':'background.ogv','charts':{'Bass':{'Easy':[{'t':1,'end':1,'lane':0}]}}}
        values={'song.json':json.dumps(metadata).encode(),'audio.wav':b'fixture audio bytes','background.ogv':b'fixture video bytes'}
        for name,content in values.items():self.upload(name,content)
        self.call('publish',self.host)
        return values
    def test_host_pack_roundtrip_with_video_and_checksums(self):
        values=self.publish_pack()
        state=self.call('poll',self.guest)
        self.assertTrue(state['published'])
        self.assertEqual(len(state['files']),3)
        for item in state['files']:
            path,meta=self.service.download(self.guest['token'],item['name'])
            self.assertEqual(path.read_bytes(),values[item['name']])
            self.assertEqual(meta['sha256'],hashlib.sha256(values[item['name']]).hexdigest())
        with self.assertRaises(LobbyError):self.service.download('outsider','audio.wav')
    def test_upload_permissions_paths_and_partial_files(self):
        with self.assertRaises(LobbyError):self.upload('audio.wav',b'bytes',self.guest)
        with self.assertRaises(LobbyError):self.upload('../outside',b'bytes')
        self.upload('audio.wav',b'part',size=8)
        with self.assertRaises(LobbyError):self.call('publish',self.host)
        with self.assertRaises(LobbyError):self.upload('audio.wav',b'part',offset=2,size=8)
        self.upload('audio.wav',b'last',offset=4,size=8)
        with self.assertRaises(LobbyError):self.service.download(self.guest['token'],'audio.wav')
    def test_http_download_and_authenticated_control(self):
        values=self.publish_pack()
        server=Server(('127.0.0.1',0),self.service)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        url='http://127.0.0.1:'+str(server.server_port)
        try:
            request=urllib.request.Request(url+'/api/poll',json.dumps({'protocol':PROTOCOL,'room':'Band room','token':self.guest['token']}).encode(),{'Content-Type':'application/json'})
            with urllib.request.urlopen(request,timeout=3) as response:state=json.load(response)
            self.assertEqual(state['room'],'Band room')
            request=urllib.request.Request(url+'/file/background.ogv',headers={'Authorization':'Bearer '+self.guest['token']})
            with urllib.request.urlopen(request,timeout=3) as response:self.assertEqual(response.read(),values['background.ogv'])
        finally:server.shutdown();server.server_close();thread.join()
