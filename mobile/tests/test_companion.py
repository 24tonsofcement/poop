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
