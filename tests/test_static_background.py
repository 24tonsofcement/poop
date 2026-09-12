import sys
import unittest
import tempfile
import json
from pathlib import Path
from unittest.mock import patch
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'importer'))
from static_background import still_image
from worker import download_background

class StaticBackgroundTests(unittest.TestCase):
    def fixture(self):
        info={'duration':60,'formats':[{'protocol':'mhtml','width':80,'height':45,'rows':2,'columns':3,'fps':.2,
              'fragments':[{'url':'one'},{'url':'two'}]}]}
        tile=np.zeros((45,80,3),dtype=np.uint8);tile[:,:,0]=np.arange(80);tile[:,:,1]=110
        sheet=Image.fromarray(np.tile(tile,(2,3,1)))
        return info,sheet

    def test_matching_frames_produce_still(self):
        info,sheet=self.fixture()
        image=still_image(info,lambda _:sheet)
        self.assertEqual(image.size,(80,45))

    def test_changed_last_frame_requires_video(self):
        info,sheet=self.fixture(); changed=sheet.copy();changed.paste('red',(160,45,240,90))
        self.assertIsNone(still_image(info,lambda url: sheet if url=='one' else changed))

    def test_missing_or_sparse_previews_require_video(self):
        info,sheet=self.fixture();info['formats'][0]['fragments'].pop()
        self.assertIsNone(still_image(info,lambda _:sheet))
        self.assertIsNone(still_image({}))

    def test_still_background_skips_video_downloader(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'download.info.json').write_text(json.dumps({'duration':60}))
            class Job:
                def update(self,*args): pass
                def run(self,*args): raise AssertionError('Must not download a video for still imagery')
            with patch('static_background.still_image',return_value=Image.new('RGB',(100,100))):
                result=download_background('https://youtu.be/abcdefghijk',root,Job())
            self.assertEqual(result.name,'background.png')
            self.assertTrue(result.is_file())
