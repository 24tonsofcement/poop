"""PNG thumbnail + bounded private ancillary chunk; no audio or video payload."""
import copy
import hashlib
import json
import math
from pathlib import Path
import struct
import zlib

SIGNATURE = b'\x89PNG\r\n\x1a\n'
CHUNK = b'pfCH'  # ancillary, private, reserved bit valid, unsafe-to-copy
MAX_FILE = 32 * 1024 * 1024
MAX_JSON = 64 * 1024 * 1024


def canonical(data):
    def normalize(value):
        if isinstance(value, dict): return {k: normalize(v) for k, v in value.items()}
        if isinstance(value, list): return [normalize(v) for v in value]
        if type(value) is float and math.isfinite(value) and value.is_integer(): return int(value)
        return value
    return json.dumps(normalize(data), ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def validate(pack):
    from sources import CATEGORIES, source_info
    if not isinstance(pack, dict) or pack.get('schema') != 1 or pack.get('category') not in CATEGORIES:
        raise ValueError('This card must contain a supported online song.')
    category, source = source_info(pack.get('source', ''))
    if category != pack['category']: raise ValueError('Card category does not match its source.')
    duration = pack.get('duration')
    if not number(duration) or not 0 < duration <= 900:
        raise ValueError('Invalid song duration.')
    charts = pack.get('charts')
    if not isinstance(charts, dict) or not 1 <= len(charts) <= 16:
        raise ValueError('Invalid instrument charts.')
    count = 0
    for part, difficulties in charts.items():
        if not isinstance(part, str) or not 1 <= len(part) <= 100 or not isinstance(difficulties, dict) or not 1 <= len(difficulties) <= 16:
            raise ValueError('Invalid chart group.')
        for difficulty, notes in difficulties.items():
            if not isinstance(difficulty, str) or not 1 <= len(difficulty) <= 100 or not isinstance(notes, list) or len(notes) > 100000:
                raise ValueError('Invalid difficulty.')
            previous = -1
            for note in notes:
                if not isinstance(note, dict): raise ValueError('Invalid note.')
                at, end, lane = note.get('t'), note.get('end'), note.get('lane')
                if not number(at) or not number(end) or not previous <= at <= end <= duration + 5 or at < 0 or not number(lane) or lane != int(lane) or not 0 <= lane <= 3:
                    raise ValueError('Invalid note timing or lane.')
                previous = at
            count += len(notes)
    if not 0 < count <= 500000:
        raise ValueError('Card has no notes or too many notes.')
    for field in ['title', 'artist', 'generator', 'credits']:
        if field in pack and (not isinstance(pack[field], str) or len(pack[field]) > 2000):
            raise ValueError('Invalid song text.')
    timing = pack.get('timing', [])
    if not isinstance(timing, list) or len(timing) > 10000: raise ValueError('Invalid timing map.')
    for point in timing:
        if not isinstance(point, dict) or not number(point.get('t')) or not number(point.get('beat_length')) or point['beat_length'] <= 0 or not number(point.get('meter')) or point['meter'] != int(point['meter']) or not 1 <= point['meter'] <= 32:
            raise ValueError('Invalid timing point.')
    hype = pack.get('hype', {})
    if not isinstance(hype, dict) or not isinstance(hype.get('instruments', {}), dict): raise ValueError('Invalid hype metadata.')
    for sections in [hype.get('global', []), *hype.get('instruments', {}).values()]:
        if not isinstance(sections, list) or len(sections) > 10000: raise ValueError('Invalid hype sections.')
        for section in sections:
            if not isinstance(section, dict) or not all(number(section.get(k)) for k in ['start', 'end', 'confidence']) or not 0 <= section['start'] < section['end'] <= duration + 5:
                raise ValueError('Invalid hype section.')
    keep = ['schema', 'title', 'artist', 'duration', 'charts', 'timing', 'hype', 'generator', 'credits']
    result = {key: copy.deepcopy(pack[key]) for key in keep if key in pack}
    result.update(category=category, source=source, audio='audio.wav')
    result.setdefault('title', 'YouTube song')
    result.setdefault('artist', 'Unknown')
    canonical(result)  # Reject non-finite values in optional metadata too.
    return result


def chunks(raw):
    if len(raw) > MAX_FILE or not raw.startswith(SIGNATURE): raise ValueError('Not a supported PNG song card.')
    offset = 8
    first = True
    while offset + 12 <= len(raw):
        length, kind = struct.unpack('>I4s', raw[offset:offset + 8])
        finish = offset + length + 12
        if finish > len(raw): raise ValueError('Truncated PNG.')
        data = raw[offset + 8:finish - 4]
        crc = struct.unpack('>I', raw[finish - 4:finish])[0]
        if zlib.crc32(kind + data) & 0xffffffff != crc: raise ValueError('PNG checksum failed; resend the original file.')
        if first:
            if kind != b'IHDR' or length != 13: raise ValueError('Missing PNG header.')
            w, h = struct.unpack('>II', data[:8])
            if not 0 < w <= 4096 or not 0 < h <= 4096: raise ValueError('Thumbnail dimensions are too large.')
            first = False
        yield kind, data, raw[offset:finish]
        offset = finish
        if kind == b'IEND':
            if length or offset != len(raw): raise ValueError('Invalid PNG ending.')
            return
    raise ValueError('Incomplete PNG.')


def read_bounded(path):
    with Path(path).open('rb') as stream:
        data = stream.read(MAX_FILE + 1)
    if len(data) > MAX_FILE: raise ValueError('Song card exceeds 32 MB.')
    return data


def encode(thumbnail, pack):
    payload = canonical({'format': 'pulse-four-chart-card', 'version': 1, 'song': validate(pack)})
    if len(payload) > MAX_JSON: raise ValueError('Charts are too large.')
    compressed = zlib.compress(payload, 9)
    chunk = struct.pack('>I', len(compressed)) + CHUNK + compressed + struct.pack('>I', zlib.crc32(CHUNK + compressed) & 0xffffffff)
    output = bytearray(SIGNATURE)
    for kind, data, raw in chunks(thumbnail):
        if kind == CHUNK: continue
        if kind == b'IEND': output.extend(chunk)
        output.extend(raw)
    if len(output) > MAX_FILE: raise ValueError('Song card exceeds 32 MB.')
    return bytes(output)


def decode(raw):
    found = [data for kind, data, _ in chunks(raw) if kind == CHUNK]
    if len(found) != 1: raise ValueError('No intact Pulse Four chart in this PNG. Send the original as a file, not a photo.')
    decoder = zlib.decompressobj()
    payload = decoder.decompress(found[0], MAX_JSON + 1)
    if len(payload) > MAX_JSON or not decoder.eof or decoder.unused_data:
        raise ValueError('Invalid or oversized chart payload.')
    envelope = json.loads(payload)
    if not isinstance(envelope, dict) or envelope.get('format') != 'pulse-four-chart-card' or envelope.get('version') != 1:
        raise ValueError('Unsupported song-card version.')
    song = validate(envelope.get('song'))
    song['id'] = 'card-' + hashlib.sha256(canonical(song)).hexdigest()[:24]
    return song


def render_card(thumbnail, title):
    """Retain the thumbnail and append a readable cabinet-style data label."""
    import io
    from PIL import Image, ImageDraw, ImageFont
    list(chunks(thumbnail))
    with Image.open(io.BytesIO(thumbnail)) as image:
        image.load()
        art = image.convert('RGB')
    art.thumbnail((960, 720))
    width = max(480, art.width)
    canvas = Image.new('RGB', (width, art.height + 142), '#121d2e')
    canvas.paste(art, ((width - art.width) // 2, 0))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, art.height, width, art.height + 4), fill='#ffbd55')
    heading = ImageFont.load_default(size=22)
    for font_path in ['C:/Windows/Fonts/meiryo.ttc', 'C:/Windows/Fonts/msgothic.ttc', '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc']:
        if Path(font_path).is_file():
            heading = ImageFont.truetype(font_path, 22)
            break
    caption = ImageFont.load_default(size=15)
    draw.text((18, art.height + 16), 'DATA CARD', font=caption, fill='#ffbd55')
    words = str(title).split()
    lines = ['']
    for word in words:
        candidate = (lines[-1] + ' ' + word).strip()
        if draw.textlength(candidate, font=heading) > width - 36 and lines[-1]: lines.append(word)
        else: lines[-1] = candidate
    lines = lines[:2]
    for i, line in enumerate(lines):
        while draw.textlength(line, font=heading) > width - 52: line = line[:-1]
        draw.text((18, art.height + 43 + i * 27), line, font=heading, fill='#e4edf9')
    draw.text((18, art.height + 113), 'CHARTS + SOURCE LINK / KEEP ORIGINAL PNG', font=caption, fill='#9aabc4')
    output = io.BytesIO()
    canvas.save(output, format='PNG')
    return output.getvalue()
