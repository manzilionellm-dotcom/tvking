#!/usr/bin/env python3
"""Le splash TV colle au fond Flutter et ne laisse pas le logo derrière."""
import tempfile
import unittest
from pathlib import Path

import apply_splash


class ApplySplashTest(unittest.TestCase):
    def test_wordmark_avant_android_12_aplats_apres(self):
        with tempfile.TemporaryDirectory() as raw:
            res = Path(raw)
            apply_splash.apply(res)
            pre = (res / 'drawable/launch_background.xml').read_text()
            pre21 = (res / 'drawable-v21/launch_background.xml').read_text()
            post = (res / 'drawable-v31/launch_background.xml').read_text()
            self.assertIn('@drawable/splash_logo', pre)
            self.assertIn('@color/zuno_splash', pre)
            self.assertNotIn('tv_banner', pre)
            self.assertNotIn('#FF050505', pre)
            self.assertNotIn('#FFFFFF', pre.upper())
            self.assertEqual(pre, pre21)
            self.assertNotIn('splash_logo', post)
            self.assertNotIn('tv_banner', post)

            colors = (res / 'values/colors.xml').read_text()
            self.assertIn(apply_splash.SPLASH, colors)

            normal = (res / 'values/styles.xml').read_text()
            self.assertIn(
                'name="NormalTheme"',
                normal,
            )
            self.assertIn('@color/zuno_splash', normal)
            # Le thème de marche ne réaffiche pas le drawable (logo inclus).
            normal_block = normal.split('name="NormalTheme"', 1)[1]
            self.assertNotIn('launch_background', normal_block)
            self.assertIn('launch_background', normal.split('NormalTheme', 1)[0])

            night = (res / 'values-night/styles.xml').read_text()
            self.assertEqual(night, normal)

            v31 = (res / 'values-v31/styles.xml').read_text()
            self.assertIn('windowSplashScreenBackground', v31)
            self.assertIn('windowSplashScreenIconBackgroundColor', v31)
            self.assertNotIn('windowSplashScreenAnimatedIcon', v31)

            # Deuxième passe : la couleur n'est pas dupliquée.
            apply_splash.apply(res)
            again = (res / 'values/colors.xml').read_text()
            self.assertEqual(again.count('zuno_splash'), 1)


if __name__ == '__main__':
    unittest.main()
