from pathlib import Path
import sys
import unittest
import tempfile
import json
from unittest.mock import patch
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'importer'))
from hype import detect_arrays, detect_hype
from worker import analyze_song_hype, Job

class HypeTests(unittest.TestCase):
    def test_silence_and_constant_energy_not_hype(self):
        for energy in [np.zeros(30),np.ones(30)*.1]:
            self.assertFalse(detect_arrays(energy,np.ones((30,8))/np.sqrt(8),60)['global'])

    def test_repeated_energy_lifts(self):
        e=np.full(40,.04);e[6:11]=.20;e[24:29]=.20
        result=detect_arrays(e,np.ones((40,8))/np.sqrt(8),80)
        for time in [14,50]:
            self.assertTrue(any(s['start']<=time<s['end'] for s in result['global']))
        self.assertFalse(any(s['start']<=35<s['end'] for s in result['global']))
        self.assertEqual(result,detect_arrays(e,np.ones((40,8))/np.sqrt(8),80))

    def test_solo_only_dominant_instrument(self):
        a=np.full(30,.025);a[10:15]=.3
        result=detect_arrays(np.ones(30)*.1,np.ones((30,8))/np.sqrt(8),60,
            {'Bass':a,'Drums':np.ones(30)*.08,'Vocals':np.ones(30)*.05})
        self.assertTrue(result['instruments']['Bass'])
        self.assertFalse(result['instruments']['Drums'])
        self.assertFalse(result['instruments']['Vocals'])

    def test_analysis_preserves_chart_and_audio(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);folder=root/'song';folder.mkdir()
            pack={'audio':'audio.wav','category':'osu!mania','charts':{'Original':{'Easy':[{'t':1,'lane':0,'end':1}]}}}
            (folder/'song.json').write_text(json.dumps(pack));(folder/'audio.wav').write_bytes(b'unchanged')
            with patch('worker.detect_hype',return_value={'global':[]}):
                analyze_song_hype(folder,root,root,Job(root/'result.json'))
            updated=json.loads((folder/'song.json').read_text())
            self.assertEqual(updated['charts'],pack['charts'])
            self.assertEqual((folder/'audio.wav').read_bytes(),b'unchanged')
            self.assertIn('hype',updated)

    def test_audio_waveform_energy_lift(self):
        import wave
        with tempfile.TemporaryDirectory() as temp:
            rate = 22050
            t = np.arange(rate * 32) / rate
            amplitude = np.where(((t >= 8) & (t < 14)) | ((t >= 24) & (t < 30)), .4, .04)
            signal = amplitude * np.sin(2 * np.pi * 220 * t)
            path = Path(temp) / 'audio.wav'
            with wave.open(str(path), 'wb') as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
                w.writeframes((signal * 32767).astype('<i2').tobytes())
            result = detect_hype(path)
            self.assertTrue(any(section['start'] <= 10 < section['end'] for section in result['global']))
            self.assertTrue(any(section['start'] <= 26 < section['end'] for section in result['global']))

    def test_busy_quiet_chart_does_not_create_hype(self):
        energy=np.full(40,.02);energy[20:30]=.2
        notes=[{'t': t, 'end': t, 'lane': 0} for t in np.arange(0,40,.1)]
        notes += [{'t': t, 'end': t, 'lane': 0} for t in np.arange(40,60,1)]
        result=detect_arrays(energy,np.ones((40,8))/np.sqrt(8),80,
            charts={'Drums': {'Expert':notes}})
        self.assertFalse(any(s['start']<40 for s in result['global']))
        self.assertTrue(any(s['start']<=46<s['end'] for s in result['global']))

    def test_empty_instrument_chart_cannot_claim_solo(self):
        stem=np.full(30,.02);stem[10:15]=.3
        result=detect_arrays(np.ones(30)*.1,np.ones((30,8))/np.sqrt(8),60,
            {'Bass':stem,'Drums':np.ones(30)*.08}, {'Bass': {'Expert':[]}})
        self.assertFalse(result['instruments']['Bass'])
