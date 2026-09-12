import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'importer'))
from instruments import select_sources

class InstrumentTests(unittest.TestCase):
    def test_vocals_drums_plus_two_strongest_parts(self):
        measured={'vocals':(.02,.06),'drums':(.03,.1),'bass':(.02,.04),
                  'guitar':(.10,.3),'piano':(.08,.2),'other':(.001,.002)}
        self.assertEqual(select_sources(measured,(.3,.5)),['vocals','drums','guitar','piano'])

    def test_instrumental_does_not_get_leakage_vocals_or_drums(self):
        measured={'vocals':(.0001,.0004),'drums':(0,0),'bass':(.03,.1),
                  'guitar':(.04,.15),'piano':(.1,.25),'other':(.002,.003)}
        self.assertEqual(select_sources(measured,(.3,.5)),['piano','guitar'])

    def test_quiet_but_present_vocals_retained(self):
        self.assertEqual(select_sources({'vocals':(.001,.003),'piano':(.02,.04)},(.025,.05)),['vocals','piano'])

    def test_silence_creates_no_fake_choices(self):
        self.assertEqual(select_sources({'vocals':(0,0),'other':(0,0)},(0,0)),[])
