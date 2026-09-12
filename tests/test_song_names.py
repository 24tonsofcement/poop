import sys
import unittest
import tempfile
import json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'importer'))
from worker import song_folder_name, commit_pack, existing_pack

class SongNamesTests(unittest.TestCase):
    def test_readable_safe_unique_titles(self):
        first=song_folder_name({'title':'Song: One / 二','id':'one'})
        self.assertTrue(first.startswith('Song_ One _ 二'))
        self.assertNotEqual(first,song_folder_name({'title':'Song: One / 二','id':'two'}))
        self.assertTrue(song_folder_name({'title':'CON','id':'one'}).startswith('_CON'))

    def test_old_and_new_folder_imports_remain_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);library=root/'songs';library.mkdir();work=root/'work';work.mkdir()
            pack={'id':'yt-one','title':'Music Title'}
            path=commit_pack(work,library,pack)
            self.assertTrue(path.name.startswith('Music Title'))
            self.assertEqual(existing_pack(library,'yt-one'),path)
            self.assertEqual(commit_pack(root/'absent',library,pack),path)
