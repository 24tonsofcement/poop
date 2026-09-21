"""Bounded HTTPS cloud analysis; never sends the Claude key or raw audio to Claude."""
import http.client
import json
import time
import urllib.parse
from song_card import validate

MAX_RESULT=16*1024*1024

def analyze_remote(audio,endpoint,token,job,bridge):
    url=urllib.parse.urlsplit(endpoint)
    if url.scheme!='https' or not url.hostname or url.username or url.query or url.fragment:
        raise ValueError('Cloud analysis requires an HTTPS server address')
    prefix=url.path.rstrip('/')
    def call(method,path,source=None):
        connection=http.client.HTTPSConnection(url.hostname,url.port or 443,timeout=60)
        try:
            connection.putrequest(method,prefix+path)
            connection.putheader('Authorization','Bearer '+token)
            connection.putheader('Content-Length',str(source.stat().st_size if source else 0))
            if source:connection.putheader('Content-Type','audio/wav')
            connection.endheaders()
            if source:
                with source.open('rb') as stream:
                    while True:
                        if bridge.isCancelled():raise RuntimeError('Import cancelled')
                        chunk=stream.read(256*1024)
                        if not chunk:break
                        connection.send(chunk)
            response=connection.getresponse()
            data=response.read(MAX_RESULT+1)
            if len(data)>MAX_RESULT:raise ValueError('Cloud result exceeds size limit')
            if response.status not in (200,202):raise ValueError('Cloud analysis returned HTTP '+str(response.status)+'. Check server settings; no automatic paid retry was made.')
            return json.loads(data) if data else {}
        finally:connection.close()
    job.update('Uploading song to your cloud analysis worker…',25)
    created=call('POST','/v1/jobs',audio)
    identifier=created.get('id','')
    if len(identifier)!=32 or any(c not in '0123456789abcdef' for c in identifier):raise ValueError('Invalid cloud job')
    try:
        deadline=time.monotonic()+1800
        while time.monotonic()<deadline:
            if bridge.isCancelled():raise RuntimeError('Import cancelled')
            result=call('GET','/v1/jobs/'+identifier)
            state=result.get('state')
            if state=='done':
                result=result['result']
                if result.get('schema')!=1:raise ValueError('Incompatible cloud analysis version')
                validate({'schema':1,'category':'YouTube','source':'https://www.youtube.com/watch?v=dQw4w9WgXcQ','duration':result['duration'],'charts':result['charts']})
                if 'Mixed' not in result['charts'] or not isinstance(result.get('evidence'),dict) or not result.get('timing'):
                    raise ValueError('Cloud analysis is incomplete')
                return result
            if state=='error':raise ValueError('Cloud analysis failed. Check the worker logs or choose on-device processing.')
            job.update('Cloud: '+str(result.get('message','Analyzing song…'))[:160],min(85,float(result.get('progress',30))))
            time.sleep(2)
        raise TimeoutError('Cloud analysis timed out; no automatic paid retry was made')
    finally:
        try:call('DELETE','/v1/jobs/'+identifier)
        except Exception:pass
