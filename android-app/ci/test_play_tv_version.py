import unittest

from play_tv_version import validate_version


class PlayTvVersionTest(unittest.TestCase):
    def test_increment_from_existing_play_release(self):
        self.assertEqual(validate_version({
            "lastPublishedVersionCode": 1791125395,
            "versionCode": 1791125396, "versionName": "108",
        }), (1791125396, "108"))

    def test_rejects_timestamp_jump_reuse_downgrade_and_limit(self):
        for previous, current in [(1791125395, 1792394391), (10, 10),
                                  (10, 9), (2100000000, 2100000001),
                                  (True, 2), (0, 1), ("10", 11)]:
            with self.subTest(previous=previous, current=current):
                with self.assertRaises(ValueError):
                    validate_version({"lastPublishedVersionCode": previous,
                                      "versionCode": current, "versionName": "108"})

    def test_rejects_environment_injection(self):
        for name in ["108\nTV_BUILD_NUMBER=1", "108-test", 108, ""]:
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    validate_version({"lastPublishedVersionCode": 10,
                                      "versionCode": 11, "versionName": name})


if __name__ == "__main__":
    unittest.main()
