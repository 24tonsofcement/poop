"""Single-instance private analysis worker. Run behind HTTPS; no Anthropic credential needed."""
import hmac
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import wave
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'importer'),str(ROOT/'mobile/native/python')]
from charting import generate_charts
from instruments import MODEL,LABELS,selected_paths
from ai_charting import evidence
from hype import detect_hype
from timing import estimate_timing

TOKEN=os.environ.get('PULSE_CLOUD_TOKEN','')
JOBS={}
LOCK=threading.Lock()
SLOTS=threading.BoundedSemaphore(2)
MAX_UPLOAD=180*1024*1024

def analyze(entry):
    folder=entry['folder'];audio=folder/'audio.wav'
    try:
        with wave.open(str(audio)) as stream:
            duration=stream.getnframes()/stream.getframerate()
            if not 1<=duration<=900 or stream.getsampwidth()!=2 or stream.getnchannels() not in (1,2) or stream.getframerate()>48000:
                raise ValueError('Expected 1–900 seconds PCM16 mono/stereo WAV, <=48kHz')
        entry.update(message='Separating six stems',progress=30)
        stems=folder/'stems'
        with (folder/'separation.log').open('wb') as log:
            command=[sys.executable,'-m','demucs','-n',MODEL,'--shifts','0','-o',str(stems),str(audio)]
            child=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT)
            entry['process']=child
            if entry.get('cancelled'):child.terminate()
            if child.wait(timeout=1500):raise RuntimeError('Separation failed')
        if entry.get('cancelled'):return
        source_dir=stems/MODEL/audio.stem
        parts=selected_paths(audio,source_dir)
        charts={'Mixed':generate_charts(audio,instrument='mixed')}
        for name,path in parts.items():
            if entry.get('cancelled'):return
            entry.update(message='Charting '+LABELS[name],progress=65)
            charts[LABELS[name]]=generate_charts(path,allow_holds=name!='drums',instrument=name)
        entry.update(message='Measuring tempo, dynamics, repeating phrases and hype',progress=80)
        paths={LABELS[name]:source_dir/(name+'.wav') for name in LABELS if (source_dir/(name+'.wav')).exists()}
        result={'schema':1,'duration':duration,'charts':charts,'timing':estimate_timing(audio),
                'evidence':evidence(charts,audio,source_dir),'hype':detect_hype(audio,paths,charts=charts)}
        encoded=json.dumps(result,separators=(',',':'),allow_nan=False)
        if len(encoded.encode())>16*1024*1024:raise ValueError('Analysis exceeds response limit')
        entry.update(state='done',result=result)
    except Exception as exc:
        # Server logs contain only failure type; no credentials or uploaded metadata.
        print('Analysis failed: '+type(exc).__name__,flush=True)
        entry.update(state='error')
    finally:
        child=entry.get('process')
        if child and child.poll() is None:
            child.kill();child.wait()
        shutil.rmtree(folder,ignore_errors=True)
        SLOTS.release()
        if entry.get('cancelled'):
            with LOCK:JOBS.pop(entry['id'],None)

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def respond(self,code,data):
        data=json.dumps(data,separators=(',',':'),allow_nan=False).encode()
        self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    def authorized(self):
        if not hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+TOKEN):
            self.close_connection=True;self.respond(401,{'error':'Unauthorized'});return False
        with LOCK:
            for key,entry in list(JOBS.items()):
                if time.monotonic()-entry['created']>3600 and entry['state'] in ('done','error'):JOBS.pop(key,None)
        return True
    def do_POST(self):
        if not self.authorized():return
        if self.path!='/v1/jobs':self.respond(404,{});return
        try:length=int(self.headers.get('Content-Length','0'))
        except ValueError:length=0
        if not 44<=length<=MAX_UPLOAD:self.close_connection=True;self.respond(413,{});return
        with LOCK:full=len(JOBS)>=32
        if full or not SLOTS.acquire(blocking=False):self.close_connection=True;self.respond(429,{});return
        folder=Path(tempfile.mkdtemp(prefix='pulse-cloud-'))
        try:
            self.connection.settimeout(60)
            remaining=length
            with (folder/'audio.wav').open('wb') as stream:
                while remaining:
                    data=self.rfile.read(min(256*1024,remaining))
                    if not data:raise ValueError('Incomplete upload')
                    stream.write(data);remaining-=len(data)
            identifier=uuid.uuid4().hex
            entry={'id':identifier,'folder':folder,'created':time.monotonic(),'state':'working','message':'Preparing analysis','progress':25}
            with LOCK:JOBS[identifier]=entry
            threading.Thread(target=analyze,args=(entry,),daemon=True).start()
        except Exception:
            shutil.rmtree(folder,ignore_errors=True);SLOTS.release();self.respond(400,{});return
        self.respond(202,{'id':identifier})
    def find(self):
        if not self.authorized():return None
        prefix='/v1/jobs/'
        identifier=self.path[len(prefix):] if self.path.startswith(prefix) else ''
        with LOCK:entry=JOBS.get(identifier)
        if not entry:self.respond(404,{})
        return entry
    def do_GET(self):
        entry=self.find()
        if entry:self.respond(200,{k:entry[k] for k in ('state','message','progress','result') if k in entry})
    def do_DELETE(self):
        entry=self.find()
        if not entry:return
        entry['cancelled']=True
        child=entry.get('process')
        if child and child.poll() is None:child.terminate()
        with LOCK:
            if entry['state'] in ('done','error'):JOBS.pop(entry['id'],None)
        self.respond(200,{'deleted':True})

if __name__=='__main__':
    if len(TOKEN)<32:raise SystemExit('Set PULSE_CLOUD_TOKEN to a private random token of at least 32 characters')
    ThreadingHTTPServer(('0.0.0.0',8080),Handler).serve_forever()
