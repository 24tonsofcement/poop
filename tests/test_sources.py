import sys
import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'importer'))
from sources import source_info
from test_song_card import pack, thumbnail
from song_card import encode, decode
import worker

class SourceTests(unittest.TestCase):
    def test_categories_and_canonical_links(self):
        self.assertEqual(source_info('https://m.soundcloud.com/artist/song?secret_token=abc'),('SoundCloud','https://soundcloud.com/artist/song?secret_token=abc'))
        self.assertEqual(source_info('https://youtu.be/abcdefghijk')[0],'YouTube')

    def test_unsupported_and_collection_links_rejected(self):
        for url in ['https://soundcloud.com/a/sets/b','https://soundcloud.com/a','https://soundcloud.com.evil.test/a/b',
            'file:///etc/passwd','https://user:pass@soundcloud.com/a/b','https://open.spotify.com/track/123',
            'https://artist.bandcamp.com/track/song','https://audius.co/user/song']:
            with self.assertRaises(ValueError): source_info(url)

    def test_soundcloud_card_roundtrip_category_and_charts(self):
        song=pack();song.update(category='SoundCloud',source='https://soundcloud.com/artist/song')
        result=decode(encode(thumbnail(),song))
        self.assertEqual(result['category'],'SoundCloud');self.assertEqual(result['charts'],song['charts'])
        song['category']='YouTube'
        with self.assertRaises(ValueError): encode(thumbnail(),song)

    def test_soundcloud_import_skips_youtube_background(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);work=root/'pack';work.mkdir();library=root/'songs';library.mkdir()
            class Job:
                def update(self,*args): pass
            with patch.object(worker,'download_youtube_audio',return_value=(work,10,{'id':'123','title':'SC Song'})), \
                 patch.object(worker,'instrument_charts',return_value=pack()['charts']), \
                 patch.object(worker,'song_hype',return_value={}),patch.object(worker,'estimate_timing',return_value=[]), \
                 patch.object(worker,'optional_background',side_effect=AssertionError('SoundCloud is audio-only')):
                paths,_=worker.import_youtube('https://soundcloud.com/artist/song',library,root,Job())
            import json
            saved=json.loads((Path(paths[0])/'song.json').read_text())
            self.assertEqual(saved['category'],'SoundCloud')
            self.assertEqual(saved['source'],'https://soundcloud.com/artist/song')
