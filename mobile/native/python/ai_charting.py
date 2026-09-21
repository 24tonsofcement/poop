"""Evidence-constrained Claude chart editor. No raw audio, credentials, or invented timestamps in prompts."""
import copy
import json
from pathlib import Path
import numpy as np
from charting import read_wav
from timing import estimate_timing
from instruments import LABELS

LEVELS=['Easy','Normal','Hard','Expert','Master','Insane']
PATTERNS={'alternate':[0,2,1,3], 'roll':[0,1,2,3,2,1], 'inward':[0,3,1,2], 'trill':[0,2], 'outward':[1,2,0,3]}
REFERENCE={
 'provenance':'Measured user-supplied native osu!mania 4K corpus; not a verified popularity ranking. Aggregate observations, not a trained model.',
 'charts':169,'sets':43,'note_heads':249557,
 'median_chord_row_fraction':.3218,'median_hold_head_fraction':.0934,
 'single_transition_cross_hand_fraction':.634,'single_transition_same_lane_fraction':.013,
 'principles':['Keep repeated musical phrases recognizable','Use measured onsets only','Emphasize stronger attacks; calm music should breathe',
 'Reserve triples and quads for strong accents','Short supported sustains add variety; long holds need sustained evidence',
 'At most two simultaneous holds; chords may have four lanes','Do not change the musical voice followed midway through a phrase']}

from mania_prior import PRIOR
from itertools import permutations
REFERENCE['measured_corpus']=PRIOR
# Additional grammars are ranked by measured transition likelihoods, not randomness.
_matrix=np.asarray(PRIOR['transitions'],dtype=float)+1
_matrix/=_matrix.sum(axis=1,keepdims=True)
_grams=sorted(permutations(range(4)),key=lambda p:-sum(float(np.log(_matrix[a,b])) for a,b in zip(p,p[1:])))
for _pattern in _grams[:16]:PATTERNS['corpus_'+''.join(map(str,_pattern))]=list(_pattern)


def evidence(charts,audio,stems):
    timing=estimate_timing(audio)
    beat=float(timing[0]['beat_length'])
    span=max(2.4,min(8.,beat*8))
    result={};families=[]
    for instrument,diffs in charts.items():
        stem=next((name for name,label in LABELS.items() if label==instrument),'other')
        path=Path(stems)/(stem+'.wav')
        samples,rate=read_wav(path if path.exists() else audio)
        hop=max(1,round(rate*.02));n=len(samples)//hop
        power=np.sqrt(np.mean(samples[:n*hop].reshape(n,hop)**2,axis=1))
        attacks=np.maximum(np.diff(power,prepend=0),0)
        sections=[];templates=[]
        maximum=max(float(np.percentile(power,95)),1e-8)
        for index,start in enumerate(np.arange(0,len(samples)/rate,span)):
            a=int(start/.02);b=min(n,int((start+span)/.02));part=attacks[a:b]
            if not len(part):continue
            contour=np.array([float(v.mean()) if len(v) else 0 for v in np.array_split(part,32)])
            norm=float(np.linalg.norm(contour));unit=contour/max(norm,1e-10)
            # Ordered chroma fingerprints distinguish different melodies with the same rhythm.
            clip=samples[int(start*rate):min(len(samples),int((start+span)*rate))]
            chroma=[]
            freq=np.fft.rfftfreq(2048,1/rate)
            valid=(freq>=65)&(freq<=4200)
            pitch=np.mod(np.rint(69+12*np.log2(np.maximum(freq,1)/440)).astype(int),12)
            for chunk in np.array_split(clip,16):
                frame=np.zeros(2048,dtype=np.float32);take=chunk[:2048];frame[:len(take)]=take
                spectrum=np.abs(np.fft.rfft(frame*np.hanning(2048)))
                vector=np.bincount(pitch[valid],weights=spectrum[valid],minlength=12)
                vector=vector/max(float(np.linalg.norm(vector)),1e-9)
                chroma.append(vector)
            chroma=np.asarray(chroma).reshape(-1)
            chroma/=max(float(np.linalg.norm(chroma)),1e-9)
            family=None
            for tid,template in enumerate(templates):
                if norm>1e-6 and float(np.dot(unit,template[0]))>.94 and float(np.dot(chroma,template[1]))>.90:family=tid;break
            if family is None:family=len(templates);templates.append((unit,chroma))
            family_id=f'{instrument}:{family}'
            if family_id not in families:families.append(family_id)
            sections.append({'id':index,'family':family_id,'start':round(float(start),4),'end':round(min(float(start+span),len(samples)/rate),4),
                'energy':round(float(np.mean(power[a:b]))/maximum,3),
                'attack_contour':np.round(unit,3).tolist(),
                'pitch_class_contour':np.argmax(chroma.reshape(16,12),axis=1).tolist(),
                'difficulty_notes':{d:sum(start<=v['t']<start+span for v in notes) for d,notes in diffs.items()},
                'onset_strength':{str(v['t']):round(float(attacks[min(n-1,max(0,int(v['t']/.02)))]),6) for notes in diffs.values() for v in notes if start<=v['t']<start+span},
                'supported_holds':sum(start<=v['t']<start+span and v['end']>v['t']+.08 for v in diffs.get('Expert',[]))})
        result[instrument]=sections
    return {'timing':timing,'phrase_seconds':span,'instruments':result,'families':families,'reference':REFERENCE}


