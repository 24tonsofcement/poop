import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'importer'))
from install_cleanup import cleanup

class CleanupTests(unittest.TestCase):
    def test_only_obsolete_inactive_managed_versions_deleted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);versions=root/'versions'
            for name in ['1.7.0','1.8.0','1.9.0','2.0.0','songs']:
                folder=versions/name;folder.mkdir(parents=True)
                (folder/'PulseFour.exe').write_bytes(b'exe')
            (root/'current.txt').write_text('1.9.0')
            (root/'scores.json').write_text('keep')
            self.assertEqual(cleanup(root,versions/'1.9.0',[versions/'1.8.0'/'PulseFour.exe']),['1.7.0'])
            for name in ['1.8.0','1.9.0','2.0.0','songs']: self.assertTrue((versions/name).exists())
            self.assertEqual(cleanup(root,versions/'1.9.0',[]),['1.8.0'])
            self.assertTrue((root/'scores.json').exists())

    def test_old_running_game_or_portable_copy_cannot_clean_installs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);old=root/'versions'/'1.0.0';old.mkdir(parents=True)
            (old/'PulseFour.exe').write_bytes(b'exe');(root/'current.txt').write_text('1.9.0')
            self.assertEqual(cleanup(root,old,[]),[])
            self.assertTrue(old.exists())
