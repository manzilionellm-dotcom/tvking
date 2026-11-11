import unittest

from recording_device_evidence import TEST_CLASS, TEST_METHODS, instrumentation_results


def good_report():
    return "".join(
        f"INSTRUMENTATION_STATUS: class={TEST_CLASS}\nINSTRUMENTATION_STATUS: test={name}\n"
        "INSTRUMENTATION_STATUS_CODE: 0\n" for name in TEST_METHODS
    ) + "OK (3 tests)\nINSTRUMENTATION_CODE: -1\n"


class AndroidEvidenceTest(unittest.TestCase):
    def test_three_completed_media_tests_are_required(self):
        self.assertEqual(instrumentation_results(good_report()), 3)

    def test_interrupted_android_run_is_not_a_success(self):
        with self.assertRaises(ValueError):
            instrumentation_results(good_report().replace("INSTRUMENTATION_CODE: -1", ""))

    def test_wrong_test_cannot_reuse_a_successful_summary(self):
        with self.assertRaises(ValueError):
            instrumentation_results(good_report().replace(TEST_METHODS[0], "unrelatedTest"))

    def test_a_failed_or_skipped_test_cannot_be_hidden_by_summary(self):
        for code in (-1, -2, -3, -4):
            with self.subTest(code=code), self.assertRaises(ValueError):
                instrumentation_results(good_report().replace("STATUS_CODE: 0", f"STATUS_CODE: {code}", 1))

    def test_duplicate_completion_is_rejected(self):
        with self.assertRaises(ValueError):
            instrumentation_results(good_report() + good_report())


if __name__ == "__main__":
    unittest.main()
