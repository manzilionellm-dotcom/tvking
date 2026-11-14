"""Régressions des gardes CI du diagnostic ; aucun émulateur n'est exécuté."""
from pathlib import Path
import tempfile
import unittest

import run_tap_diagnostic as diagnostic


class TapCiTest(unittest.TestCase):
    def environment(self):
        owner = diagnostic.REPOSITORY.split("/", 1)[0]
        return {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "workflow_dispatch",
                "GITHUB_REPOSITORY": diagnostic.REPOSITORY, "GITHUB_REPOSITORY_OWNER": owner,
                "GITHUB_REF": "refs/heads/" + diagnostic.BRANCH,
                "GITHUB_ACTOR": owner, "GITHUB_TRIGGERING_ACTOR": owner,
                "GITHUB_SHA": "b" * 40, "REVIEWED_COMMIT": "b" * 40,
                "GITHUB_WORKFLOW_REF": diagnostic.REPOSITORY + "/" + diagnostic.WORKFLOW +
                                       "@refs/heads/" + diagnostic.BRANCH,
                "GITHUB_WORKFLOW_SHA": "b" * 40, "GITHUB_JOB": diagnostic.JOB,
                "GITHUB_RUN_ID": "999", "GITHUB_RUN_ATTEMPT": "1",
                "NOVATUBE_CAST_DIAGNOSTIC_CONFIRMATION": diagnostic.CONFIRMATION}

    def test_manual_owner_branch_sha_workflow_and_intent_are_all_required(self):
        env = self.environment()
        context = diagnostic.runtime_context(env)
        self.assertEqual(context["scriptCommit"], "b" * 40)
        self.assertTrue(all(context[key] is False for key in diagnostic.FALSE_EVIDENCE_FIELDS))
        for name, value in {
            "GITHUB_ACTIONS": "false", "GITHUB_EVENT_NAME": "push", "GITHUB_REPOSITORY": "other/repo",
            "GITHUB_REPOSITORY_OWNER": "other", "GITHUB_REF": "refs/heads/main",
            "GITHUB_ACTOR": "other", "GITHUB_TRIGGERING_ACTOR": "other", "REVIEWED_COMMIT": "a" * 40,
            "GITHUB_WORKFLOW_REF": "other/workflow@main", "GITHUB_WORKFLOW_SHA": "a" * 40,
            "GITHUB_JOB": "release", "GITHUB_RUN_ATTEMPT": "", "GITHUB_SHA": "short",
            "NOVATUBE_CAST_DIAGNOSTIC_CONFIRMATION": "CAPTURER_NOVATUBE_DATASYNC",
            "NOVATUBE_UPLOAD_KEYSTORE_BASE64": "forbidden", "GITHUB_TOKEN": "forbidden",
        }.items():
            with self.subTest(name=name), self.assertRaises(ValueError):
                diagnostic.runtime_context({**env, name: value})

    def test_workflow_bytes_cannot_change_silently(self):
        raw = (diagnostic.REPO_ROOT / diagnostic.WORKFLOW).read_bytes()
        diagnostic.verify_workflow_bytes(raw)
        with self.assertRaises(ValueError):
            diagnostic.verify_workflow_bytes(raw + b"\n")

    def test_namespace_command_has_a_clean_environment_and_forced_pid_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk, java = root / "sdk", root / "jdk"
            sdk.mkdir()
            (java / "bin").mkdir(parents=True)
            (java / "bin/java").write_text("non exécuté")
            renderer = root / "gmediarender"
            renderer.write_text("non exécuté")
            result = diagnostic.isolated_command(sdk, root / "result", java, renderer, "net:[123]")
        self.assertEqual(result[:9], ["sudo", "-n", "unshare", "--net", "--pid", "--fork",
                                      "--mount-proc", "--kill-child=KILL", "/usr/bin/env"])
        self.assertEqual(result[9], "-i")
        self.assertEqual(result[-2:], ["--parent-netns", "net:[123]"])
        self.assertFalse(any("GITHUB_" in part or "TOKEN=" in part or "SECRET=" in part for part in result))


if __name__ == "__main__":
    unittest.main()
