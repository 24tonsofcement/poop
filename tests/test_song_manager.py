import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'importer'))
from song_manager import scan, remove

class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.library=self.root/'songs';self.library.mkdir()
        self.covers=self.root/'covers';self.covers.mkdir();self.song=self.library/'Song';self.song.mkdir()
        self.pack={'title':'Song','category':'YouTube','source':'https://www.youtube.com/watch?v=abcdefghijk','audio':'audio.wav','charts':{'Bass':{}},'video':'background.ogv','background_image':'background.png'}
        (self.song/'song.json').write_text(json.dumps(self.pack))
        for name,size in [('audio.wav',100),('background.ogv',200),('background.png',40),('thumbnail.jpg',30)]: (self.song/name).write_bytes(b'x'*size)
        (self.covers/'abcdefghijk.jpg').write_bytes(b'x'*20)

    def test_byte_totals_and_background_deletion(self):
        row=scan(self.library,self.covers)[0]
        self.assertEqual(row['bytes'],sum(p.stat().st_size for p in self.song.iterdir())+20)
        self.assertEqual(row['background_bytes'],240)
        remove(self.library,self.covers,self.song,'background')
        self.assertTrue((self.song/'audio.wav').exists())
        self.assertEqual(scan(self.library,self.covers)[0]['background_bytes'],0)
        self.assertEqual(json.loads((self.song/'song.json').read_text())['charts'],self.pack['charts'])

    def test_thumbnail_deletion_persists_opt_out(self):
        remove(self.library,self.covers,self.song,'thumbnail')
        self.assertTrue(json.loads((self.song/'song.json').read_text())['thumbnail_disabled'])
        self.assertEqual(scan(self.library,self.covers)[0]['thumbnail_bytes'],0)
        self.assertFalse((self.covers/'abcdefghijk.jpg').exists())

    def test_song_deletion_preserves_scores_and_other_songs(self):
        (self.root/'leaderboards.json').write_text('saved')
        remove(self.library,self.covers,self.song,'song')
        self.assertFalse(self.song.exists());self.assertTrue((self.root/'leaderboards.json').exists())

    def test_outside_path_rejected(self):
        with self.assertRaises(ValueError):remove(self.library,self.covers,self.root,'song')
        with self.assertRaises(ValueError):remove(self.library,self.covers,self.song,'invalid')
