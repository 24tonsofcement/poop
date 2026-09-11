import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import wave
import zipfile
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'importer'))
from worker import parse_osu, unpack_osz, safe_child, validate_youtube, atomic_json
from charting import generate_charts, DIFFICULTIES

MAP = '''osu file format v14
[General]
AudioFilename: audio.wav
Mode:3
[Metadata]
Title:Test pulse
Artist:Test
Version:Normal
[Difficulty]
CircleSize:4
[HitObjects]
64,192,1000,1,0,0:0:0:0:
192,192,1500,128,0,2200:0:0:0:0:
320,192,2500,1,0,0:0:0:0:
512,192,3000,1,0,0:0:0:0:
'''

def wav(path, samples=None):
    if samples is None:
        samples = np.zeros(44100 * 4)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes((samples * 30000).astype('<i2').tobytes())

class ImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
    def tearDown(self):
        self.temp.cleanup()
    def make_map(self, text=MAP):
        f = self.root / 'test.osu'
        f.write_text(text, encoding='utf-8-sig')
        return f
    def test_mania_lanes_and_hold(self):
        meta, notes = parse_osu(self.make_map())
        self.assertEqual([n['lane'] for n in notes], [0, 1, 2, 3])
        self.assertEqual(notes[1], {'t': 1.5, 'lane': 1, 'end': 2.2})
    def test_reject_non_mania_and_non_4k(self):
        for bad in [MAP.replace('Mode:3', 'Mode:0'), MAP.replace('CircleSize:4', 'CircleSize:7')]:
            with self.assertRaises(ValueError):
                parse_osu(self.make_map(bad))
    def test_reject_invalid_hold_and_overlap(self):
        for bad in [MAP.replace('2200:', '1200:'), MAP + '192,192,1800,1,0,0:0:0:0:\n']:
            with self.assertRaises(ValueError):
                parse_osu(self.make_map(bad))
    def test_archive_path_traversal(self):
        archive = self.root / 'bad.osz'
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('../outside.txt', 'no')
        with self.assertRaises(ValueError):
            unpack_osz(archive, self.root / 'out')
        self.assertFalse((self.root / 'outside.txt').exists())
    def test_audio_path_traversal(self):
        for bad in ['../file.wav', '/tmp/file.wav', 'C:\\music.wav', '..\\file.wav']:
            with self.assertRaises(ValueError):
                safe_child(self.root, bad)
    def test_youtube_canonicalization(self):
        self.assertEqual(validate_youtube('https://youtu.be/abcdefghijk?t=30'), 'https://www.youtube.com/watch?v=abcdefghijk')
        for bad in ['file:///etc/passwd', 'https://youtube.com.evil.test/watch?v=abcdefghijk', 'https://youtube.com/playlist?list=x', 'https://user:pass@youtube.com/watch?v=abcdefghijk']:
            with self.assertRaises(ValueError):
                validate_youtube(bad)
    def test_silence_no_fabricated_notes(self):
        audio = self.root / 'silent.wav'
        wav(audio)
        self.assertTrue(all(not notes for notes in generate_charts(audio).values()))
    def test_onsets_alignment_density_and_reproducibility(self):
        audio = self.root / 'pulses.wav'
        samples = np.zeros(44100 * 8)
        times = np.arange(.5, 7.5, .25)
        for i, t in enumerate(times):
            tone_t = np.arange(2205) / 44100
            signal = np.sin(2 * np.pi * (220 + 30 * (i % 4)) * tone_t) * np.exp(-tone_t * 60) * (.4 + (i % 3) * .2)
            start = round(t * 44100)
            samples[start:start + len(signal)] = signal
        wav(audio, samples)
        charts = generate_charts(audio)
        self.assertEqual(charts, generate_charts(audio))
        counts = [len(charts[d]) for d in DIFFICULTIES]
        self.assertGreater(counts[-1], counts[0])
        self.assertEqual(counts, sorted(counts))
        for difficulty, notes in charts.items():
            self.assertTrue(notes)
            for note in notes:
                self.assertLess(min(abs(times - note['t'])), .04)
                self.assertIn(note['lane'], range(4))
            gap = DIFFICULTIES[difficulty][0]
            self.assertTrue(all(b['t'] - a['t'] >= gap - .001 for a, b in zip(notes, notes[1:])))
    def test_osz_end_to_end_and_reimport(self):
        audio = self.root / 'audio.wav'
        wav(audio)
        archive = self.root / 'valid.osz'
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('normal.osu', MAP)
            z.writestr('hard.osu', MAP.replace('Version:Normal', 'Version:Hard'))
            z.writestr('7key.osu', MAP.replace('CircleSize:4', 'CircleSize:7'))
            z.write(audio, 'audio.wav')
        lib = self.root / 'songs'
        result = self.root / 'result.json'
        req = self.root / 'request.json'
        atomic_json(req, {'kind': 'osu', 'source': str(archive), 'library': str(lib), 'result': str(result)})
        script = Path(__file__).resolve().parents[1] / 'importer' / 'worker.py'
        for _ in range(2):
            run = subprocess.run([sys.executable, str(script), '--request', str(req)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            status = json.loads(result.read_text())
            self.assertEqual(status['state'], 'done')
            self.assertEqual(len(status['warnings']), 1)
        packs = list(lib.glob('*/song.json'))
        self.assertEqual(len(packs), 1)
        data = json.loads(packs[0].read_text())
        self.assertEqual(set(data['charts']['Original']), {'Normal', 'Hard'})
        self.assertTrue(packs[0].with_name('audio.wav').exists())
    def test_youtube_pipeline_separated_chart_wiring(self):
        # Simulates external downloader/separator only; real WAV/chart/commit code runs.
        # This is not a live YouTube or real Demucs test.
        from unittest.mock import patch
        from worker import import_youtube
        temp = self.root / 'staging'
        temp.mkdir()
        library = self.root / 'library'
        library.mkdir()
        class SimulatedJob:
            def update(self, *args):
                pass
            def run(self, args, *unused):
                args = [str(x) for x in args]
                if args[0] == 'yt-dlp':
                    (temp / 'download.info.json').write_text(json.dumps({'id': 'abcdefghijk', 'title': 'Test', 'uploader': 'Test'}))
                    wav(temp / 'download.wav')
                elif args[0] == 'ffmpeg':
                    import shutil
                    shutil.copyfile(args[args.index('-i') + 1], args[-1])
                elif '--separate' in args:
                    stems = Path(args[-1]) / 'htdemucs' / 'audio'
                    stems.mkdir(parents=True)
                    for index, stem in enumerate(['drums', 'bass', 'vocals', 'other']):
                        samples = np.zeros(44100 * 4)
                        for t in np.arange(.4 + index * .06, 3.5, .25):
                            phase = np.arange(2205) / 44100
                            sound = .6 * np.sin(2 * np.pi * (220 + index * 100) * phase) * np.exp(-phase * 60)
                            start = round(t * 44100)
                            samples[start:start + len(sound)] = sound
                        wav(stems / (stem + '.wav'), samples)
                else:
                    raise AssertionError(args)
        with patch('worker.binary', side_effect=lambda x: x):
            paths, warnings = import_youtube('https://youtu.be/abcdefghijk', library, temp, SimulatedJob())
        data = json.loads((Path(paths[0]) / 'song.json').read_text())
        self.assertEqual(data['category'], 'YouTube')
        self.assertEqual(set(data['charts']), {'Drums', 'Bass', 'Vocals', 'Accompaniment'})
        first_times = []
        for charts in data['charts'].values():
            self.assertEqual(set(charts), set(DIFFICULTIES))
            self.assertTrue(charts['Expert'])
            first_times.append(charts['Expert'][0]['t'])
        self.assertEqual(len(set(first_times)), 4)

    def test_worker_failure_is_machine_readable(self):
        result = self.root / 'failed.json'
        req = self.root / 'request.json'
        atomic_json(req, {'kind': 'youtube', 'source': 'invalid', 'library': str(self.root / 'songs'), 'result': str(result)})
        script = Path(__file__).resolve().parents[1] / 'importer' / 'worker.py'
        run = subprocess.run([sys.executable, str(script), '--request', str(req)], capture_output=True)
        self.assertNotEqual(run.returncode, 0)
        self.assertEqual(json.loads(result.read_text())['state'], 'error')
    def test_cancellation(self):
        from worker import Job
        result = self.root / 'job.result.json'
        job = Job(result)
        job.cancel.touch()
        with self.assertRaises(RuntimeError):
            job.update('preparing')

if __name__ == '__main__':
    unittest.main()
