"""Explicit supported music link providers; provider categories follow the actual audio source."""
import re
import urllib.parse

CATEGORIES = ('YouTube', 'SoundCloud')


def source_info(url):
    p=urllib.parse.urlparse(url.strip())
    if p.scheme!='https' or p.username or p.password or p.port:
        raise ValueError('Use an HTTPS song link from YouTube or SoundCloud.')
    host=(p.hostname or '').lower()
    if host in ('youtube.com','www.youtube.com','m.youtube.com','music.youtube.com','youtu.be'):
        from worker import validate_youtube
        return 'YouTube', validate_youtube(url)
    parts=[part for part in p.path.split('/') if part]
    if host=='on.soundcloud.com' and len(parts)==1 and re.fullmatch(r'[A-Za-z0-9]+',parts[0]):
        return 'SoundCloud', 'https://on.soundcloud.com/'+parts[0]
    if host in ('soundcloud.com','www.soundcloud.com','m.soundcloud.com') and len(parts)==2 and parts[0] not in ('discover','charts','you','search') and parts[1] not in ('sets','tracks','albums','reposts','popular-tracks'):
        return 'SoundCloud', urllib.parse.urlunparse(('https','soundcloud.com',p.path,'',p.query,''))
    raise ValueError('Use an individual supported song link, not an album, playlist or profile.')

