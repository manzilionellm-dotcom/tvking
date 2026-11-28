"""Contre-épreuve de la décision de gel et des captures expurgées."""
import io
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
from PIL import Image
import observe

class DetectorTest(unittest.TestCase):
    def test_detector_keeps_first_repeated_counter(self):
        # L'écran simulé montre deux compteurs croissants puis reste bloqué.
        # La vraie calibration de region() est exécutée séparément via FFmpeg.
        image=Image.new('L',(300,30),255)
        raw=io.BytesIO();image.save(raw,format='PNG')
        def fake_adb(*args,**kwargs):
            if 'screencap' in args:return raw.getvalue()
            if 'pidof' in args:return b'42'
            return b''
        seq=iter([0,1,2]+[2]*30)
        with TemporaryDirectory() as d, patch.object(observe,'adb',side_effect=fake_adb), \
             patch.object(observe,'region',side_effect=lambda _:('A',next(seq),image)):
            out=Path(d)
            observe.observe(out,7)
            result=json.loads((out/'summary.json').read_text())
            assert result['timed']
            assert result['first_incident']['kind']=='repetition'
            assert result['longest_readable_sampled_repetition_lower_s']>=5
            assert (out/'film-marqueurs.gif').is_file()
            assert (out/'forensic.json').is_file()

if __name__=='__main__':
    unittest.main()