def validate_plan(plan,measured):
    if not isinstance(plan,dict) or not isinstance(plan.get('motifs'),list):raise ValueError('Claude returned no valid chart plan')
    allowed=set(measured['families']);result={}
    for item in plan['motifs']:
        if not isinstance(item,dict) or item.get('family') not in allowed or item.get('pattern') not in PATTERNS:raise ValueError('Claude used an unsupported motif')
        density=item.get('density')
        if not isinstance(density,list) or len(density)!=6 or any(type(v) not in (int,float) or not np.isfinite(v) or not .55<=v<=1 for v in density):raise ValueError('Invalid difficulty density')
        if density!=sorted(density):raise ValueError('Difficulty densities must increase')
        hold=item.get('hold_length',1)
        if hold not in (.5,1):raise ValueError('AI may only preserve or shorten measured holds')
        if item['family'] in result:raise ValueError('Duplicate motif plan')
        result[item['family']]=item
    if set(result)!=allowed:raise ValueError('Claude omitted musical phrases')
    return result


def apply_plan(charts,measured,plan):
    plan=validate_plan(plan,measured);out=copy.deepcopy(charts)
    for instrument,diffs in out.items():
        sections=measured['instruments'][instrument]
        for difficulty,notes in diffs.items():
            level=LEVELS.index(difficulty) if difficulty in LEVELS else 3
            changed=[];active={}
            for section in sections:
                policy=plan[section['family']];pattern=PATTERNS[policy['pattern']]
                selected=[dict(n) for n in notes if section['start']<=n['t']<section['end']]
                rows={}
                for note in selected:rows.setdefault(note['t'],[]).append(note)
                strengths=section.get('onset_strength',{})
                fraction=float(policy['density'][level])
                ordered=sorted(rows)
                # Keep the strongest measured attacks, with beat alignment only as a tie-breaker.
                # No hash, random sample, or invented time controls musical density.
                ranked=sorted(ordered,key=lambda at:(-float(strengths.get(str(at),1)),abs(((at-section['start'])/(measured.get('phrase_seconds',4)/8)+.5)%1-.5),at))
                retain=set(ranked[:max(1,round(len(rows)*fraction))])
                if ordered: retain.update((ordered[0],ordered[-1]))
                for index,(at,row) in enumerate(sorted(rows.items())):
                    if len(row)==1 and at not in retain:continue
                    active={lane:end for lane,end in active.items() if end>at+.015}
                    preferred=pattern[index%len(pattern)]
                    # Keep measured chord cardinality unless existing holds occupy lanes.
                    free=[(preferred+i)%4 for i in range(4) if (preferred+i)%4 not in active]
                    for old,lane in zip(row,free):
                        old['lane']=lane
                        length=old['end']-at
                        if length>.08:old['end']=round(at+length*policy.get('hold_length',1),5)
                        if old['end']>at+.08:
                            if len(active)>=2:old['end']=at
                            else:active[lane]=old['end']
                        changed.append(old)
            diffs[difficulty]=sorted(changed,key=lambda n:(n['t'],n['lane']))
    return out


