"""Pulse Four lobby service. Standard library only; LAN HTTP / internet HTTPS."""
from __future__ import annotations
import argparse
import base64
import binascii
import tempfile
from pathlib import Path
import shutil
import hashlib
import hmac
import json
import math
import secrets
import ssl
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROTOCOL = 'pulse-online-1'
MAX_BODY = 400000
FILE_LIMITS = {"song.json": 32*1024*1024, "audio.wav": 256*1024*1024, "background.ogv": 256*1024*1024, "background.png": 8*1024*1024}

class LobbyError(Exception):
    pass


def text(value, maximum=64):
    if not isinstance(value,str) or not value.strip() or len(value)>maximum or any(ord(c)<32 for c in value):
        raise LobbyError('Invalid or empty text field.')
    return value.strip()


def credential(password,salt):
    return hashlib.pbkdf2_hmac('sha256',password.encode(),salt,120000)


class LobbyService:
    def __init__(self, clock=time.time):
        self.clock=clock
        self.rooms={}
        self.lock=threading.RLock()
        self.attempts={}
        self.storage=tempfile.TemporaryDirectory(prefix="pulse-lobbies-")

    def prune(self):
        now=self.clock()
        for key,room in list(self.rooms.items()):
            for token,player in list(room['players'].items()):
                if now-player['seen']>12:
                    self.remove(key,token)
                    if key not in self.rooms:break
        self.attempts={ip:q for ip,q in self.attempts.items() if q and now-q[-1]<60}

    def remove(self,key,token):
        room=self.rooms.get(key)
        if not room:return
        if token==room['host']:
            shutil.rmtree(room['folder'],ignore_errors=True)
            del self.rooms[key]
            return
        room['players'].pop(token,None)
        if room['start_at']:
            room['start_at']=0
            room['notice']='A player left. Return to the lobby and ready again.'
            for p in room['players'].values():p['ready']=False

    def player(self,name):
        return {'id':secrets.token_hex(8),'name':text(name,16),'ready':False,'seen':self.clock(),
                'matched':False,'instrument':'','difficulty':'','score':0,'combo':0,'accuracy':100.,'finished':False}

    def snapshot(self,room,token):
        return {'protocol':PROTOCOL,'server_time':self.clock(),'token':token,'self_id':room['players'][token]['id'],
                'host_id':room['players'][room['host']]['id'],'room':room['name'],'song':room['song'],
                'title':room['title'],'files':room['manifest'] if room['published'] else [],'published':room['published'],'round':room['round'],'start_at':room['start_at'],'notice':room['notice'],
                'players':[{k:v for k,v in p.items() if k!='seen'} for p in room['players'].values()]}

    def call(self,action,data,ip='local'):
        with self.lock:
            self.prune()
            if not isinstance(data,dict) or data.get('protocol')!=PROTOCOL:
                raise LobbyError('Game version mismatch. Install the same multiplayer update on every PC.')
            key=text(data.get('room'),40).casefold()
            if action in ('create','join'):
                attempts=self.attempts.setdefault(ip,deque())
                while attempts and self.clock()-attempts[0]>60:attempts.popleft()
                if len(attempts)>=12:raise LobbyError('Too many join attempts. Wait one minute.')
                attempts.append(self.clock())
                password=text(data.get('password'),128)
                if action=='create':
                    if key in self.rooms:raise LobbyError('Lobby name already exists.')
                    if len(self.rooms)>=64:raise LobbyError('Server is full.')
                    signature=text(data.get('song'),64)
                    if len(signature)!=64 or any(c not in '0123456789abcdef' for c in signature):raise LobbyError('Invalid song fingerprint.')
                    player=self.player(data.get('name'))
                    salt=secrets.token_bytes(16)
                    token=secrets.token_urlsafe(32)
                    player['matched']=True
                    folder=Path(self.storage.name)/secrets.token_hex(16)
                    folder.mkdir()
                    self.rooms[key]={'folder':folder,'uploads':{},'manifest':[],'published':False,'name':text(data['room'],40),'song':signature,'title':text(data.get('title'),160),
                        'salt':salt,'password':credential(password,salt),'players':{token:player},'host':token,
                        'round':0,'start_at':0.,'notice':''}
                else:
                    room=self.rooms.get(key)
                    if not room or not hmac.compare_digest(credential(password,room['salt']),room['password']):
                        raise LobbyError('Lobby name or password is incorrect.')
                    if room['start_at']:raise LobbyError('Round in progress. Join when the host returns to the lobby.')
                    if len(room['players'])>=4:raise LobbyError('Lobby is full (four PCs).')
                    token=secrets.token_urlsafe(32)
                    room['players'][token]=self.player(data.get('name'))
                    room['players'][token]['matched']=data.get('song')==room['song']
                return self.snapshot(self.rooms[key],token)
            room=self.rooms.get(key)
            token=data.get('token')
            if not isinstance(token,str) or not room or token not in room['players']:
                raise LobbyError('Lobby closed or connection expired. Join again.')
            player=room['players'][token]
            player['seen']=self.clock()
            if action=='leave':
                self.remove(key,token)
                return {'left':True,'server_time':self.clock()}
            if action in ('upload','publish'):
                if token!=room['host']:raise LobbyError('Only the host can share the song.')
                return self.upload(room,action,data)
            if action=='ready':
                if room['start_at']:raise LobbyError('Cannot change selection during a round.')
                if data.get('song')!=room['song']:raise LobbyError('Song/chart mismatch.')
                player['matched']=True
                player['instrument']=text(data.get('instrument'),80)
                player['difficulty']=text(data.get('difficulty'),80)
                player['ready']=bool(data.get('ready'))
            elif action=='start':
                if token!=room['host']:raise LobbyError('Only the host can start.')
                if room['start_at']:raise LobbyError('A round is already active.')
                if len(room['players'])<2 or not all(p['ready'] and p['matched'] for p in room['players'].values()):
                    raise LobbyError('At least two players must be ready.')
                room['round']+=1
                room['start_at']=self.clock()+6
                room['notice']=''
                for p in room['players'].values():p.update(score=0,combo=0,accuracy=100.,finished=False)
            elif action=='reset':
                if token!=room['host']:raise LobbyError('Only the host can return everyone to the lobby.')
                room['start_at']=0
                room['notice']='Host returned to the lobby.'
                for p in room['players'].values():p['ready']=False
            elif action=='poll':
                report=data.get('report')
                if report and room['start_at'] and self.clock()>=room['start_at'] and data.get('round')==room['round']:
                    if not isinstance(report,dict):raise LobbyError('Invalid score report.')
                    for field,maximum in [('score',1000000000),('combo',1000000)]:
                        value=report.get(field,0)
                        if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value) or not 0<=value<=maximum:
                            raise LobbyError('Invalid score report.')
                    accuracy=report.get('accuracy',100.)
                    if not isinstance(accuracy,(float,int)) or not math.isfinite(accuracy) or not 0<=accuracy<=100:
                        raise LobbyError('Invalid accuracy report.')
                    if not player['finished']:
                        player.update(score=max(player['score'],int(report['score'])),combo=int(report['combo']),accuracy=float(accuracy),finished=bool(report.get('finished')))
            else:raise LobbyError('Unknown action.')
            return self.snapshot(room,token)


    def upload(self,room,action,data):
        if room['start_at']:raise LobbyError('Finish the round before sharing files.')
        if action=='publish':
            uploads=room['uploads']
            if not all(name in uploads and uploads[name]['received']==uploads[name]['size'] for name in ('song.json','audio.wav')):
                raise LobbyError('Song upload is incomplete.')
            if any(item['received']!=item['size'] for item in uploads.values()):raise LobbyError('File upload is incomplete.')
            try:
                meta=json.loads((room['folder']/'song.json').read_text(encoding='utf-8'))
                if not isinstance(meta,dict) or meta.get('schema')!=1 or not isinstance(meta.get('charts'),dict) or meta.get('audio')!='audio.wav':raise ValueError()
                if meta.get('video') and (meta['video']!='background.ogv' or 'background.ogv' not in uploads):raise ValueError()
                if meta.get('background_image') and (meta['background_image']!='background.png' or 'background.png' not in uploads):raise ValueError()
            except (ValueError,OSError):raise LobbyError('Invalid song metadata.')
            room['manifest']=[]
            for name,item in uploads.items():
                with (room['folder']/name).open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
                room['manifest'].append({'name':name,'size':item['size'],'sha256':digest})
            room['published']=True
            return {'published':True}
        name=data.get('file')
        size=data.get('size');offset=data.get('offset')
        if name not in FILE_LIMITS or type(size) is not int or type(offset) is not int or not 0<size<=FILE_LIMITS[name] or not 0<=offset<size:
            raise LobbyError('Invalid upload file or size.')
        try:chunk=base64.b64decode(data.get('data',''),validate=True)
        except (ValueError,binascii.Error):raise LobbyError('Invalid upload encoding.')
        if not 0<len(chunk)<=262144 or offset+len(chunk)>size:raise LobbyError('Invalid upload chunk.')
        if offset==0:
            if name=='song.json':
                room['published']=False
                room['uploads'].clear()
                for old_file in room['folder'].iterdir():
                    old_file.unlink(missing_ok=True)
            reserved=sum(item['size'] for r in self.rooms.values() for item in r['uploads'].values())
            old=room['uploads'].get(name,{}).get('size',0)
            if reserved-old+size>2*1024**3:raise LobbyError('Server transfer storage is full.')
            room['published']=False
            room['uploads'][name]={'size':size,'received':0}
            (room['folder']/name).write_bytes(b'')
        item=room['uploads'].get(name)
        if not item or item['size']!=size or item['received']!=offset:raise LobbyError('Upload offset mismatch. Retry sharing.')
        with (room['folder']/name).open('ab') as f:f.write(chunk)
        item['received']+=len(chunk)
        return {'offset':item['received']}

    def download(self,token,name):
        with self.lock:
            self.prune()
            for room in self.rooms.values():
                if token in room['players']:
                    room['players'][token]['seen']=self.clock()
                    if not room['published'] or name not in FILE_LIMITS:break
                    for item in room['manifest']:
                        if item['name']==name:
                            return room['folder']/name,dict(item)
            raise LobbyError('File unavailable or lobby connection expired.')


