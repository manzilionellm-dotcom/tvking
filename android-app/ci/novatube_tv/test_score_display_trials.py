"""Régressions de mesure de l'image figée sur la mire à 25 Hz."""
import csv
import tempfile
import unittest
from pathlib import Path

from score_display_trials import measure


def score(rows, end):
    with tempfile.TemporaryDirectory() as tmp:
        events = Path(tmp) / 'events.csv'
        events.write_text(f'id,kind,start_s,end_s,channel\ntv,play,0,{end},A\n')
        frames = Path(tmp) / 'frames.csv'
        with frames.open('w', newline='') as stream:
            writer = csv.writer(stream)
            writer.writerow(('capture_pts_s', 'channel', 'source_frame', 'status'))
            writer.writerows(rows)
        return measure(events, frames)['observed'][0]


class FrameHoldTests(unittest.TestCase):
    def test_image_repetee_jusqua_la_fin(self):
        # Dix secondes de vidéo acquises, incluant huit secondes d'image fixe.
        rows = [(i / 25, 'A', min(i, 50), 'ok') for i in range(251)]
        trial = score(rows, 10.04)
        self.assertTrue(trial['complete_visual_coverage'])
        self.assertEqual(trial['missing_source_frames_in_contiguous_valid_intervals'], 0)
        self.assertEqual(trial['longest_observed_frame_hold'], {
            'source_frame': 50, 'start_capture_pts_s': 2.0,
            'end_capture_pts_s': 10.0, 'duration_s': 8.0,
        })

    def test_un_trou_ou_une_autre_chaine_separe_les_repetitions(self):
        for reason in ('lacune', 'inconnue', 'autre chaîne'):
            with self.subTest(reason=reason):
                rows = [(i / 25, 'A', 100, 'ok') for i in range(151)]
                if reason == 'lacune':
                    del rows[75]
                elif reason == 'inconnue':
                    rows[75] = (3.0, '', '', 'unknown')
                else:
                    rows[75] = (3.0, 'B', 100, 'ok')
                trial = score(rows, 6.04)
                self.assertFalse(trial['complete_visual_coverage'])
                self.assertAlmostEqual(trial['longest_observed_frame_hold']['duration_s'], 2.96)

    def test_mouvement_continu_et_lecture_illisible(self):
        for status in ('ok', 'unknown'):
            with self.subTest(status=status):
                rows = [(i / 25, 'A', i, status) for i in range(51)]
                trial = score(rows, 2.04)
                self.assertEqual(trial['complete_visual_coverage'], status == 'ok')
                self.assertIsNone(trial['longest_observed_frame_hold'])


if __name__ == '__main__':
    unittest.main()
