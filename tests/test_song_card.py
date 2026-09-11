import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib
import struct
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'importer'))
from PIL import Image
import song_card as card
import worker


def thumbnail():
    out = io.BytesIO()
    Image.new('RGB', (480, 360), '#325478').save(out, format='PNG')
    return out.getvalue()


def pack():
    return dict(schema=1, category='YouTube', title='Shared rhythm', artist='Tester', source='https://www.youtube.com/watch?v=abcdefghijk', duration=10,
                charts={'Drums': {'Easy': [{'t': 1., 'end': 2., 'lane': 0}], 'Expert': [{'t': 3., 'end': 3., 'lane': 2}]}},
                timing=[{'t': 0, 'beat_length': .5, 'meter': 4}], hype={'global': [{'start': 2, 'end': 8, 'confidence': .9}], 'instruments': {}})


class Cards(unittest.TestCase):
    def test_roundtrip_visible_png_and_no_media(self):
        song = pack()
        song.update(folder='C:/private', video='background.ogv', id='yt-anything')
        art = card.render_card(thumbnail(), song['title'])
        raw = card.encode(art, song)
        with Image.open(io.BytesIO(raw)) as image:
            image.load()
            self.assertEqual(image.size, (480, 502))
            self.assertEqual(image.getpixel((20, 20)), (50, 84, 120))
        restored = card.decode(raw)
        for key in ['charts', 'timing', 'hype', 'source']:
            self.assertEqual(restored[key], song[key])
        self.assertNotIn('folder', restored)
        self.assertNotIn('video', restored)
        self.assertLess(len(raw), 100000)
        self.assertEqual(card.decode(card.encode(art, restored))['id'], restored['id'])

    def test_godot_numeric_serialization(self):
        original = pack()
        from_godot = copy.deepcopy(original)
        for notes in from_godot['charts']['Drums'].values():
            for note in notes: note['lane'] = float(note['lane'])
        from_godot['timing'][0]['meter'] = 4.0
        self.assertEqual(card.decode(card.encode(thumbnail(), original))['id'], card.decode(card.encode(thumbnail(), from_godot))['id'])
        from_godot['charts']['Drums']['Easy'][0]['lane'] = 1.5
        with self.assertRaises(ValueError): card.encode(thumbnail(), from_godot)

    def test_stripped_corrupt_and_untrusted_cards(self):
        with self.assertRaises(ValueError): card.decode(thumbnail())
        raw = bytearray(card.encode(thumbnail(), pack()))
        raw[-15] ^= 1
        with self.assertRaises(ValueError): card.decode(bytes(raw))
        for mutate in [lambda s: s.update(source='https://evil.example/x'), lambda s: s.update(duration=float('nan')), lambda s: s['charts']['Drums']['Easy'][0].update(lane=7)]:
            song = pack(); mutate(song)
            with self.assertRaises(ValueError): card.encode(thumbnail(), song)

    def test_size_limit_before_decompression(self):
        raw = card.encode(thumbnail(), pack())
        with patch.object(card, 'MAX_JSON', 50):
            with self.assertRaises(ValueError): card.decode(raw)

    def test_import_downloads_media_without_regeneration_and_preserves_variants(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            library = root / 'songs'; library.mkdir()
            source = root / 'shared.png'; source.write_bytes(card.encode(thumbnail(), pack()))
            temp = root / 'work'; temp.mkdir()
            job = worker.Job(root / 'result.json')
            def audio(url, directory, job):
                work = directory / 'pack'; work.mkdir()
                (work / 'audio.wav').write_bytes(b'fixture audio')
                return work, 10, {'id': 'abcdefghijk'}
            def video(url, destination, temp, job):
                destination.write_bytes(b'fixture video'); return []
            with patch.object(worker, 'download_youtube_audio', side_effect=audio) as download, patch.object(worker, 'optional_background', side_effect=video) as background, patch.object(worker, 'instrument_charts', side_effect=AssertionError('Must not regenerate')):
                paths, _ = worker.import_card(source, library, temp, job)
                restored = json.loads((Path(paths[0]) / 'song.json').read_text())
                self.assertEqual(restored['charts'], pack()['charts'])
                self.assertEqual(restored['video'], 'background.ogv')
                worker.import_card(source, library, temp, job)
                self.assertEqual(download.call_count, 1)
                self.assertEqual(background.call_count, 1)
            revised = pack(); revised['charts']['Drums']['Easy'][0]['t'] = .8
            self.assertNotEqual(card.decode(source.read_bytes())['id'], card.decode(card.encode(thumbnail(), revised))['id'])

    def test_changed_audio_does_not_publish_song(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root / 'card.png'
            source.write_bytes(card.encode(thumbnail(), pack()))
            with patch.object(worker, 'download_youtube_audio', return_value=(root, 20, {})):
                with self.assertRaisesRegex(ValueError, 'duration has changed'):
                    worker.import_card(source, root, root, worker.Job(root / 'result.json'))
            self.assertFalse(any(root.glob('card-*/song.json')))