class Handler(BaseHTTPRequestHandler):
    protocol_version='HTTP/1.0'
    def setup(self):
        super().setup()
        self.connection.settimeout(5)
    def log_message(self,*args):pass  # Never log passwords, tokens or request bodies.
    def do_GET(self):
        if self.path.startswith('/file/'):
            try:
                auth=self.headers.get('Authorization','')
                path,item=self.server.service.download(auth.removeprefix('Bearer '),self.path[6:])
                with path.open('rb') as f:
                    self.send_response(200)
                    self.send_header('Content-Type','application/octet-stream')
                    self.send_header('Content-Length',str(item['size']))
                    self.send_header('Cache-Control','no-store')
                    self.end_headers()
                    shutil.copyfileobj(f,self.wfile,262144)
            except LobbyError as e:self.respond(403,{'error':str(e)})
            except (OSError,ConnectionError):pass
        else:
            self.respond(200,{'service':'Pulse Four','protocol':PROTOCOL})
    def respond(self,status,value):
        body=json.dumps(value,allow_nan=False).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(body)))
        self.send_header('Cache-Control','no-store')
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 0<length<=MAX_BODY:raise LobbyError('Invalid request size.')
            data=json.loads(self.rfile.read(length))
            if not self.path.startswith('/api/'):raise LobbyError('Unknown endpoint.')
            reply=self.server.service.call(self.path[5:],data,self.client_address[0])
            self.respond(200,reply)
        except (LobbyError,ValueError,TypeError,KeyError) as error:
            self.respond(400,{'error':str(error) if isinstance(error,LobbyError) else 'Invalid request.'})
        except (TimeoutError,ConnectionError):pass
        except OSError:
            self.respond(400,{'error':'Transfer storage is unavailable. Wait for other downloads and retry.'})


class Server(ThreadingHTTPServer):
    daemon_threads=True
    request_queue_size=32
    def __init__(self,address,service=None):
        self.service=service or LobbyService()
        super().__init__(address,Handler)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind',default='0.0.0.0')
    parser.add_argument('--port',type=int,default=27440)
    parser.add_argument('--cert',help='HTTPS full certificate chain PEM')
    parser.add_argument('--key',help='HTTPS private key PEM')
    args=parser.parse_args()
    if bool(args.cert)!=bool(args.key):parser.error('--cert and --key must be supplied together')
    server=Server((args.bind,args.port))
    if args.cert:
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version=ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(args.cert,args.key)
        server.socket=context.wrap_socket(server.socket,server_side=True)
    print(f'Pulse Four lobby service listening on {args.bind}:{server.server_address[1]} ({"HTTPS" if args.cert else "HTTP"})',flush=True)
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()

if __name__=='__main__':main()
