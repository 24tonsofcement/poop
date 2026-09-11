import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import wave
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'importer'))
from charting import generate_charts, add_holds
from worker import regenerate_song, Job

class HoldTests(unittest.TestCase):
    def test_sustained_audio_produces_holds_and_percussion_remains_taps(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'audio.wav'
            rate = 44100
            time = np.arange(rate * 4) / rate
            envelope = np.clip((time - .5) / .008, 0, 1) * np.clip((2.0 - time) / .015, 0, 1)
            signal = .6 * np.sin(2 * np.pi * 220 * time) * envelope
            with wave.open(str(path), 'wb') as f:
                f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate)
                f.writeframes((signal * 32767).astype('<i2').tobytes())
            charts = generate_charts(path)
            self.assertTrue(any(n['end'] - n['t'] > 1.0 for notes in charts.values() for n in notes))
            self.assertEqual(charts, generate_charts(path))
            self.assertLessEqual(len(charts['Expert']), 2, 'Sustained tone should not become a stream of false attacks')
            for notes in charts.values():
                last = [-1.] * 4
                for n in notes:
                    self.assertGreater(n['t'], last[n['lane']])
                    self.assertLessEqual(n['end'], 2.1)
                    last[n['lane']] = n['end']
            taps = generate_charts(path, allow_holds=False)
            self.assertTrue(all(n['end'] == n['t'] for notes in taps.values() for n in notes))
    def test_repeated_pitches_keep_lanes_and_ascending_pitches_move_right(self):
        with tempfile.TemporaryDirectory() as tmp:
            audio = Path(tmp) / 'notes.wav'
            rate = 44100
            samples = np.zeros(rate * 7)
            frequencies = [110, 110, 220, 440, 880, 880]
            times = np.arange(.5, 6.0, 1.0)
            for start_time, frequency in zip(times, frequencies):
                t = np.arange(int(.16 * rate)) / rate
                burst = .6 * np.sin(2 * np.pi * frequency * t) * np.exp(-t * 20)
                start = round(start_time * rate)
                samples[start:start + len(burst)] = burst
            with wave.open(str(audio), 'wb') as f:
                f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate)
                f.writeframes((samples * 32767).astype('<i2').tobytes())
            notes = generate_charts(audio, instrument='bass')['Expert']
            matched = [min(notes, key=lambda n: abs(n['t'] - t)) for t in times]
            self.assertTrue(all(abs(n['t'] - t) < .03 for n, t in zip(matched, times)))
            lanes = [n['lane'] for n in matched]
            self.assertEqual(lanes, sorted(lanes))
            self.assertEqual(lanes[0], lanes[1])
            self.assertEqual(lanes[-1], lanes[-2])
            self.assertGreater(lanes[-1], lanes[0])

    def test_hold_tail_leaves_release_gap_before_next_same_lane(self):
        notes = [{'t': .2, 'end': .2, 'lane': 0}, {'t': .8, 'end': .8, 'lane': 0}, {'t': 1., 'end': 1., 'lane': 1}]
        add_holds(notes, np.ones(300), .01, 3.0, 'Hard')
        self.assertAlmostEqual(notes[0]['end'], .7)
        self.assertGreater(notes[1]['end'], notes[1]['t'])
    def test_short_hit_does_not_become_hold(self):
        notes = [{'t': .2, 'end': .2, 'lane': 0}]
        energy = np.zeros(300)
        energy[20:26] = 1
        add_holds(notes, energy, .01, 3.0, 'Expert')
        self.assertEqual(notes[0]['end'], notes[0]['t'])
    def test_regeneration_preserves_audio_identity_and_backup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); song = root / 'yt-song'; song.mkdir()
            original = {'schema': 1, 'id': 'yt-song', 'category': 'YouTube', 'audio': 'audio.wav', 'charts': {'old': {}}}
            file = song / 'song.json'; file.write_text(json.dumps(original))
            (song / 'audio.wav').write_bytes(b'cached audio fixture')
            generated = {'Bass': {'Easy': [{'t': 1., 'end': 2., 'lane': 0}]}}
            job = Job(root / 'result.json')
            with patch('worker.song_hype', return_value={'global': [], 'instruments': {}}), patch('worker.instrument_charts', return_value=generated), patch('worker.estimate_timing', return_value=[{'t': 0., 'beat_length': .5, 'meter': 4}]):
                regenerate_song(str(song), root, root, job)
            self.assertEqual((song / 'audio.wav').read_bytes(), b'cached audio fixture')
            self.assertEqual(json.loads(file.read_text())['id'], original['id'])
            self.assertEqual(json.loads(file.read_text())['charts'], generated)
            self.assertEqual(json.loads((song / 'song.before-holds.json').read_text()), original)
    def test_failed_regeneration_leaves_existing_map_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); song = root / 'yt-song'; song.mkdir()
            file = song / 'song.json'; file.write_text(json.dumps({'category': 'YouTube', 'audio': 'audio.wav'}))
            (song / 'audio.wav').touch()
            before = file.read_bytes()
            with patch('worker.instrument_charts', side_effect=RuntimeError('model failed')):
                with self.assertRaises(RuntimeError): regenerate_song(str(song), root, root, Job(root/'result.json'))
            self.assertEqual(file.read_bytes(), before)
    def test_regeneration_rejects_outside_library_and_osu(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); library = root / 'songs'; library.mkdir()
            with self.assertRaises(ValueError): regenerate_song(str(root), library, root, Job(root/'r.json'))
            song = library/'osu'; song.mkdir()
            (song/'song.json').write_text(json.dumps({'category': 'osu!mania', 'audio': 'audio.wav'}))
            with self.assertRaises(ValueError): regenerate_song(str(song), library, root, Job(root/'r.json'))

if __name__ == '__main__':
    unittest.main()
