"""Check the built lobby server and run two Godot clients, preserving diagnostics."""
from pathlib import Path
import argparse
import json
import re
import subprocess
import sys
import urllib.request
import urllib.error
import uuid
import os
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
PROTOCOL='pulse-online-1'

def preflight(url):
    # Local checks must not go through configured HTTP proxies.
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def request(path,data=None):
        req=urllib.request.Request(url+path,json.dumps(data).encode() if data is not None else None,
                                   {'Content-Type':'application/json'})
        try:
            with opener.open(req,timeout=8) as response:return json.load(response)
        except urllib.error.HTTPError as error:
            try:detail=json.loads(error.read()).get('error','HTTP request rejected')
            except (ValueError,AttributeError):detail='Non-JSON error response'
            raise RuntimeError(f'Server HTTP {error.code}: {detail}') from None
    health=request('/')
    if health.get('protocol')!=PROTOCOL:
        raise RuntimeError('Built server protocol mismatch: expected '+PROTOCOL+', got '+str(health.get('protocol')))
    room='diagnostic-'+uuid.uuid4().hex[:16]
    data=dict(protocol=PROTOCOL,room=room,password=uuid.uuid4().hex,name='Probe',song='a'*64,title='Local connection check')
    host=None
    try:
        host=request('/api/create',data)
        guest=request('/api/join',dict(data,name='Probe guest'))
        if len(guest.get('players',[]))!=2:raise RuntimeError('Server did not return two lobby members')
        request('/api/leave',dict(protocol=PROTOCOL,room=room,token=guest['token']))
    finally:
        if host:request('/api/leave',dict(protocol=PROTOCOL,room=room,token=host['token']))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('godot')
    parser.add_argument('--server-exe')
    args=parser.parse_args()
    log_path=ROOT/'build/network-diagnostic.txt'
    log_path.parent.mkdir(parents=True,exist_ok=True)
    log=[]
    def record(message):
        message=str(message)
        log.append(message)
        print(message,flush=True)
    command=[args.server_exe] if args.server_exe else [sys.executable,str(ROOT/'server/lobby_server.py')]
    server=None
    server_directory=tempfile.TemporaryDirectory(prefix='pulse-network-check-')
    server_log_path=Path(server_directory.name)/'server.log'
    server_log=None
    try:
        # File-backed output cannot deadlock on a child retaining a pipe handle.
        server_log=server_log_path.open('wb')
        server=subprocess.Popen(command+['--bind','127.0.0.1','--port','0'],stdout=server_log,stderr=subprocess.STDOUT)
        deadline=time.monotonic()+30
        match=None
        while time.monotonic()<deadline:
            output=server_log_path.read_text(encoding='utf-8',errors='replace')
            match=re.search(r'listening on 127\.0\.0\.1:(\d+)',output)
            if match:break
            if server.poll() is not None:
                raise RuntimeError('Lobby server exited before announcing its listening port.')
            time.sleep(.1)
        if not match:raise RuntimeError('Lobby server startup timed out.')
        url='http://127.0.0.1:'+match[1]
        record('Checking server health, protocol, lobby creation and joining over loopback...')
        preflight(url)
        record('Python loopback create/join check passed. Starting Godot clients...')
        result=subprocess.run([args.godot,'--headless','--path',str(ROOT),'--script','tests/online_smoke.gd','--',url],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
        output=result.stdout+result.stderr
        record(output)
        if result.returncode or 'Online smoke failures: 0' not in output or re.search(r'SCRIPT ERROR|Parse Error|ERROR:',output):
            raise RuntimeError('Godot multiplayer/transfer test failed. See build/network-diagnostic.txt.')
    except subprocess.TimeoutExpired as error:
        for value in (error.stdout,error.stderr):
            if value:record(value.decode('utf-8','replace') if isinstance(value,bytes) else value)
        record('DIAGNOSTIC: Godot test timed out.')
        raise
    except Exception as error:
        record('DIAGNOSTIC: '+str(error))
        raise
    finally:
        if server and server.poll() is None:
            # A PyInstaller one-file launcher has a child process on Windows.
            # Terminating only the launcher leaves the child server running.
            try:
                if os.name == 'nt':
                    subprocess.run(['taskkill','/PID',str(server.pid),'/T','/F'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
                else:
                    server.terminate()
                server.wait(timeout=5)
            except (OSError,subprocess.TimeoutExpired):
                server.kill()
                try:server.wait(timeout=3)
                except subprocess.TimeoutExpired:pass
        if server_log:server_log.close()
        log.append('SERVER OUTPUT\n'+server_log_path.read_text(encoding='utf-8',errors='replace') if server_log_path.exists() else 'No server output.')
        log_path.write_text('\n'.join(log),encoding='utf-8')
        print('Diagnostic log: '+str(log_path),flush=True)
        try:server_directory.cleanup()
        except OSError:pass

if __name__=='__main__':main()
