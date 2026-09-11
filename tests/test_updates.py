import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'launcher'))
import updater as u

class UpdateTests(unittest.TestCase):
    def release(self, payload=b'', tag='v1.1.0'):
        return dict(tag_name=tag, draft=False, prerelease=False, assets=[dict(
            name=u.ASSET, size=len(payload) or 1, digest='sha256:'+hashlib.sha256(payload).hexdigest(),
            browser_download_url=f'https://github.com/{u.REPO}/releases/download/{tag}/{u.ASSET}')])

    def test_versions(self):
        self.assertGreater(u.version('1.10.0'),u.version('1.9.0'))
        for bad in ('../1.0.0','v1.0.0-beta','',None):
            with self.assertRaises(ValueError): u.version(bad)
        self.assertIsNone(u.select_asset(self.release(), '1.1.0'))
        self.assertIsNone(u.select_asset(self.release(), '2.0.0'))

    def test_untrusted_asset(self):
        r=self.release();r['assets'][0]['browser_download_url']='https://example.com/update.zip'
        with self.assertRaises(ValueError):u.select_asset(r,'1.0.0')
        r=self.release();r['assets'][0]['digest']=None
        with self.assertRaises((ValueError,TypeError)):u.select_asset(r,'1.0.0')

    def test_download_corruption(self):
        with tempfile.TemporaryDirectory() as d, patch.object(u,'request',return_value=io.BytesIO(b'wrong')):
            with self.assertRaises(ValueError):u.download(self.release(b'right')['assets'][0],Path(d)/'x',lambda _:None)

    def test_unsafe_archives(self):
        for name in ('../escape','/absolute','C:/escape','folder\\escape','x./file'):
            with tempfile.TemporaryDirectory() as d:
                p=Path(d)/'a.zip'
                with zipfile.ZipFile(p,'w') as z:z.writestr(name,b'x')
                with self.assertRaises(ValueError):u.extract(p,Path(d)/'out')

    def payload(self):
        b=io.BytesIO()
        with zipfile.ZipFile(b,'w') as z:
            for name in ('PulseFour.exe','PulseLobby.exe','importer/PulseImporter.exe'):
                z.writestr(name,b'fixture')
            z.writestr('VERSION','1.1.0')
        return b.getvalue()

    def test_transaction_and_player_data(self):
        for fail in (True,False):
            with tempfile.TemporaryDirectory() as d:
                root=Path(d);old=root/'versions'/'1.0.0';old.mkdir(parents=True)
                (old/'PulseFour.exe').write_bytes(b'old');u.activate(root,'1.0.0')
                (root/'songs').mkdir();(root/'songs'/'keep').write_text('save')
                payload=self.payload(); release=self.release(payload)
                def verify(_):
                    if fail:raise RuntimeError('launch failed')
                with patch.object(u,'request',return_value=io.BytesIO(payload)):
                    fetch=lambda _:io.BytesIO(json.dumps(release).encode())
                    if fail:
                        with self.assertRaises(RuntimeError):u.check_update(root,lambda _:None,fetch,verify)
                        self.assertEqual(u.active(root)[0],'1.0.0')
                    else:
                        u.check_update(root,lambda _:None,fetch,verify)
                        self.assertEqual(u.active(root)[0],'1.1.0')
                self.assertEqual((old/'PulseFour.exe').read_bytes(),b'old')
                self.assertEqual((root/'songs'/'keep').read_text(),'save')

if __name__=='__main__':unittest.main()
