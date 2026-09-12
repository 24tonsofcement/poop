"""Bounded library maintenance; links and paths outside the library are rejected."""
import json
from pathlib import Path
import re
import shutil


def linked(path):
    return path.is_symlink() or bool(getattr(path.lstat(), "st_file_attributes", 0) & 0x400)


def files(folder):
    for child in folder.iterdir():
        if linked(child): continue
        if child.is_dir(): yield from files(child)
        elif child.is_file(): yield child


def cover_cache(pack, covers):
    import urllib.parse
    parsed=urllib.parse.urlparse(str(pack.get('source','')))
    identity=urllib.parse.parse_qs(parsed.query).get('v',[''])[0]
    if parsed.hostname=='www.youtube.com' and re.fullmatch(r'[A-Za-z0-9_-]{11}',identity):
        return Path(covers)/(identity+'.jpg')
    return None


def scan(library, covers):
    result=[]
    for folder in sorted(Path(library).iterdir()):
        if not folder.is_dir() or linked(folder) or folder.resolve().parent != Path(library).resolve() or folder.name.startswith('.'): continue
        try:
            pack=json.loads((folder/'song.json').read_text(encoding='utf-8'))
            sizes={str(p.relative_to(folder)):p.stat().st_size for p in files(folder)}
            thumb=sizes.get('thumbnail.jpg',0)
            cached=cover_cache(pack,covers)
            cache_size=cached.stat().st_size if cached and cached.is_file() and not pack.get('thumbnail_disabled') else 0
            result.append(dict(path=str(folder),title=str(pack.get('title','Song')),category=str(pack.get('category','Unknown')),
                bytes=sum(sizes.values())+cache_size,background_bytes=sizes.get('background.png',0)+sizes.get('background.ogv',0),thumbnail_bytes=thumb+cache_size))
        except (OSError,ValueError): continue
    return result


def remove(library, covers, source, action):
    from worker import atomic_json
    library=Path(library).resolve(); original=Path(source);folder=original.resolve()
    if linked(original) or folder.parent!=library or not (folder/'song.json').is_file():
        raise ValueError('Choose an installed song inside the song library.')
    if action not in ('song','background','thumbnail'): raise ValueError('Unknown cleanup action')
    # Reject nested links before recursive deletion, including Windows junctions.
    for path in folder.rglob('*'):
        if linked(path) or path.resolve().is_relative_to(folder) is False:
            raise ValueError('Song contains linked files; manage it manually.')
    if action=='song':
        pack=json.loads((folder/'song.json').read_text(encoding='utf-8'))
        cached=cover_cache(pack,covers)
        shutil.rmtree(folder)
        if cached:
            used=False
            for metadata in library.glob('*/song.json'):
                try:
                    other=json.loads(metadata.read_text(encoding='utf-8'))
                    if not other.get('thumbnail_disabled') and cover_cache(other,covers)==cached: used=True
                except (ValueError,OSError): continue
            if not used: cached.unlink(missing_ok=True)
        return
    metadata=folder/'song.json';pack=json.loads(metadata.read_text(encoding='utf-8'))
    if action=='background':
        pack.pop('video',None);pack.pop('background_image',None)
        atomic_json(metadata,pack)
        for name in ('background.ogv','background.png'): (folder/name).unlink(missing_ok=True)
    else:
        pack['thumbnail_disabled']=True
        atomic_json(metadata,pack)
        (folder/'thumbnail.jpg').unlink(missing_ok=True)
        cached=cover_cache(pack,covers)
        if cached: cached.unlink(missing_ok=True)
