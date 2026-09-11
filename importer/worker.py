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
from charting import generate_charts
from hype import detect_hype
from timing import estimate_timing, parse_timing_points

BASE = Path(sys.executable).parent if getattr(sys, 'frozen', False) else Path(__file__).resolve().parent
TOOLS = BASE / 'tools'
os.environ['PATH'] = str(TOOLS) + os.pathsep + os.environ.get('PATH', '')
os.environ.setdefault('TORCH_HOME', str(BASE / 'models'))
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

def commit_pack(work, library, pack):
    atomic_json(work / 'song.json', pack)
    target = library / pack['id']
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
        pack['hype'] = detect_hype(work / 'audio.wav')
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
    job.run(command, 'Separating drums, bass, vocals and accompaniment (CPU; may take several minutes)…', 30)
    return separated

def instrument_charts(audio_path, temp, job):
    separated = separate_stems(audio_path, temp, job)
    charts = {}
    for index, stem in enumerate(['drums', 'bass', 'vocals', 'other']):
        job.update('Generating four difficulties: ' + stem, 60 + index * 9)
        stem_path = separated / 'htdemucs' / 'audio' / (stem + '.wav')
        if not stem_path.exists():
            raise RuntimeError('Stem separation did not produce ' + stem)
        charts['Accompaniment' if stem == 'other' else stem.title()] = generate_charts(stem_path, allow_holds=stem != 'drums', instrument=stem)
    if not any(notes for diffs in charts.values() for notes in diffs.values()):
        raise ValueError('No playable onsets detected')
    return charts

def song_hype(audio_path, temp, job):
    job.update('Detecting energy lifts, recurring choruses and instrument solos...', 93)
    stems = temp / 'stems' / 'htdemucs' / 'audio'
    return detect_hype(audio_path, {('Accompaniment' if name == 'other' else name.title()): stems / (name + '.wav') for name in ['drums', 'bass', 'vocals', 'other']})

def encode_background(source, output, job):
    job.run([binary('ffmpeg'), '-nostdin', '-y', '-i', source, '-t', str(MAX_SECONDS),
             '-an', '-vf', 'scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=24',
             '-c:v', 'libtheora', '-q:v', '5', '-pix_fmt', 'yuv420p', output],
            'Preparing dimmed video background...', 94)
    if not output.is_file() or output.stat().st_size < 100:
        raise ValueError('Video conversion produced no playable background')


def download_background(url, temp, job):
    url = validate_youtube(url)
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
        shutil.copy2(video, destination)
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
    shutil.copy2(video, folder / 'background.ogv.partial')
    os.replace(folder / 'background.ogv.partial', folder / 'background.ogv')
    pack['video'] = 'background.ogv'
    atomic_json(metadata, pack)
    return [str(folder)], []

def import_youtube(url, library, temp, job):
    url = validate_youtube(url)
    work = temp / 'pack'
    work.mkdir()
    job.run([binary('yt-dlp'), '--ignore-config', '--no-playlist', '--no-progress', '--no-warnings',
             '--js-runtimes', 'deno:' + binary('deno'), '--socket-timeout', '30', '--retries', '2',
             '--match-filter', 'duration <= 900 & !is_live', '--max-filesize', '200M',
             '--ffmpeg-location', str(Path(binary('ffmpeg')).parent), '-f', 'bestaudio/best',
             '--write-info-json', '-o', str(temp / 'download.%(ext)s'), '--', url], 'Downloading YouTube audio…', 5)
    info_file = temp / 'download.info.json'
    if not info_file.exists():
        raise ValueError('Video unavailable, live, or longer than 15 minutes')
    info = json.loads(info_file.read_text(encoding='utf-8'))
    audio = [p for p in temp.glob('download.*') if p.suffix not in {'.json', '.part', '.ytdl'}]
    if len(audio) != 1:
        raise ValueError('Audio download did not produce a single complete file')
    duration = convert_audio(audio[0], work / 'audio.wav', job, 20)
    charts = instrument_charts(work / 'audio.wav', temp, job)
    pack = {'schema': 1, 'id': 'yt-' + info['id'], 'category': 'YouTube', 'title': info.get('title', 'YouTube import'),
            'artist': info.get('uploader', 'Unknown'), 'audio': 'audio.wav', 'duration': duration,
            'charts': charts, 'timing': estimate_timing(work / 'audio.wav'), 'source': url, 'generator': 'htdemucs + consistent voice + recurring riffs v7'}
    pack['hype'] = song_hype(work / 'audio.wav', temp, job)
    warnings = optional_background(url, work / 'background.ogv', temp, job)
    if (work / 'background.ogv').is_file():
        pack['video'] = 'background.ogv'
    job.update('Saving generated charts…', 99)
    return [str(commit_pack(work, library, pack))], warnings

def regenerate_song(source, library, temp, job):
    folder = Path(source).resolve()
    if not folder.is_relative_to(library.resolve()) or folder == library.resolve():
        raise ValueError('Choose a song in the game song folder')
    pack_file = folder / 'song.json'
    original = pack_file.read_bytes()
    pack = json.loads(original)
    if pack.get('category') != 'YouTube' or pack.get('audio') != 'audio.wav':
        raise ValueError('Only YouTube songs can be regenerated')
    audio_path = folder / 'audio.wav'
    if not audio_path.is_file():
        raise ValueError('Cached audio is missing')
    pack['charts'] = instrument_charts(audio_path, temp, job)
    pack['timing'] = estimate_timing(audio_path)
    pack['hype'] = song_hype(audio_path, temp, job)
    pack['generator'] = 'htdemucs + consistent voice + recurring riffs v7'
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
    if pack.get('category') == 'YouTube':
        separate_stems(audio, temp, job)
        pack['hype'] = song_hype(audio, temp, job)
    else:
        pack['hype'] = detect_hype(audio)
    if pack_file.read_bytes() != original:
        raise ValueError('Song changed during analysis; retry')
    atomic_json(pack_file, pack)
    return [str(folder)], []

def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--separate':
        from demucs.separate import main as separate
        separate(['-n', 'htdemucs', '-d', 'cpu', '--shifts', '1', '-o', sys.argv[3], sys.argv[2]])
        return
    parser = argparse.ArgumentParser()
    parser.add_argument('--request', required=True)
    args = parser.parse_args()
    request = json.loads(Path(args.request).read_text(encoding='utf-8'))
    job = Job(request['result'])
    try:
        library = Path(request['library']).resolve()
        library.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.import-', dir=library) as tmp:
            job.update('Preparing import…', 1)
            if request['kind'] == 'youtube':
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
        atomic_json(job.result, {'state': 'done', 'message': 'Import complete', 'progress': 100, 'paths': paths, 'warnings': warnings})
    except Exception as error:
        atomic_json(job.result, {'state': 'error', 'message': str(error), 'progress': 0})
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    import multiprocessing
    multiprocessing.freeze_support()
    main()
