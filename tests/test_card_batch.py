import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'importer'))
from worker import import_cards

class BatchTests(unittest.TestCase):
    def test_bad_card_does_not_stop_batch_and_duplicates_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            class Job:
                cancel=root/'cancel'
                def update(self,*args): pass
                def run(self,*args): pass
            seen=[]
            def importer(source,library,temp,job):
                self.assertTrue(temp.is_dir())
                self.assertFalse((temp/'scratch').exists())
                (temp/'scratch').write_text('one card only')
                seen.append(Path(source).name)
                job.update('reading',50)
                if Path(source).name=='bad.png':raise ValueError('No intact chart')
                return [str(library/Path(source).stem)],[]
            sources=[str(root/name) for name in ['first.png','bad.png','last.PNG','first.png']]
            with patch('worker.import_card',side_effect=importer):
                paths,warnings,message=import_cards(sources,root,root,Job())
            self.assertEqual(seen,['first.png','bad.png','last.PNG'])
            self.assertEqual(len(paths),2);self.assertEqual(len(warnings),1)
            self.assertIn('bad.png',warnings[0]);self.assertIn('2/3',message)
            self.assertFalse(list(root.glob('card-*')))

    def test_cancel_keeps_completed_cards_and_skips_remaining(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            class Job:
                cancel=root/'cancel'
            def importer(source,library,temp,job):
                job.cancel.write_text('cancel')
                return ['completed-song'],[]
            with patch('worker.import_card',side_effect=importer) as mocked:
                paths,_,message=import_cards(['one.png','two.png'],root,root,Job())
            self.assertEqual(mocked.call_count,1);self.assertEqual(paths,['completed-song'])
            self.assertIn('cancelled',message)

    def test_invalid_batch_rejected(self):
        for value in [None,[],['x']*501,[42]]:
            with self.assertRaises(ValueError):import_cards(value,Path('.'),Path('.'),None)
