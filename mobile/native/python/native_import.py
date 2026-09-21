"""Android adapter; charting, instrument selection, hype and PNG codec are shared with PC."""
import json
import tempfile
import io
from pathlib import Path
import worker


def run(request_json, bridge):
    request = json.loads(request_json)
    library = Path(request['library']).resolve()
    library.mkdir(parents=True, exist_ok=True)
    class PhoneJob:
        cancel = None
        def update(self, message, progress=0):
            if bridge.isCancelled(): raise RuntimeError('Import cancelled')
            bridge.progress(str(message), float(progress))
        def run(self, args, message, progress=0):
            self.update(message, progress)
            args = [str(a) for a in args]
            if args[0] == '__yt-dlp':
                cleaned=[]; index=1
                while index<len(args):
                    if args[index] in ('--js-runtimes','--ffmpeg-location'):
                        index+=2;continue
                    cleaned.append(args[index]);index+=1
                bridge.download(json.dumps(cleaned))
            else:
                bridge.command(json.dumps(args))
    job = PhoneJob()
    worker.binary = lambda name: '__yt-dlp' if name=='yt-dlp' else '__unused_deno' if name=='deno' else bridge.binary(name)
    def separate(audio, temp, job):
        separated = temp/'stems'
        output = separated/worker.MODEL/audio.stem
        output.mkdir(parents=True)
        job.update('Separating six instruments on this device…', 30)
        bridge.command(json.dumps([bridge.binary('demucs'),bridge.modelPath(),str(audio),str(output)]))
        return separated
    worker.separate_stems = separate
    with tempfile.TemporaryDirectory(prefix='.import-',dir=library) as folder:
        temp=Path(folder)
        kind=request['kind']
        if kind=='card_import':
            paths,warnings=worker.import_card(request['source'],library,temp,job)
        elif kind=='card_export':
            from song_card import encode,decode,render_card
            from PIL import Image
            song=json.loads((Path(request['source'])/'song.json').read_text())
            thumb=Path(request['source'])/'thumbnail.jpg'
            stream=io.BytesIO()
            if thumb.exists():
                with Image.open(thumb) as im: im.convert('RGB').save(stream,format='PNG')
            else: Image.new('RGB',(640,360),'#152032').save(stream,format='PNG')
            data=encode(render_card(stream.getvalue(),song['title']),song)
            decode(data)
            Path(request['destination']).write_bytes(data)
            return json.dumps({'message':'Card ready','paths':[],'warnings':[]})
        elif kind in ('link','regenerate'):
            if request.get('ai'):
                from ai_charting import refine
                original=worker.instrument_charts
                original_hype=worker.song_hype
                original_commit=worker.commit_pack
                approved_hype=None
                def assisted(audio,temp,job):
                    nonlocal approved_hype
                    charts=original(audio,temp,job)
                    job.update('Claude: reviewing measured musical phrases and chart flow…',88)
                    edited,approved_hype=refine(charts,audio,temp/'stems'/worker.MODEL/audio.stem,bridge,job)
                    return edited
                worker.instrument_charts=assisted
                worker.song_hype=lambda *args,**kwargs: approved_hype
                def ai_commit(work,library,pack):
                    pack['generator'] += ' + Claude evidence-constrained editor ('+bridge.get_model()+')'
                    return original_commit(work,library,pack)
                worker.commit_pack=ai_commit
                try: paths,warnings=(worker.import_youtube if kind=='link' else worker.regenerate_song)(request['source'],library,temp,job)
                finally:
                    worker.instrument_charts=original
                    worker.song_hype=original_hype
                    worker.commit_pack=original_commit
            else: paths,warnings=(worker.import_youtube if kind=='link' else worker.regenerate_song)(request['source'],library,temp,job)
        else: raise ValueError('Unsupported phone import')
    return json.dumps({'message':'Import complete','paths':paths,'warnings':warnings})


def self_test(bridge):
    import numpy as np
    import scipy.signal
    from PIL import Image
    from song_card import encode, decode
    p={'schema':1,'category':'YouTube','source':'https://www.youtube.com/watch?v=dQw4w9WgXcQ','title':'Android round trip','duration':4,'charts':{'Drums':{'Easy':[{'t':1,'end':1,'lane':0}]}}}
    b=io.BytesIO();Image.new('RGB',(64,64)).save(b,format='PNG')
    assert decode(encode(b.getvalue(),p))['charts']==p['charts']
    assert scipy.signal.find_peaks(np.array([0.,1.,0.]))[0].tolist()==[1]
    bridge.command(json.dumps([bridge.binary('ffmpeg'),'-version']))
    import wave
    with tempfile.TemporaryDirectory() as tmp:
        folder=Path(tmp);audio=folder/'probe.wav';rate=44100
        t=np.arange(rate*8)/rate
        envelope=np.maximum(0,1-(t%0.25)/.12)
        signal=.2*np.sin(2*np.pi*220*t)*envelope+.08*np.sin(2*np.pi*440*t)
        pcm=np.repeat((signal*32767).astype('<i2')[:,None],2,axis=1)
        with wave.open(str(audio),'wb') as wav:
            wav.setnchannels(2);wav.setsampwidth(2);wav.setframerate(rate);wav.writeframes(pcm.tobytes())
        target=folder/'stems'
        bridge.command(json.dumps([bridge.binary('demucs'),bridge.modelPath(),str(audio),str(target),'--verify']))
        for source in worker.SOURCES:
            with wave.open(str(target/(source+'.wav'))) as wav:
                assert wav.getnframes()==rate*8 and wav.getnchannels()==2
        charts=worker.generate_charts(audio,allow_holds=True,instrument='piano')
        assert len(charts)==6 and any(charts.values())
        from song_card import render_card
        decode(encode(render_card(b.getvalue(),'Android song card'),p))
    return 'Python, SciPy, six-stem streaming/reference parity, six difficulties, PNG cards and FFmpeg passed'
