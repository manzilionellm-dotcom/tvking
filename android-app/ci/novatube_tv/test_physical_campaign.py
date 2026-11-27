"""Contrôles du lanceur sans appareil. Aucune commande ADB réelle n'est exécutée."""
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

import physical_campaign as campaign
from regional_live_source import SIGNATURE


BASE_SHA = 'aa93b4b959bb93d0e863d338be98445254f3412100302870a6c58a4d52662b34'
FIX_SHA = '7936acfa8e1064b8d2c58314c59d1ae5f4a2ebed4c5c56beefdcb0b1c6f629ad'


class Preflight(unittest.TestCase):
    def test_virtual_serial_stops_before_adb(self):
        with patch.object(campaign, 'adb') as adb:
            with self.assertRaises(ValueError):
                campaign.inventory('emulator-5554')
            adb.assert_not_called()

    def test_qemu_device_disguised_as_network_serial(self):
        props = {f'ro.{name}': 'value' for name in ('product.manufacturer', 'product.model', 'hardware',
                 'build.fingerprint', 'build.version.release', 'product.cpu.abi')}
        props['ro.boot.qemu'] = '1'
        output = '\n'.join(f'[{key}]: [{value}]' for key, value in props.items())
        with patch.object(campaign, 'adb', side_effect=['device', output]):
            with self.assertRaisesRegex(ValueError, 'virtuel'):
                campaign.inventory('box-lan')

    def test_protect_secondary_user_and_retained_data(self):
        states = ['Users:\nUserInfo{0:Primary:13}\nUserInfo{12:Lab:13}', '0',
                  'package:android', f'package:android\npackage:{campaign.PACKAGE}']
        with patch.object(campaign, 'adb', side_effect=states) as adb:
            with self.assertRaisesRegex(ValueError, 'refusée'):
                campaign.package_state('usb', False, FIX_SHA)
        self.assertTrue(all('-u' in call.args for call in adb.call_args_list[-2:]))

    def test_unreadable_package_list_stops(self):
        states = ['Users:\nUserInfo{0:Lab:13}', '0', 'Error: access denied']
        with patch.object(campaign, 'adb', side_effect=states):
            with self.assertRaisesRegex(ValueError, 'incomplète'):
                campaign.package_state('usb', False, FIX_SHA)

    def test_refuse_unexpected_reuse(self):
        with patch.object(campaign, 'adb', side_effect=['UserInfo{0:Lab:13}', '0', 'package:android']):
            with self.assertRaisesRegex(ValueError, 'absent'):
                campaign.package_state('usb', True, FIX_SHA)

    def test_reuse_requires_exact_base(self):
        with patch.object(campaign, 'adb', return_value='package:/test/base.apk\npackage:/test/split.apk'):
            with self.assertRaisesRegex(ValueError, 'fractionné'):
                campaign.verify_installed('usb', '0', FIX_SHA)
        with patch.object(campaign, 'adb', side_effect=['package:/test/base.apk', 'copié']), \
                patch.object(campaign, 'sha256', return_value='autre'):
            with self.assertRaisesRegex(ValueError, 'différent'):
                campaign.verify_installed('usb', '0', FIX_SHA)

    def test_reuse_cannot_mix_the_two_measured_apks(self):
        self.assertIn(FIX_SHA, campaign.REVISIONS_BY_SHA)
        self.assertIn(BASE_SHA, campaign.REVISIONS_BY_SHA)
        for expected, other in [(FIX_SHA, BASE_SHA), (BASE_SHA, FIX_SHA)]:
            with self.subTest(expected=expected), \
                    patch.object(campaign, 'adb', side_effect=['package:/test/base.apk', 'copié']), \
                    patch.object(campaign, 'sha256', return_value=other):
                with self.assertRaisesRegex(ValueError, 'différent'):
                    campaign.verify_installed('usb', '0', expected)

    def test_leave_another_reverse_mapping_in_place(self):
        with patch.object(campaign, 'adb', return_value='UsbFfs tcp:8788 tcp:1333') as adb:
            campaign.remove_own_route('usb', 'tcp:1222')
            self.assertEqual(adb.call_count, 1)
        with patch.object(campaign, 'adb', side_effect=['UsbFfs tcp:8788 tcp:1222', '']) as adb:
            campaign.remove_own_route('usb', 'tcp:1222')
            adb.assert_called_with('usb', 'reverse', '--remove', 'tcp:8788')


class OpticalProtocol(unittest.TestCase):
    def test_one_hundred_zaps_and_forward_reading(self):
        # Les captures portent la vraie signature et le vrai compteur de la mire.
        # Seuls ADB, le temps de capture et les 80 minutes sont simulés.
        channel, counter = 'A', 0

        def frame(adb, out, start, console_fallback=True):
            nonlocal counter
            self.assertEqual(adb, ['adb', '-s', 'qa-box'])
            self.assertFalse(console_fallback)
            counter += 1
            pixels = [*SIGNATURE, int(channel == 'B')]
            bits = [(counter >> shift) & 1 for shift in range(20)]
            pixels += bits + [sum(bits) % 2, 1]
            # Le banc échantillonne le centre de chaque case 16:9.
            image = Image.new('L', (480, 270))
            for index, value in enumerate(pixels):
                image.putpixel((round((496 + 32 * index) / 4), round(650 / 4)), 255 * value)
            return image, b''

        def key(args, **kwargs):
            nonlocal channel
            self.assertEqual(args[:5], ['adb', '-s', 'qa-box', 'shell', 'input'])
            channel = 'B' if channel == 'A' else 'A'
            return subprocess.CompletedProcess(args, 0)

        def reading(out, adb, screenshot, current, duration):
            self.assertEqual(duration, 4800)
            rows = [dict(channel=current, frame=n) for n in (23,24,25)]
            (out / 'hour-samples.jsonl').write_text('\n'.join(json.dumps(r) for r in rows))
            return {'screens': 3, 'identified': 3, 'moving_pairs': 2}

        with tempfile.TemporaryDirectory() as tmp, patch('pilot_observer.frame', frame), \
                patch('pilot_observer.sparse_hour', reading), patch('subprocess.run', key), \
                patch.object(sys, 'argv', ['benchmark.py', tmp, '--physical-serial', 'qa-box']):
            with self.assertRaises(SystemExit) as stop:
                runpy.run_path(str(campaign.HERE / 'benchmark.py'), run_name='__main__')
            self.assertEqual(stop.exception.code, 0)
            results = json.loads((Path(tmp) / 'pilot.json').read_text())
            self.assertEqual(results['zap_summary']['attempted'], 100)
            self.assertEqual(results['zap_summary']['confirmed'], 100)
            self.assertEqual(results['forward_pairs'], 2)
            self.assertTrue(results['all_sampled_pairs_moved'])


if __name__ == '__main__':
    unittest.main()
