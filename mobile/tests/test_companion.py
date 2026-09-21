import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
spec = importlib.util.spec_from_file_location('companion', Path(__file__).resolve().parents[1] / 'companion.py')
companion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(companion)

class LibraryTests(unittest.TestCase):
    def test_library_rejects_external_audio_and_incomplete_songs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'outside.wav').write_bytes(b'audio')
            valid = root / 'Valid'
            valid.mkdir()
            (valid / 'audio.wav').write_bytes(b'audio')
            (valid / 'song.json').write_text(json.dumps({'title': 'Valid', 'audio': 'audio.wav'}))
            invalid = root / 'Invalid'
            invalid.mkdir()
            (invalid / 'song.json').write_text(json.dumps({'title': 'Invalid', 'audio': '../outside.wav'}))
            self.assertEqual([song['title'] for _, song in companion.catalog(root).values()], ['Valid'])

class HTTPTests(unittest.TestCase):
    def test_authenticated_song_download(self):
        import io
        import os
        import socket
        import subprocess
        import sys
        import time
        import urllib.error
        import urllib.request
        import zipfile
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / 'Song'
            folder.mkdir()
            (folder / 'song.json').write_text(json.dumps({'title': 'Song', 'audio': 'audio.wav'}))
            (folder / 'audio.wav').write_bytes(b'original audio')
            (folder / 'private.txt').write_text('not part of song pack')
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0))
                port = sock.getsockname()[1]
            env = dict(os.environ, PULSE_COMPANION_TOKEN='test-access-token')
            server = subprocess.Popen([sys.executable, str(Path(companion.__file__)), '--songs', tmp, '--bind', '127.0.0.1', '--port', str(port)], env=env, stdout=subprocess.DEVNULL)
            base = f'http://127.0.0.1:{port}'
            def get(path, authenticated=True):
                headers = {'Authorization': 'Bearer test-access-token'} if authenticated else {}
                return urllib.request.urlopen(urllib.request.Request(base + path, headers=headers), timeout=2)
            try:
                for attempt in range(50):
                    try:
                        with get('/songs') as response: data = json.load(response)
                        break
                    except OSError:
                        time.sleep(.05)
                else: self.fail('companion did not start')
                with self.assertRaises(urllib.error.HTTPError) as error: get('/songs', False)
                self.assertEqual(error.exception.code, 401)
                with get('/pack/' + data['songs'][0]['id']) as response:
                    archive = zipfile.ZipFile(io.BytesIO(response.read()))
                self.assertEqual(set(archive.namelist()), {'song.json', 'audio.wav'})
                self.assertEqual(archive.read('audio.wav'), b'original audio')
            finally:
                server.terminate()
                server.wait(timeout=5)