def refine(charts,audio,stems,bridge,job):
    model=bridge.get_model()
    if not model:raise ValueError('Choose an available Claude model in Settings > AI first')
    available=json.loads(bridge.api('/v1/models','')).get('data',[])
    if model not in {item.get('id') for item in available}:raise ValueError('Selected Claude model is not available to this API key. Refresh Models in Settings.')
    measured=evidence(charts,audio,stems)
    from hype import detect_hype
    candidate_hype=detect_hype(audio,{LABELS[p.stem]:p for p in Path(stems).glob('*.wav') if p.stem in LABELS},charts=charts)
    candidates={}
    for scope,sections in [('global',candidate_hype.get('global',[])),*candidate_hype.get('instruments',{}).items()]:
        for index,section in enumerate(sections):candidates[f'{scope}:{index}']={'scope':scope,**section}
    measured['hype_candidates']=candidates
    # One whole-song request: the model sees recurring families together, avoiding independent random chunks.
    prompt={'task':'Plan coherent four-lane rhythm charts across six difficulties. Analyze every measured instrument and repeated family. Pick a consistent motif per family, progressively increasing density. Use corpus evidence as guidance, not quotas. Preserve rhythmic identity. You have audio measurements, not a listening session: do not invent musical claims.',
        'measurements':measured,'allowed_patterns':PATTERNS,
        'response_format':{'motifs':[{'family':'exact family id','pattern':'one allowed pattern','density':[.65,.75,.85,.9,.95,1.0],'hold_length':1}], 'hype_keep':['exact candidate id']},
        'rules':['Include every family exactly once','Density must be nondecreasing and each value 0.55..1.0','hold_length is 0.5 or 1; never extend unsupported holds','hype_keep may only contain supplied candidate IDs; keep strong lifts/drops or clear instrument solos, reject ambiguous candidates. An empty list is allowed.', 'Return JSON only']}
    families=measured['families']
    plan={'motifs':[], 'hype_keep':[]}
    batches=[families[i:i+48] for i in range(0,len(families),48)]
    overview={instrument:[{k:v for k,v in section.items() if k not in ('attack_contour','onset_strength')} for section in sections] for instrument,sections in measured['instruments'].items()}
    for index,batch in enumerate(batches):
        job.update(f'Claude: reviewing phrase group {index+1}/{len(batches)}…',88+3*index/max(1,len(batches)))
        current=copy.deepcopy(prompt)
        current['whole_song_structure']=overview
        current['measurements']['families']=batch
        current['measurements']['instruments']={part:[{k:v for k,v in section.items() if k!='onset_strength'} for section in sections if section['family'] in batch] for part,sections in measured['instruments'].items()}
        current['rules'].append('Return motifs only for the supplied families in this batch; use whole_song_structure for context. Give a whole-song hype_keep decision.')
        body={'model':model,'max_tokens':8000,'messages':[{'role':'user','content':json.dumps(current,separators=(',',':'))}]}
        response=json.loads(bridge.api('/v1/messages',json.dumps(body)))
        if response.get('stop_reason')=='max_tokens':raise ValueError('AI analysis was truncated. Retry without AI; no incomplete chart was saved.')
        raw=''.join(item.get('text','') for item in response.get('content',[]) if item.get('type')=='text').strip()
        if raw.startswith('```'):raw=raw.split('\n',1)[1].rsplit('```',1)[0]
        partial=json.loads(raw)
        validate_plan(partial,{'families':batch})
        plan['motifs'].extend(partial['motifs'])
        if index==0:plan['hype_keep']=partial.get('hype_keep')
    result=apply_plan(charts,measured,plan)
    keep=plan.get('hype_keep')
    if not isinstance(keep,list) or any(not isinstance(k,str) or k not in candidates for k in keep) or len(keep)!=len(set(keep)):
        raise ValueError('Claude returned unsupported hype windows')
    # Recheck density after edits; a hype section must still fit the resulting chart.
    rescored=detect_hype(audio,{LABELS[p.stem]:p for p in Path(stems).glob('*.wav') if p.stem in LABELS},charts=result)
    approved={'global':[], 'instruments':{}}
    for key in keep:
        candidate=candidates[key];scope=candidate['scope']
        checks=rescored.get('global',[]) if scope=='global' else rescored.get('instruments',{}).get(scope,[])
        if not any(min(c['end'],candidate['end'])-max(c['start'],candidate['start']) > .5*(candidate['end']-candidate['start']) for c in checks):continue
        section={k:v for k,v in candidate.items() if k!='scope'}
        if scope=='global':approved['global'].append(section)
        else:approved['instruments'].setdefault(scope,[]).append(section)
    # Validate the complete chart representation before the importer publishes anything.
    from song_card import validate
    samples,sample_rate=read_wav(audio)
    duration=len(samples)/sample_rate
    validate({'schema':1,'category':'YouTube','source':'https://www.youtube.com/watch?v=dQw4w9WgXcQ','duration':duration,'charts':result})
    job.update('AI phrase plan validated; measuring hype against the edited charts…',92)
    return result,approved
