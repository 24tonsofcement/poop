from pathlib import Path
import sys
import unittest
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'importer'))
from arrangement import phrase_onsets, flowing_lanes, independent_tones, add_supported_chords

class ArrangementTests(unittest.TestCase):
    def test_harmonics_are_not_independent_notes(self):
        frequencies = np.arange(100) * 10.
        self.assertFalse(independent_tones([22, 44, 66], [1., .9, .8], frequencies))
        self.assertTrue(independent_tones([22, 33, 44], [1., .8, .7], frequencies))

    def test_chords_need_evidence_and_preserve_measured_heads(self):
        attacks = list(range(10, 410, 25))
        base = [{'t': at*.01, 'end': at*.01, 'lane': i%4} for i,at in enumerate(attacks)]
        scores = np.ones(420)
        bands = np.zeros((420,4)); bins = np.zeros((420,6),dtype=int); weights = np.zeros((420,6))
        notes = [dict(n) for n in base]
        add_supported_chords(notes,attacks,scores,bands,bins,weights,np.arange(100),'drums','Expert',.01)
        self.assertEqual(notes,base)
        bands[:,0] = 1; bands[:,3] = .8
        add_supported_chords(notes,attacks,scores,bands,bins,weights,np.arange(100),'drums','Expert',.01)
        self.assertGreater(len(notes),len(base))
        self.assertEqual({n['t'] for n in notes},{n['t'] for n in base})
        self.assertEqual(len(notes),len({(n['t'],n['lane']) for n in notes}))
        self.assertTrue(all(sum(n['t']==at for n in notes)<=2 for at in {n['t'] for n in notes}))
        mono=[dict(n) for n in base]
        add_supported_chords(mono,attacks,scores,bands,bins,weights,np.arange(100),'vocals','Expert',.01)
        self.assertEqual(mono,base)

    def test_fast_finger_repeats_softened_but_slow_pitches_preserved(self):
        attacks=list(range(0,80,10)); lanes={at:1 for at in attacks}
        fast=flowing_lanes(attacks,lanes,.01)
        self.assertEqual(set(fast),set(lanes))
        self.assertLess(sum(fast[a]==fast[b] for a,b in zip(attacks,attacks[1:])),2)
        self.assertEqual(flowing_lanes(attacks,lanes,.05),lanes)

    def test_repeated_gesture_uses_same_thinning_mask(self):
        first=list(range(10,210,25));second=[at+300 for at in first];pool=first+second
        scores=np.ones(600)
        scores[first]=np.linspace(.5,1.,8);scores[second]=np.linspace(1.,.5,8)
        chosen=phrase_onsets(pool,scores,.45,40,.01)
        self.assertEqual([at for at in chosen if at in first],[at-300 for at in chosen if at in second])
        self.assertTrue(all((b-a)*.01>=.45 for a,b in zip(chosen,chosen[1:])))

    def test_wide_chords_are_rare_and_require_four_band_evidence(self):
        attacks = list(range(50, 8050, 50))
        notes = [{'t': at*.01, 'end': at*.01, 'lane': i%4} for i,at in enumerate(attacks)]
        add_supported_chords(notes, attacks, np.ones(8100), np.ones((8100,4)),
            np.zeros((8100,6), dtype=int), np.zeros((8100,6)), np.arange(100), 'drums', 'Expert', .01)
        rows = {}
        for note in notes: rows.setdefault(note['t'], set()).add(note['lane'])
        quads = [t for t, lanes in rows.items() if len(lanes) == 4]
        self.assertGreater(len(quads), 0)
        self.assertLessEqual(len(quads), int(len(attacks)*.02))
        self.assertTrue(any(len(lanes)==3 for lanes in rows.values()))
        self.assertTrue(all(b-a >= 8 for a,b in zip(quads,quads[1:])))

    def test_quiet_template_cannot_thin_an_energetic_repeat(self):
        first = list(range(10,210,25)); second = [at+300 for at in first]
        pool = first+second; intensity = np.ones(600); intensity[first] = .1
        chosen = phrase_onsets(pool, np.ones(600), .22, 0, .01, intensity=intensity)
        self.assertGreater(sum(at in second for at in chosen), sum(at in first for at in chosen))
