from pathlib import Path
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'importer'))
from charting import limit_simultaneous_holds
from worker import Job, attach_video, encode_background, optional_background

class ArcadeTests(unittest.TestCase):
    def test_cap_and_preserve_note_heads(self):
        notes = [{'t': float(i), 'end': 10., 'lane': i} for i in range(4)]
        before = [(n['t'], n['lane']) for n in notes]
        limit_simultaneous_holds(notes)
        self.assertEqual([n['end'] for n in notes], [10., 10., 2., 3.])
        self.assertEqual(before, [(n['t'], n['lane']) for n in notes])
    def test_tail_boundary_frees_slot(self):
        notes = [{'t':0.,'end':1.,'lane':0},{'t':0.,'end':3.,'lane':1},{'t':1.,'end':4.,'lane':2}]
        limit_simultaneous_holds(notes)
        self.assertEqual(notes[-1]['end'], 4.)
    def test_sweep_never_exceeds_two_holds(self):
        notes = [{'t': i * .13, 'end': i * .13 + .7 + (i % 5) * .2, 'lane':i % 4} for i in range(200)]
        limit_simultaneous_holds(notes)
        events = sorted((t, delta) for n in notes if n['end']>n['t'] for t,delta in [(n['t'],1),(n['end'],-1)])
        active = 0
        for _, delta in events:
            active += delta
            self.assertLessEqual(active, 2)
        self.assertEqual(active, 0)
        again = copy.deepcopy(notes); limit_simultaneous_holds(again)
        self.assertEqual(again, notes)
    def test_video_transcode_theora_muted_and_scaled(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); source=root/'source.mp4'; target=root/'background.ogv'
            subprocess.run(['ffmpeg','-nostdin','-v','error','-y','-f','lavfi','-i','testsrc2=size=160x120:rate=12','-t','0.5','-c:v','mpeg4',str(source)],check=True)
            encode_background(source,target,Job(root/'job.json'))
            probe=subprocess.run(['ffprobe','-v','error','-show_streams','-of','json',str(target)],capture_output=True,text=True,check=True)
            streams=json.loads(probe.stdout)['streams']
            self.assertEqual(len(streams),1)
            self.assertEqual(streams[0]['codec_name'],'theora')
            self.assertEqual((streams[0]['width'],streams[0]['height']),(640,360))
    def test_attach_video_preserves_chart_and_audio(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); song=root/'yt'; song.mkdir()
            original={'id':'yt','category':'YouTube','source':'https://youtu.be/abcdefghijk','charts':{'Bass':{}},'audio':'audio.wav'}
            (song/'song.json').write_text(json.dumps(original)); (song/'audio.wav').write_bytes(b'audio')
            video=root/'download.ogv'; video.write_bytes(b'OggS-video-fixture')
            with patch('worker.download_background',return_value=video):
                attach_video(str(song),root,root,Job(root/'job.json'))
            data=json.loads((song/'song.json').read_text())
            self.assertEqual(data['charts'],original['charts'])
            self.assertEqual(data['video'],'background.ogv')
            self.assertEqual((song/'audio.wav').read_bytes(),b'audio')
            self.assertEqual((song/'background.ogv').read_bytes(),video.read_bytes())
    def test_optional_video_failure_keeps_audio_import_usable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            with patch('worker.download_background',side_effect=RuntimeError('no video')):
                warnings=optional_background('url',root/'background.ogv',root,Job(root/'result.json'))
            self.assertEqual(len(warnings),1)
            self.assertFalse((root/'background.ogv').exists())
    def test_video_cancellation_not_swallowed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); job=Job(root/'result.json'); job.cancel.touch()
            with patch('worker.download_background',side_effect=RuntimeError('cancelled')):
                with self.assertRaises(RuntimeError): optional_background('url',root/'background.ogv',root,job)

if __name__=='__main__':
    unittest.main()
