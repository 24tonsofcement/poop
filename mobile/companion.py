"""Android companion: authenticated song library and queued desktop imports.
Run: python mobile/companion.py --songs PATH [--worker PATH_TO_PulseImporter.exe]
The normal desktop game does not need to be modified.
"""
import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import threading
import urllib.parse
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BODY = 8192

def catalog(root):
    result = {}
    for folder in root.iterdir():
        if not folder.is_dir() or folder.name.startswith('.'):
            continue
        try:
            data = json.loads((folder / 'song.json').read_text(encoding='utf-8'))
            audio = folder / str(data['audio'])
            if audio.resolve().parent != folder.resolve() or not audio.is_file():
                continue
            key = hashlib.sha256(folder.name.encode()).hexdigest()[:24]
            result[key] = (folder, data)
        except (OSError, ValueError, KeyError, TypeError):
            pass
    return result

def serve(args):
    root = Path(args.songs).resolve()
    root.mkdir(parents=True, exist_ok=True)
    token = os.environ.get('PULSE_COMPANION_TOKEN') or secrets.token_urlsafe(24)
    jobs = {}
    lock = threading.Lock()
    state = Path(tempfile.mkdtemp(prefix='pulse-mobile-'))

    def generate(job, source):
        result = state / (job + '.json')
        request = state / (job + '-request.json')
        request.write_text(json.dumps({'kind': 'link', 'source': source, 'library': str(root), 'result': str(result)}))
        try:
            command = [args.worker] if args.worker else [sys.executable, str(Path(__file__).resolve().parents[1] / 'importer' / 'worker.py')]
            process = subprocess.run(command + ['--request', str(request)], capture_output=True, timeout=7200)
            if not result.exists():
                result.write_text(json.dumps({'state': 'error', 'message': process.stderr.decode(errors='replace')[-1000:] or 'Importer did not return a result.'}))
        except Exception as error:
            result.write_text(json.dumps({'state': 'error', 'message': str(error)}))
        finally:
            lock.release()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def authorized(self):
            return hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + token)
        def reply(self, data, status=200):
            body = json.dumps(data).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def do_GET(self):
            if not self.authorized(): return self.reply({'error': 'Unauthorized'}, 401)
            path = urllib.parse.urlparse(self.path).path
            if path == '/songs':
                return self.reply({'songs': [{'id': key, 'title': data.get('title', folder.name)} for key, (folder, data) in catalog(root).items()]})
            if path.startswith('/jobs/'):
                job = path.rsplit('/', 1)[-1]
                if job not in jobs: return self.reply({'error': 'Not found'}, 404)
                result = state / (job + '.json')
                try: return self.reply(json.loads(result.read_text()))
                except (OSError, ValueError): return self.reply({'state': 'working', 'message': 'Preparing importer…'})
            if path.startswith('/pack/'):
                item = catalog(root).get(path.rsplit('/', 1)[-1])
                if item is None: return self.reply({'error': 'Not found'}, 404)
                folder, _ = item
                with tempfile.TemporaryFile() as archive:
                    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_STORED) as output:
                        for file in folder.iterdir():
                            if file.is_file() and not file.is_symlink() and file.suffix.lower() in {'.json', '.wav', '.ogg', '.mp3', '.ogv', '.png', '.jpg', '.jpeg'}:
                                output.write(file, file.name)
                    length = archive.tell()
                    archive.seek(0)
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/zip')
                    self.send_header('Content-Length', str(length))
                    self.end_headers()
                    while chunk := archive.read(1024 * 1024): self.wfile.write(chunk)
                return
            self.reply({'error': 'Not found'}, 404)
        def do_POST(self):
            if not self.authorized(): return self.reply({'error': 'Unauthorized'}, 401)
            if self.path != '/generate': return self.reply({'error': 'Not found'}, 404)
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= MAX_BODY: raise ValueError()
                source = str(json.loads(self.rfile.read(length))['source']).strip()
                url = urllib.parse.urlparse(source)
                host = (url.hostname or '').lower()
                if url.scheme not in {'http', 'https'} or not any(host == domain or host.endswith('.' + domain) for domain in ['youtube.com', 'youtu.be', 'soundcloud.com']): raise ValueError()
            except (ValueError, KeyError, TypeError): return self.reply({'error': 'Provide a YouTube or SoundCloud URL'}, 400)
            if not lock.acquire(blocking=False): return self.reply({'error': 'Another import is active'}, 409)
            job = secrets.token_hex(12)
            jobs[job] = True
            threading.Thread(target=generate, args=(job, source), daemon=True).start()
            self.reply({'job': job})
    print(f'Companion ready on port {args.port}. Enter this computer\'s LAN IP in the phone settings.')
    print(f'Access token: {token}', flush=True)
    ThreadingHTTPServer((args.bind, args.port), Handler).serve_forever()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--songs', required=True)
    parser.add_argument('--worker', default='')
    parser.add_argument('--port', type=int, default=27441)
    parser.add_argument('--bind', default='0.0.0.0')
    serve(parser.parse_args())
