import unittest

from play_tv_version import validate_version


class PlayTvVersionTest(unittest.TestCase):
    def test_increment_from_existing_play_release(self):
        # Compatibilité d'un manifeste antérieur au suivi des imports.
        self.assertEqual(validate_version({
            "lastPublishedVersionCode": 1791125395,
            "versionCode": 1791125396, "versionName": "108",
        }), (1791125396, "108"))

    def test_uploaded_release_consumes_code_without_becoming_published(self):
        # La version 108 reste en examen : seule la référence d'import avance.
        data = {
            "lastPublishedVersionCode": 1791125395,
            "lastUploadedVersionCode": 1791125396,
            "versionCode": 1791125397,
            "versionName": "109",
        }
        self.assertEqual(validate_version(data), (1791125397, "109"))
        self.assertEqual(data["lastPublishedVersionCode"], 1791125395)

    def test_published_reference_still_sets_a_floor(self):
        self.assertEqual(validate_version({
            "lastPublishedVersionCode": 20,
            "lastUploadedVersionCode": 19,
            "versionCode": 21, "versionName": "109",
        }), (21, "109"))

    def test_rejects_reuse_or_jump_after_unpublished_upload(self):
        for current in (1791125395, 1791125396, 1791125398):
            with self.subTest(current=current):
                with self.assertRaises(ValueError):
                    validate_version({
                        "lastPublishedVersionCode": 1791125395,
                        "lastUploadedVersionCode": 1791125396,
                        "versionCode": current, "versionName": "109",
                    })

    def test_rejects_non_integer_codes_in_each_reference(self):
        for field in ("lastPublishedVersionCode", "lastUploadedVersionCode", "versionCode"):
            for value in (True, False, "11", 11.0, None):
                with self.subTest(field=field, value=value):
                    data = {
                        "lastPublishedVersionCode": 10,
                        "lastUploadedVersionCode": 11,
                        "versionCode": 12, "versionName": "109",
                    }
                    data[field] = value
                    with self.assertRaises(ValueError):
                        validate_version(data)

    def test_rejects_invalid_upload_code_and_exhausted_range(self):
        for uploaded, current in ((0, 11), (-1, 11),
                                  (2100000000, 2100000001),
                                  (2100000001, 2100000002)):
            with self.subTest(uploaded=uploaded, current=current):
                with self.assertRaises(ValueError):
                    validate_version({
                        "lastPublishedVersionCode": 10,
                        "lastUploadedVersionCode": uploaded,
                        "versionCode": current, "versionName": "109",
                    })

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
