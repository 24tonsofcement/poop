"""Versioned, fail-safe Windows launcher. Only published releases are trusted."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tempfile
import urllib.request
import zipfile

REPO = '24tonsofcement/poop'
API = f'https://api.github.com/repos/{REPO}/releases/latest'
ASSET = 'PulseFour-update.zip'
MAX_BYTES = 2_000_000_000
MAX_EXPANDED = 8_000_000_000


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r'v?\d+\.\d+\.\d+', value):
        raise ValueError('Expected a stable version such as 1.0.0')
    return tuple(map(int, value.lstrip('v').split('.')))


def request(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={
        'User-Agent': 'PulseFour-Updater/1', 'Accept': 'application/vnd.github+json'
    }), timeout=8)


def select_asset(release, current):
    if release.get('draft') or release.get('prerelease'):
        return None
    tag = release['tag_name']
    if version(tag) <= version(current):
        return None
    asset = next(a for a in release['assets'] if a['name'] == ASSET)
    digest = asset.get('digest', '')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        raise ValueError('Release is missing its SHA-256 digest')
    if not 0 < asset['size'] <= MAX_BYTES:
        raise ValueError('Invalid update size')
    expected = f'https://github.com/{REPO}/releases/download/{tag}/{ASSET}'
    if asset['browser_download_url'] != expected:
        raise ValueError('Unexpected update source')
    return tag.lstrip('v'), asset


def download(asset, path, progress):
    digest = hashlib.sha256()
    count = 0
    with request(asset['browser_download_url']) as response, path.open('wb') as out:
        while True:
            data = response.read(1024 * 256)
            if not data:
                break
            count += len(data)
            if count > asset['size']:
                raise ValueError('Download exceeded advertised size')
            digest.update(data)
            out.write(data)
            progress(f'Downloading update… {count * 100 // asset["size"]}%')
    if count != asset['size'] or 'sha256:' + digest.hexdigest() != asset['digest']:
        raise ValueError('Incomplete download or checksum mismatch')


def extract(archive, target):
    with zipfile.ZipFile(archive) as z:
        if sum(i.file_size for i in z.infolist()) > MAX_EXPANDED:
            raise ValueError('Update expands beyond the allowed size')
        seen = set()
        for item in z.infolist():
            name = item.filename
            parts = PurePosixPath(name).parts
            if (not parts or name.startswith('/') or '\\' in name or ':' in name
                    or '..' in parts or any(p.endswith((' ', '.')) for p in parts)
                    or stat.S_ISLNK(item.external_attr >> 16)):
                raise ValueError('Unsafe archive entry')
            if name.lower() in seen:
                raise ValueError('Duplicate archive entry')
            seen.add(name.lower())
        z.extractall(target)
    required = ['PulseFour.exe', 'PulseLobby.exe', 'importer/PulseImporter.exe', 'VERSION']
    if not all((target / p).is_file() for p in required):
        raise ValueError('Update is missing required files')


def active(root):
    try:
        name = (root / 'current.txt').read_text().strip()
        version(name)
        path = root / 'versions' / name
        if (path / 'PulseFour.exe').is_file():
            return name, path
    except (OSError, ValueError):
        pass
    return '0.0.0', None


def activate(root, name):
    pointer = root / 'current.tmp'
    pointer.write_text(name, encoding='utf-8')
    os.replace(pointer, root / 'current.txt')


def check_update(root, progress, fetch=request, verify=None):
    """Keep current.txt unchanged until a complete candidate passes its launch check."""
    current, old = active(root)
    progress('Checking for updates…')
    with fetch(API) as response:
        release = json.loads(response.read(1024 * 1024))
    selected = select_asset(release, current)
    if not selected:
        return old
    name, asset = selected
    root.mkdir(parents=True, exist_ok=True)
    (root / 'versions').mkdir(exist_ok=True)
    destination = root / 'versions' / name
    with tempfile.TemporaryDirectory(prefix='update-', dir=root) as tmp:
        tmp = Path(tmp)
        archive = tmp / 'update.zip'
        download(asset, archive, progress)
        candidate = tmp / 'app'
        extract(archive, candidate)
        if (candidate / 'VERSION').read_text().strip() != name:
            raise ValueError('Release version mismatch')
        progress('Checking the new version…')
        (verify or verify_game)(candidate)
        # A previous interrupted install can leave an unused directory behind.
        if destination.exists():
            shutil.rmtree(destination)
        os.replace(candidate, destination)
        activate(root, name)
    return destination


def verify_game(folder):
    with tempfile.TemporaryDirectory() as data:
        env = dict(os.environ, APPDATA=data)
        result = subprocess.run([str(folder / 'PulseFour.exe'), '--headless',
                                 '--quit-after', '3'], cwd=folder, env=env,
                                capture_output=True, timeout=45,
                                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        output = result.stdout + result.stderr
        if result.returncode or b'ERROR:' in output or b'SCRIPT ERROR' in output:
            raise RuntimeError('New game failed its launch check')
