"""Conservative storyboard still-image detection before video download.

Sparse previews cannot prove absence of brief motion. Missing coverage, changing
frames or malformed previews always fall back to the normal video downloader.
"""
import io
import math
import urllib.parse
import urllib.request
import numpy as np
from PIL import Image


def fetch_image(url):
    parsed=urllib.parse.urlparse(url)
    if parsed.scheme != 'https' or not (parsed.hostname or '').endswith('.ytimg.com'):
        raise ValueError('Unexpected storyboard host')
    with urllib.request.urlopen(url, timeout=10) as response:
        raw=response.read(8*1024*1024+1)
    if len(raw)>8*1024*1024: raise ValueError('Storyboard too large')
    image=Image.open(io.BytesIO(raw))
    if image.width*image.height>16_000_000: raise ValueError('Storyboard dimensions too large')
    image.load()
    return image.convert('RGB')


def still_image(info, fetch=fetch_image):
    duration=float(info.get('duration') or 0)
    choices=[f for f in info.get('formats',[]) if f.get('protocol')=='mhtml' and f.get('fragments')]
    for fmt in sorted(choices,key=lambda f:-float(f.get('width',0))):
        width,height=int(fmt.get('width',0)),int(fmt.get('height',0))
        cols,rows=int(fmt.get('columns',0)),int(fmt.get('rows',0))
        fps=float(fmt.get('fps') or 0); count=round(duration*fps)
        if not (80<=width<=1024 and 45<=height<=1024 and 0<cols<=25 and 0<rows<=25): continue
        if fps<.2 or count<12 or count>4500: continue
        fragments=fmt['fragments']
        if len(fragments)!=math.ceil(count/(rows*cols)) or len(fragments)>40: continue
        baseline=None; first=None; seen=0
        for fragment in fragments:
            sheet=fetch(fragment['url'])
            if sheet.size != (width*cols,height*rows): return None
            for index in range(min(cols*rows,count-seen)):
                x=(index%cols)*width;y=(index//cols)*height
                tile=sheet.crop((x,y,x+width,y+height))
                pixels=np.asarray(tile.resize((64,36)),dtype=float)
                if baseline is None: baseline=pixels;first=tile.copy()
                delta=np.abs(pixels-baseline)
                if float(delta.mean())>1.3 or float(np.percentile(delta,99))>12: return None
                seen+=1
        if seen==count:
            # Use a sharper thumbnail only if its composition matches the frames.
            for thumb in sorted(info.get('thumbnails',[]),key=lambda t:-(t.get('width') or 0)):
                try:
                    candidate=fetch(thumb['url'])
                    delta=np.abs(np.asarray(candidate.resize((64,36)),dtype=float)-baseline)
                    if delta.mean()<4: return candidate
                except (OSError,ValueError): continue
            return first
    return None
