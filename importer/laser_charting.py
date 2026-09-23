"""Measured full-song charts for four BT keys, two FX keys and two laser paths."""
import math
import numpy as np
from charting import read_wav,generate_charts

LEVELS=['Easy','Normal','Hard','Expert','Master','Insane']

def validate(charts,duration):
    if not isinstance(charts,dict) or not 1<=len(charts)<=16:raise ValueError('Invalid laser chart set')
    total=0
    for name,chart in charts.items():
        if not isinstance(name,str) or not isinstance(chart,dict):raise ValueError('Invalid laser difficulty')
        notes=chart.get('buttons');lasers=chart.get('lasers')
        if not isinstance(notes,list) or not isinstance(lasers,list) or len(lasers)!=2:raise ValueError('Invalid laser lanes')
        last=-1;ends=[-1]*6
        for note in notes:
            t,end,lane=note.get('t'),note.get('end'),note.get('lane')
            if not all(type(v) in (int,float) and math.isfinite(v) for v in [t,end,lane]) or not 0<=t<=end<=duration+2 or t<last or lane!=int(lane) or not 0<=lane<6:raise ValueError('Invalid laser button')
            if t<ends[int(lane)]-.001:raise ValueError('Overlapping laser buttons')
            ends[int(lane)]=end+.00001;last=t
        total+=len(notes)
        for paths in lasers:
            if not isinstance(paths,list):raise ValueError('Invalid laser paths')
            last=-1
            for path in paths:
                points=path.get('points',[])
                if not 2<=len(points)<=4096:raise ValueError('Invalid laser point count')
                for point in points:
                    t,x=point.get('t'),point.get('x')
                    if not all(type(v) in (int,float) and math.isfinite(v) for v in [t,x]) or t<last or not 0<=t<=duration+2 or not 0<=x<=1:raise ValueError('Invalid laser point')
                    last=t
                if points[-1]['t']<=points[0]['t']:raise ValueError('Empty laser path')
                total+=len(points)
    if not 0<total<=500000:raise ValueError('Empty or oversized laser charts')
    return charts

def generate(audio,base=None):
    base=base or generate_charts(audio,instrument='mixed')
    samples,rate=read_wav(audio)
    # Spectral balance measures contour; rhythmic attacks decide when paths change.
    hop=max(1,int(rate*.05));n=2048
    contour=[];energy=[]
    freq=np.fft.rfftfreq(n,1/rate);mask=(freq>100)&(freq<6000)
    for start in range(0,len(samples),hop):
        frame=np.zeros(n);piece=samples[start:start+n];frame[:len(piece)]=piece
        spectrum=np.abs(np.fft.rfft(frame*np.hanning(n)))
        centroid=float(np.sum(spectrum[mask]*freq[mask])/max(np.sum(spectrum[mask]),1e-8))
        contour.append(centroid);energy.append(float(np.sqrt(np.mean(frame**2))))
    values=np.asarray(contour);power=np.asarray(energy)
    lo,hi=np.percentile(values,[15,85])
    values=np.clip((values-lo)/max(hi-lo,1),0,1)
    result={}
    for level,(difficulty,notes) in enumerate(base.items()):
        rank=LEVELS.index(difficulty) if difficulty in LEVELS else min(5,level+2)
        buttons=[];lasers=[[],[]];held=[0.]*6
        # Full-mix phrases keep a reproducible hand/pattern identity at every level.
        for note in notes:
            item=dict(note);phrase=int(item['t']//8)
            if item['end']-item['t']>.13 and (phrase+int(item['lane']))%3==0:
                item['lane']=4+int(item['lane'])%2
            elif rank>=2 and phrase%4==2 and int(item['lane']) in (0,3):
                item['lane']=4+int(item['lane'])//3
            lane=int(item['lane'])
            if item['t']<held[lane]+.025:continue
            held[lane]=item['end'];buttons.append(item)
        heads=sorted(set(float(v['t']) for v in notes))
        for phrase in range(int(len(samples)/rate)//8+1):
            side=phrase%2;start=phrase*8+2;finish=min(phrase*8+6,len(samples)/rate-.1)
            if finish-start<.6 or (rank==0 and phrase%3!=0):continue
            a=int(start/.05);b=min(len(power),int(finish/.05))
            if b<=a or float(power[a:b].mean())<max(.002,float(np.percentile(power,65))*.45):continue
            anchors=[t for t in heads if start<=t<=finish]
            gap=[1.,.75,.5,.3,.22,.15][rank]
            chosen=[]
            for t in anchors:
                if not chosen or t-chosen[-1]>=gap:chosen.append(t)
            if len(chosen)<2:continue
            points=[]
            for t in chosen:
                x=round(float(values[min(len(values)-1,int(t/.05))])* .8+.1,3)
                if points and rank<2:x=round(float(np.clip(x,points[-1]['x']-.3,points[-1]['x']+.3)),3)
                if points and rank>=2 and abs(x-points[-1]['x'])>.42:
                    # A sharp measured timbral change at an attack becomes a slam.
                    points.append({'t':round(t,5),'x':points[-1]['x']})
                points.append({'t':round(t,5),'x':x})
            lasers[side].append({'points':points})
            # One hand is on a knob. Leave the opposite BT/FX hand playable.
            occupied=(0,1,4) if side==0 else (2,3,5)
            buttons=[v for v in buttons if not(v['lane'] in occupied and v['end']>chosen[0]-.15 and v['t']<chosen[-1]+.15)]
            if rank>=3 and phrase%4==3 and len(points)>=3:
                other=1-side
                dual=[{'t':v['t'],'x':round(1-v['x'],3)} for v in points if v['t']>=points[-1]['t']-1.6]
                if len(dual)>=2 and dual[-1]['t']>dual[0]['t']:
                    lasers[other].append({'points':dual})
                    buttons=[v for v in buttons if not(v['end']>dual[0]['t']-.15 and v['t']<dual[-1]['t']+.15)]
        result[difficulty]={'buttons':buttons,'lasers':lasers}
    return validate(result,len(samples)/rate)

def attach(audio,pack):
    if 'laser_charts' in pack:
        validate(pack['laser_charts'],pack['duration'])
    else:pack['laser_charts']=generate(audio,next(iter(pack['charts'].values())))
    pack['mode']='laser'
    return pack
