"""Pulse Four import worker: osu!mania and YouTube -> portable song folders."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
import urllib.parse
import uuid
import zipfile
# This lightweight command also works with older persistent launchers.
if __name__ == '__main__' and len(sys.argv) == 3 and sys.argv[1] == '--cleanup-old-versions':
    from install_cleanup import cleanup_installed
    cleanup_installed(sys.argv[2])
    raise SystemExit(0)

from charting import generate_charts
from sources import CATEGORIES, source_info
from instruments import MODEL, SOURCES, LABELS, selected_paths
from hype import detect_hype
from timing import estimate_timing, parse_timing_points

BASE = Path(sys.executable).parent if getattr(sys, 'frozen', False) else Path(__file__).resolve().parent
TOOLS = BASE / 'tools'
os.environ['PATH'] = str(TOOLS) + os.pathsep + os.environ.get('PATH', '')
os.environ.setdefault('TORCH_HOME', str(BASE / 'models'))
ACTIVE_MODE = 'arcade'
MAX_SECONDS = 15 * 60
MAX_ARCHIVE_BYTES = 1024 * 1024 * 1024

def atomic_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    os.replace(temp, path)

class Job:
    def __init__(self, result):
        self.result = Path(result)
        self.cancel = self.result.with_suffix('.cancel')
    def update(self, message, progress=0):
        if self.cancel.exists():
            raise RuntimeError('Import cancelled.')
        atomic_json(self.result, {'state': 'working', 'message': message, 'progress': progress})
    def run(self, args, message, progress=0):
        self.update(message, progress)
        with tempfile.TemporaryFile() as log:
            process = subprocess.Popen([str(a) for a in args], stdout=log, stderr=log,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
            start = time.monotonic()
            while process.poll() is None:
                if self.cancel.exists() or time.monotonic() - start > 7200:
                    if os.name == 'nt':
                        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
                    else:
                        process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                    raise RuntimeError('Import cancelled or timed out.')
                time.sleep(.2)
            if process.returncode:
                log.seek(0, 2)
                size = log.tell()
                log.seek(max(0, size - 5000))
                raise RuntimeError(message + '\n' + log.read().decode('utf-8', 'replace'))

def binary(name):
    local = TOOLS / (name + ('.exe' if os.name == 'nt' else ''))
    found = str(local) if local.exists() else shutil.which(name)
    if not found:
        raise RuntimeError(f'{name} is missing. Use the full Windows build or install the importer dependencies.')
    return found

def safe_child(root, relative):
    # osu files and archives are untrusted. Never allow path traversal.
    relative = relative.strip().strip('"').replace('\\', '/')
    if ':' in relative or PurePosixPath(relative).is_absolute():
        raise ValueError('Absolute paths in beatmaps are not supported')
    result = (Path(root) / relative).resolve()
    if not result.is_relative_to(Path(root).resolve()):
        raise ValueError('Path escapes beatmap directory')
    return result

def unpack_osz(path, dest):
    with zipfile.ZipFile(path) as archive:
        if len(archive.infolist()) > 5000 or sum(i.file_size for i in archive.infolist()) > MAX_ARCHIVE_BYTES:
            raise ValueError('Archive is too large (limit: 1 GB / 5000 entries)')
        for info in archive.infolist():
            out = safe_child(dest, info.filename)
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Archive symlinks are not supported')
            if info.is_dir():
                out.mkdir(parents=True, exist_ok=True)
            else:
                out.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(info) as src, out.open('wb') as dst:
                    shutil.copyfileobj(src, dst)

def parse_osu(path):
    section, meta, objects, timing_lines = '', {}, [], []
    for raw in Path(path).read_text(encoding='utf-8-sig', errors='replace').splitlines():
        line = raw.strip()
        if not line or line.startswith('//'):
            continue
        if line.startswith('[') and line.endswith(']'):
            section = line[1:-1]
        elif section == 'TimingPoints':
            timing_lines.append(line)
        elif section == 'HitObjects':
            objects.append(line)
        elif ':' in line:
            k, v = line.split(':', 1)
            meta[section + '.' + k.strip()] = v.strip()
    if meta.get('General.Mode') != '3':
        raise ValueError('Only osu!mania maps (Mode:3) are supported')
    if float(meta.get('Difficulty.CircleSize', '0')) != 4:
        raise ValueError('Only native 4-key osu!mania maps are supported')
    notes = []
    for line in objects:
        p = line.split(',')
        if len(p) < 5:
            raise ValueError('Malformed hit object')
        x, t, kind = int(p[0]), int(p[2]) / 1000, int(p[3])
        if not 0 <= x <= 512 or t < 0 or not kind & (1 | 128):
            raise ValueError('Invalid mania hit object')
        end = int(p[5].split(':')[0]) / 1000 if kind & 128 and len(p) > 5 else t
        if end < t:
            raise ValueError('Hold ends before it starts')
        notes.append({'t': t, 'lane': min(3, x * 4 // 512), 'end': end})
    notes.sort(key=lambda n: (n['t'], n['lane']))
    last_end = [-1.] * 4
    for n in notes:
        if n['t'] <= last_end[n['lane']]:
            raise ValueError('Overlapping notes in one lane are not supported')
        last_end[n['lane']] = n['end']
    if not notes:
        raise ValueError('Beatmap contains no notes')
    meta["timing"] = parse_timing_points(timing_lines)
    return meta, notes

def convert_audio(source, out, job, progress=20):
    job.run([binary('ffmpeg'), '-nostdin', '-y', '-i', source, '-vn', '-ac', '2', '-ar', '44100', '-c:a', 'pcm_s16le', out],
            'Converting audio…', progress)
    import wave
    with wave.open(str(out)) as w:
        duration = w.getnframes() / w.getframerate()
    if duration > MAX_SECONDS:
        raise ValueError('Songs are limited to 15 minutes')
    return duration

def song_folder_name(pack):
    import re
    title = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', str(pack.get('title', 'Song'))).strip(' .')[:70].rstrip(' .') or 'Song'
    if title.split('.')[0].upper() in {'CON','PRN','AUX','NUL',*[f'COM{i}' for i in range(1,10)],*[f'LPT{i}' for i in range(1,10)]}: title = '_' + title
    return title + ' [' + hashlib.sha256(str(pack['id']).encode()).hexdigest()[:10] + ']'


def existing_pack(library, identity):
    for metadata in library.glob('*/song.json'):
        if metadata.parent.name.startswith('.'): continue
        try:
            if json.loads(metadata.read_text(encoding='utf-8')).get('id') == identity:
                return metadata.parent
        except (ValueError, OSError): continue
    return None


def commit_pack(work, library, pack):
    if ACTIVE_MODE == 'laser':
        from laser_charting import attach
        attach(work / 'audio.wav', pack)
    existing = existing_pack(library, pack['id'])
    if existing is not None: return existing
    atomic_json(work / 'song.json', pack)
    target = library / song_folder_name(pack)
    # Content-keyed imports are idempotent; a completed existing import wins.
    if target.exists():
        if (target / 'song.json').exists():
            return target
        raise ValueError('Incomplete destination already exists; remove it before retrying')
    shutil.move(str(work), str(target))
    return target

def import_osu(source, library, temp, job):
    folder = temp / 'extracted'
    if source.suffix.lower() == '.osz':
        folder.mkdir()
        unpack_osz(source, folder)
        files = sorted(folder.rglob('*.osu'))
    else:
        files = [source]
    groups, skipped = {}, []
    for f in files:
        try:
            meta, notes = parse_osu(f)
            audio = safe_child(f.parent, meta.get('General.AudioFilename', ''))
            if not audio.is_file():
                raise ValueError('Referenced audio is missing; keep it beside the .osu file or import .osz')
            group = groups.setdefault(str(audio), {'meta': meta, 'charts': {}, 'timing': {}})
            version = meta.get('Metadata.Version', 'Original')
            if version in group['charts']:
                version += ' ' + f.stem
            group['charts'][version] = notes
            group['timing'][version] = meta['timing']
        except (ValueError, IndexError) as error:
            skipped.append(f.name + ': ' + str(error))
    if not groups:
        raise ValueError('\n'.join(skipped) or 'No .osu files found')
    imported = []
    for i, (audio, group) in enumerate(groups.items()):
        work = temp / ('pack' + str(i))
        work.mkdir()
        duration = convert_audio(audio, work / 'audio.wav', job)
        meta = group['meta']
        with open(audio, 'rb') as audio_file:
            audio_digest = hashlib.file_digest(audio_file, 'sha256').hexdigest()
        pack_id = 'osu-' + hashlib.sha256((audio_digest + json.dumps(group['charts'], sort_keys=True)).encode()).hexdigest()[:20]
        pack = {'schema': 1, 'id': pack_id, 'category': 'osu!mania',
                'title': meta.get('Metadata.Title', source.stem), 'artist': meta.get('Metadata.Artist', 'Unknown'),
                'audio': 'audio.wav', 'duration': duration, 'charts': {'Original': group['charts']}, 'timing': {'Original': group['timing']},
                'source': 'osu!mania', 'credits': meta.get('Metadata.Creator', '')}
        if max(n['end'] for notes in group['charts'].values() for n in notes) > duration + 2:
            raise ValueError('Beatmap notes extend beyond its audio')
        pack['hype'] = detect_hype(work / 'audio.wav', charts=pack.get('charts'))
        imported.append(str(commit_pack(work, library, pack)))
    return imported, skipped

def validate_youtube(url):
    p = urllib.parse.urlparse(url)
    if p.scheme != 'https' or p.hostname not in {'youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be'} or p.username or p.password or p.port:
        raise ValueError('Enter an HTTPS YouTube video link')
    query = urllib.parse.parse_qs(p.query)
    video = p.path.strip('/') if p.hostname == 'youtu.be' else (query.get('v', [''])[0] if p.path == '/watch' else p.path.split('/')[-1] if p.path.startswith(('/shorts/', '/embed/')) else '')
    import re
    if not re.fullmatch(r'[A-Za-z0-9_-]{11}', video):
        raise ValueError('Use an individual YouTube video, not a playlist or channel')
    return 'https://www.youtube.com/watch?v=' + video

def separate_stems(audio_path, temp, job):
    separated = temp / 'stems'
    if getattr(sys, 'frozen', False):
        command = [sys.executable, '--separate', str(audio_path), str(separated)]
    else:
        command = [sys.executable, str(Path(__file__).resolve()), '--separate', str(audio_path), str(separated)]
    job.run(command, 'Separating vocals, drums, bass, guitar, piano and other instruments (CPU; may take several minutes)…', 30)
    return separated

def instrument_charts(audio_path, temp, job):
    if ACTIVE_MODE == 'laser':
        job.update('Measuring full-song button, FX and laser patterns…', 60)
        return {'Full mix': generate_charts(audio_path, instrument='mixed')}
    separated = separate_stems(audio_path, temp, job)
    charts = {}
    parts = selected_paths(audio_path, separated / MODEL / audio_path.stem)
    for index, (stem, stem_path) in enumerate(parts.items()):
        job.update('Generating charts: ' + LABELS[stem], 60 + index * 9)
        generated = generate_charts(stem_path, allow_holds=stem != 'drums', instrument=stem)
        if any(generated.values()): charts[LABELS[stem]] = generated
    if not any(notes for diffs in charts.values() for notes in diffs.values()):
        raise ValueError('No playable onsets detected')
    return charts

def song_hype(audio_path, temp, job, charts=None):
    job.update('Matching energy lifts and instrument solos with chart activity...', 93)
    stems = temp / 'stems' / MODEL / audio_path.stem
    paths = {LABELS[name]: stems / (name + '.wav') for name in SOURCES if (stems / (name + '.wav')).exists()}
    if charts and 'Accompaniment' in charts and 'Other instruments' in paths:
        paths['Accompaniment'] = paths.pop('Other instruments')
    return detect_hype(audio_path, paths, charts=charts)

def encode_background(source, output, job):
    job.run([binary('ffmpeg'), '-nostdin', '-y', '-i', source, '-t', str(MAX_SECONDS),
             '-an', '-vf', 'scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=24',
             '-c:v', 'libtheora', '-q:v', '5', '-pix_fmt', 'yuv420p', output],
            'Preparing dimmed video background...', 94)
    if not output.is_file() or output.stat().st_size < 100:
        raise ValueError('Video conversion produced no playable background')


def download_background(url, temp, job):
    url = validate_youtube(url)
    info_file = temp / 'download.info.json'
    try:
        if not info_file.exists():
            job.run([binary('yt-dlp'), '--ignore-config', '--no-playlist', '--skip-download',
                     '--write-info-json', '--js-runtimes', 'deno:' + binary('deno'),
                     '-o', str(temp / 'download.%(ext)s'), '--', url], 'Checking background motion...', 91)
        from static_background import still_image
        still = still_image(json.loads(info_file.read_text(encoding='utf-8')))
        if still is not None:
            output = temp / 'background.png'
            still.save(output, format='PNG')
            job.update('Still background detected; skipping video download.', 94)
            return output
    except (RuntimeError, ValueError, OSError, KeyError, TypeError):
        if getattr(job, 'cancel', None) is not None and job.cancel.exists(): raise
    job.run([binary('yt-dlp'), '--ignore-config', '--no-playlist', '--no-progress', '--no-warnings',
             '--js-runtimes', 'deno:' + binary('deno'), '--socket-timeout', '30', '--retries', '2',
             '--match-filter', 'duration <= 900 & !is_live', '--max-filesize', '200M',
             '-f', 'bestvideo[height<=480]/best[height<=480]/worstvideo/worst',
             '-o', str(temp / 'video-source.%(ext)s'), '--', url], 'Downloading video background...', 92)
    sources = [p for p in temp.glob('video-source.*') if p.suffix not in {'.part', '.ytdl', '.json'}]
    if len(sources) != 1:
        raise ValueError('No complete video stream was available')
    output = temp / 'background.ogv'
    encode_background(sources[0], output, job)
    return output


def optional_background(url, destination, temp, job):
    try:
        video = download_background(url, temp, job)
        shutil.copy2(video, destination.with_suffix(video.suffix))
        return []
    except (RuntimeError, ValueError, OSError) as error:
        if getattr(job, 'cancel', None) is not None and job.cancel.exists():
            raise
        return ['Background video unavailable; the song remains playable. ' + str(error)[-900:]]


def attach_video(source, library, temp, job):
    folder = Path(source).resolve()
    if not folder.is_relative_to(library.resolve()) or folder == library.resolve():
        raise ValueError('Choose a song in the game song folder')
    metadata = folder / 'song.json'
    original = metadata.read_bytes()
    pack = json.loads(original)
    if pack.get('category') != 'YouTube':
        raise ValueError('Only YouTube songs support video downloads')
    video = download_background(pack.get('source', ''), temp, job)
    job.update('Saving video background...', 99)
    if metadata.read_bytes() != original:
        raise ValueError('Song changed while the video was downloading; retry')
    # Install the finished video, then publish its filename in song metadata.
    name = 'background' + video.suffix
    shutil.copy2(video, folder / (name + '.partial'))
    os.replace(folder / (name + '.partial'), folder / name)
    pack.pop('video', None); pack.pop('background_image', None)
    pack['background_image' if video.suffix == '.png' else 'video'] = name
    atomic_json(metadata, pack)
    (folder / ('background.ogv' if video.suffix == '.png' else 'background.png')).unlink(missing_ok=True)
    return [str(folder)], []

def download_youtube_audio(url, temp, job):
    provider, url = source_info(url)
    work = temp / 'pack'
    work.mkdir()
    job.run([binary('yt-dlp'), '--ignore-config', '--no-playlist', '--no-progress', '--no-warnings',
             '--js-runtimes', 'deno:' + binary('deno'), '--socket-timeout', '30', '--retries', '2',
             '--match-filter', 'duration <= 900 & !is_live', '--max-filesize', '200M',
             '--ffmpeg-location', str(Path(binary('ffmpeg')).parent), '-f', 'bestaudio/best',
             '--write-info-json', '-o', str(temp / 'download.%(ext)s'), '--', url], 'Downloading ' + provider + ' audio…', 5)
    info_file = temp / 'download.info.json'
    if not info_file.exists():
        raise ValueError('Video unavailable, live, or longer than 15 minutes')
    info = json.loads(info_file.read_text(encoding='utf-8'))
    if info.get('_type') in ('playlist', 'multi_video') or info.get('entries') is not None:
        raise ValueError('Import one song at a time; playlists and profiles are unsupported.')
    audio = [p for p in temp.glob('download.*') if p.suffix not in {'.json', '.part', '.ytdl'}]
    if len(audio) != 1:
        raise ValueError('Audio download did not produce a single complete file')
    duration = convert_audio(audio[0], work / 'audio.wav', job, 20)
    return work, duration, info


def save_artwork(info, work):
    # Keep provider artwork per song so deleting one cover does not affect others.
    import io
    import urllib.request
    from PIL import Image
    url = str(info.get('thumbnail') or '')
    host = urllib.parse.urlparse(url).hostname or ''
    allowed = ('ytimg.com', 'sndcdn.com')
    if not url.startswith('https://') or not any(host == domain or host.endswith('.'+domain) for domain in allowed): return
    try:
        with urllib.request.urlopen(url, timeout=8) as response: raw=response.read(4*1024*1024+1)
        if len(raw)>4*1024*1024: return
        with Image.open(io.BytesIO(raw)) as image:
            if image.width*image.height>16_000_000: return
            image.thumbnail((960,960))
            image.convert('RGB').save(work/'thumbnail.jpg', quality=85)
    except (OSError, ValueError): pass


def import_youtube(url, library, temp, job):
    provider, url = source_info(url)
    work, duration, info = download_youtube_audio(url, temp, job)
    charts = instrument_charts(work / 'audio.wav', temp, job)
    pack = {'schema': 1, 'id': ('yt-' + info['id']) if provider == 'YouTube' else provider.lower() + '-' + hashlib.sha256(url.encode()).hexdigest()[:24], 'category': provider, 'title': info.get('title', 'YouTube import'),
            'artist': info.get('uploader', 'Unknown'), 'audio': 'audio.wav', 'duration': duration,
            'charts': charts, 'timing': estimate_timing(work / 'audio.wav'), 'source': url, 'generator': 'htdemucs_6s + adaptive instruments + evidence-based sustains v10'}
    pack['hype'] = song_hype(work / 'audio.wav', temp, job, pack.get('charts'))
    warnings = optional_background(url, work / 'background.ogv', temp, job) if provider == 'YouTube' else []
    save_artwork(info, work)
    if (work / 'background.ogv').is_file():
        pack['video'] = 'background.ogv'
    if (work / 'background.png').is_file(): pack['background_image'] = 'background.png'
    job.update('Saving generated charts…', 99)
    return [str(commit_pack(work, library, pack))], warnings

def import_card(source, library, temp, job):
    from song_card import decode, read_bounded
    pack = decode(read_bounded(source))
    target = existing_pack(library, pack['id'])
    if target is not None and (target / 'audio.wav').is_file():
        return [str(target)], []
    work, duration, info = download_youtube_audio(pack['source'], temp, job)
    if abs(duration - pack['duration']) > 0.5:
        raise ValueError('Source audio duration has changed; these shared charts may no longer sync. Import stopped.')
    warnings = optional_background(pack['source'], work / 'background.ogv', temp, job) if pack['category'] == 'YouTube' else []
    save_artwork(info, work)
    if (work / 'background.ogv').is_file(): pack['video'] = 'background.ogv'
    if (work / 'background.png').is_file(): pack['background_image'] = 'background.png'
    job.update('Saving the shared charts unchanged…', 99)
    return [str(commit_pack(work, library, pack))], warnings


def import_cards(sources, library, temp, job):
    """Import independently so one bad card cannot discard the rest of a batch."""
    if not isinstance(sources, list) or not sources or len(sources) > 500 or not all(isinstance(p,str) for p in sources):
        raise ValueError('Select between 1 and 500 PNG song cards.')
    resolved = [str(Path(p).resolve()) for p in sources]
    unique = list({os.path.normcase(p): p for p in resolved}.values())
    paths, warnings = [], []
    successful = 0
    cancelled = False
    for index, source in enumerate(unique):
        if getattr(job, 'cancel', None) is not None and job.cancel.exists():
            cancelled = True
            break
        label = f'Card {index+1}/{len(unique)} · {Path(source).name}: '
        class CardProgress:
            cancel = getattr(job, 'cancel', None)
            def update(self, message, progress=0):
                job.update(label+message, (index*100+progress)/len(unique))
            def run(self, args, message, progress=0):
                job.run(args, label+message, (index*100+progress)/len(unique))
        try:
            with tempfile.TemporaryDirectory(prefix='card-', dir=temp) as folder:
                imported, notes = import_card(source, library, Path(folder), CardProgress())
            paths.extend(path for path in imported if path not in paths)
            warnings.extend(Path(source).name + ': ' + note for note in notes)
            successful += 1
        except Exception as error:
            if getattr(job, 'cancel', None) is not None and job.cancel.exists():
                cancelled = True
                break
            warnings.append(Path(source).name + ': ' + str(error)[-1000:])
    message = f'Imported {successful}/{len(unique)} cards.'
    if cancelled: message += ' Batch cancelled; completed imports were kept.'
    elif successful < len(unique): message += ' Some cards could not be imported.'
    return paths, warnings, message


def export_card(request, job):
    from song_card import encode, decode, read_bounded, render_card
    job.update('Embedding charts into the thumbnail…', 30)
    output = Path(request['destination']).resolve()
    if output.suffix.lower() != '.png': raise ValueError('Choose a .png filename.')
    thumbnail = render_card(read_bounded(request['thumbnail']), request['song'].get('title', 'YouTube song'))
    data = encode(thumbnail, request['song'])
    temporary = output.with_name(output.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        temporary.write_bytes(data)
        decode(read_bounded(temporary))  # Verify embedded charts before committing.
        job.update('Saving song card…', 99)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    return [], []


def regenerate_song(source, library, temp, job):
    folder = Path(source).resolve()
    if not folder.is_relative_to(library.resolve()) or folder == library.resolve():
        raise ValueError('Choose a song in the game song folder')
    pack_file = folder / 'song.json'
    original = pack_file.read_bytes()
    pack = json.loads(original)
    if pack.get('category') not in CATEGORIES or pack.get('audio') != 'audio.wav':
        raise ValueError('Only generated online songs can be regenerated')
    audio_path = folder / 'audio.wav'
    if not audio_path.is_file():
        raise ValueError('Cached audio is missing')
    pack['charts'] = instrument_charts(audio_path, temp, job)
    if ACTIVE_MODE == 'laser':
        from laser_charting import attach
        pack.pop('laser_charts',None)
        attach(audio_path,pack)
    pack['timing'] = estimate_timing(audio_path)
    pack['hype'] = song_hype(audio_path, temp, job, pack.get('charts'))
    pack['generator'] = 'htdemucs_6s + adaptive instruments + evidence-based sustains v10'
    job.update('Saving updated charts...', 99)
    if pack_file.read_bytes() != original:
        raise ValueError('Song changed during generation; retry')
    # Preserve the last charts for manual recovery; audio and song identity stay put.
    atomic_json(folder / 'song.before-holds.json', json.loads(original))
    atomic_json(pack_file, pack)
    return [str(folder)], []

def analyze_song_hype(source, library, temp, job):
    folder = Path(source).resolve()
    if not folder.is_relative_to(library.resolve()) or folder == library.resolve():
        raise ValueError('Choose an imported song in the library')
    pack_file = folder / 'song.json'
    original = pack_file.read_bytes()
    pack = json.loads(original)
    if pack.get('audio') != 'audio.wav':
        raise ValueError('Unsupported song audio')
    audio = folder / 'audio.wav'
    if pack.get('category') in CATEGORIES:
        separate_stems(audio, temp, job)
        pack['hype'] = song_hype(audio, temp, job, pack.get('charts'))
    else:
        pack['hype'] = detect_hype(audio, charts=pack.get('charts'))
    if pack_file.read_bytes() != original:
        raise ValueError('Song changed during analysis; retry')
    atomic_json(pack_file, pack)
    return [str(folder)], []

def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--separate':
        from demucs.separate import main as separate
        separate(['-n', MODEL, '-d', 'cpu', '--shifts', '1', '-o', sys.argv[3], sys.argv[2]])
        return
    parser = argparse.ArgumentParser()
    parser.add_argument('--request', required=True)
    args = parser.parse_args()
    request = json.loads(Path(args.request).read_text(encoding='utf-8'))
    global ACTIVE_MODE
    ACTIVE_MODE = request.get('mode', 'arcade')
    if ACTIVE_MODE not in ('arcade','laser'):raise ValueError('Invalid game mode')
    job = Job(request['result'])
    try:
        library = Path(request['library']).resolve()
        library.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.import-', dir=library) as tmp:
            job.update('Preparing import…', 1)
            if request['kind'] in ('manage_list', 'manage_remove'):
                from song_manager import scan, remove
                covers = library.parent / 'covers'
                if request['kind'] == 'manage_remove': remove(library, covers, request['source'], request['action'])
                atomic_json(job.result, {'state': 'done', 'message': 'Song storage updated.', 'progress': 100, 'manager_rows': scan(library, covers)})
                return
            elif request['kind'] == 'card_batch':
                paths, warnings, message = import_cards(request.get('sources'), library, Path(tmp), job)
                atomic_json(job.result, {'state': 'done', 'message': message, 'progress': 100, 'paths': paths, 'warnings': warnings})
                return
            elif request['kind'] == 'card_import':
                paths, warnings = import_card(request['source'], library, Path(tmp), job)
            elif request['kind'] == 'card_export':
                paths, warnings = export_card(request, job)
            elif request['kind'] in ('youtube', 'link'):
                paths, warnings = import_youtube(request['source'], library, Path(tmp), job)
            elif request['kind'] == 'hype':
                paths, warnings = analyze_song_hype(request['source'], library, Path(tmp), job)
            elif request['kind'] == 'video':
                paths, warnings = attach_video(request['source'], library, Path(tmp), job)
            elif request['kind'] == 'regenerate':
                paths, warnings = regenerate_song(request['source'], library, Path(tmp), job)
            elif request['kind'] == 'osu':
                paths, warnings = import_osu(Path(request['source']).resolve(), library, Path(tmp), job)
            else:
                raise ValueError('Unknown import kind')
        if request['kind'] == 'card_export':
            request_path = Path(args.request).resolve()
            thumbnail_path = Path(request['thumbnail']).resolve()
            if thumbnail_path.parent == request_path.parent and thumbnail_path.name.startswith('card-thumbnail-'):
                thumbnail_path.unlink(missing_ok=True)
            if request_path.name.endswith('.request.json'):
                request_path.unlink(missing_ok=True)
        atomic_json(job.result, {'state': 'done', 'message': ('Song card exported: ' + request['destination']) if request['kind'] == 'card_export' else 'Import complete', 'progress': 100, 'paths': paths, 'warnings': warnings, 'exported_path': str(Path(request['destination']).resolve()) if request['kind'] == 'card_export' else ''})
    except Exception as error:
        atomic_json(job.result, {'state': 'error', 'message': str(error), 'progress': 0})
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    import multiprocessing
    multiprocessing.freeze_support()
    main()

