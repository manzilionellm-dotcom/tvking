#!/usr/bin/env python3
"""Régressions : aucune publication privée ni aucun define privé dans l'AAB."""

import copy
import unittest

import yaml

from common import REPO_ROOT
from verify_source import WorkflowLoader, verify_workflow


class WorkflowIsolationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = (REPO_ROOT / ".github/workflows/novatube-play-aab.yml").read_text(encoding="utf-8")
        cls.template = yaml.load(cls.text, Loader=WorkflowLoader)

    def document(self):
        return copy.deepcopy(self.template)

    def step(self, document, step_id):
        return next(step for step in document["jobs"]["release"]["steps"] if step.get("id") == step_id)

    def reject(self, document):
        with self.assertRaises(ValueError):
            verify_workflow(yaml.safe_dump(document, allow_unicode=True))

    def test_reviewed_workflow_keeps_both_modes_isolated(self):
        verify_workflow(self.text)

    def test_push_or_pull_request_cannot_publish_or_build(self):
        for event in ("push", "pull_request", "workflow_run"):
            with self.subTest(event=event):
                document = self.document()
                document["on"][event] = {}
                self.reject(document)

    def test_exact_source_branch_and_owner_are_required(self):
        for old, new in (("inputs.reviewed_commit == github.sha", "true"),
                         ("refs/heads/feature/novatube-play-aab", "refs/heads/main"),
                         ("github.actor == github.repository_owner", "true")):
            for job in ("release", "publish_private"):
                with self.subTest(job=job, old=old):
                    document = self.document()
                    document["jobs"][job]["if"] = document["jobs"][job]["if"].replace(old, new)
                    self.reject(document)

    def test_private_steps_cannot_run_in_play_mode_or_unconditionally(self):
        for step_id in ("tests_private", "build_private_apk", "verify_private_apk", "upload_private_apk"):
            for condition in (None, "always()", "inputs.confirme == 'COMPILER_NOVATUBE'"):
                with self.subTest(step=step_id, condition=condition):
                    document = self.document()
                    self.step(document, step_id)["if"] = condition
                    self.reject(document)

    def test_private_define_cannot_leak_into_play_or_global_environment(self):
        for location in ("build_play_aab", "tests_play", "global_env"):
            with self.subTest(location=location):
                document = self.document()
                if location == "global_env":
                    document["env"]["PRIVATE_MODE"] = "NOVATUBE_PRIVATE_APK=true"
                else:
                    self.step(document, location)["run"] += "\n# NOVATUBE_PRIVATE_APK=true\n"
                self.reject(document)

    def test_extra_dart_defines_cannot_override_the_explicit_commands(self):
        document = self.document()
        document["env"]["DART_DEFINES"] = "external-parameters"
        self.reject(document)

    def test_release_commands_cannot_become_debug_or_change_entrypoint(self):
        for step_id in ("build_play_aab", "build_private_apk"):
            for old, new in (("--release", "--debug"), ("main_zuno_mobile.dart", "main_tv.dart")):
                with self.subTest(step=step_id, old=old):
                    document = self.document()
                    self.step(document, step_id)["run"] = self.step(document, step_id)["run"].replace(old, new)
                    self.reject(document)

    def test_private_suite_must_enable_the_private_feature(self):
        document = self.document()
        step = self.step(document, "tests_private")
        step["run"] = step["run"].replace("--dart-define=NOVATUBE_PRIVATE_APK=true", "")
        self.reject(document)

    def test_real_apk_verifier_cannot_be_replaced_by_success(self):
        document = self.document()
        self.step(document, "verify_private_apk")["run"] = "set -euo pipefail\ntrue\n"
        self.reject(document)

    def test_tests_and_verification_must_precede_artifact_upload(self):
        document = self.document()
        steps = document["jobs"]["release"]["steps"]
        upload = self.step(document, "upload_private_apk")
        steps.remove(upload)
        steps.insert(0, upload)
        self.reject(document)

    def test_test_or_build_failures_cannot_be_ignored(self):
        for step_id in ("analyze", "tests_play", "tests_private", "build_private_apk", "verify_private_apk"):
            with self.subTest(step=step_id):
                document = self.document()
                self.step(document, step_id)["continue-on-error"] = "true"
                self.reject(document)
        document = self.document()
        self.step(document, "tests_private")["run"] = self.step(document, "tests_private")["run"].replace("set -euo pipefail", "set -eu")
        self.reject(document)

    def test_write_permission_is_reserved_to_publication(self):
        document = self.document()
        document["permissions"]["contents"] = "write"
        self.reject(document)
        document = self.document()
        document["jobs"]["release"]["permissions"] = {"contents": "write"}
        self.reject(document)

    def test_publication_requires_success_and_the_same_artifact(self):
        for mutation in ("needs", "confirmation", "artifact"):
            with self.subTest(mutation=mutation):
                document = self.document()
                publish = document["jobs"]["publish_private"]
                if mutation == "needs":
                    publish.pop("needs")
                elif mutation == "confirmation":
                    publish["if"] = publish["if"].replace("PUBLIER_NOVATUBE_APK_PRIVE", "COMPILER_NOVATUBE")
                else:
                    publish["steps"][1]["with"]["name"] = "unverified-apk"
                self.reject(document)

    def test_ambiguous_yaml_keys_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "YAML"):
            verify_workflow(self.text + "\npermissions:\n  contents: write\n")


if __name__ == "__main__":
    unittest.main()
