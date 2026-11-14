#!/usr/bin/env python3
"""Régressions de refus ; ces tests ne simulent pas une preuve Android réussie."""

from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import run_datasync_evidence as evidence


class DataSyncEvidenceTest(unittest.TestCase):
    def environment(self):
        owner = evidence.REPOSITORY.split("/", 1)[0]
        return {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "workflow_dispatch",
                "GITHUB_REPOSITORY": evidence.REPOSITORY, "GITHUB_REPOSITORY_OWNER": owner,
                "GITHUB_REF": "refs/heads/" + evidence.BRANCH, "GITHUB_ACTOR": owner,
                "GITHUB_TRIGGERING_ACTOR": owner, "GITHUB_SHA": "b" * 40,
                "GITHUB_WORKFLOW_REF": evidence.REPOSITORY + "/" + evidence.WORKFLOW + "@refs/heads/" + evidence.BRANCH,
                "GITHUB_WORKFLOW_SHA": "b" * 40, "GITHUB_JOB": "capture_datasync",
                "REVIEWED_COMMIT": "b" * 40, "GITHUB_RUN_ID": "999", "GITHUB_RUN_ATTEMPT": "1",
                "NOVATUBE_DATASYNC_CONFIRMATION": evidence.CONFIRMATION}

    def observations(self):
        return {"notificationPermission": True, "userRecTap": True, "userNotificationStopTap": True,
                "serviceBefore": {"foreground": False, "type": None},
                "serviceDuring": {"foreground": True, "type": 1},
                "serviceBackground": {"foreground": True, "type": 1},
                "serviceAfter": {"foreground": False, "type": None},
                "backgroundSizes": [50000, 250000], "stoppedSizes": [300000, 300000],
                "notificationRemoved": True, "fixtureServerStopped": True,
                "liveMotion": True, "replayMotion": True,
                "recordingProbe": {"videoCodec": "h264", "audioCodec": "aac", "durationSeconds": 12,
                                   "decodedSeconds": 11, "decodeScope": "all-except-final-1s", "excludedTailSeconds": 1},
                "videoProbe": {"videoCodec": "h264", "durationSeconds": 60,
                               "decodeScope": "entire-file", "excludedTailSeconds": 0},
                "videoTimeline": [2, 6, 20, 55]}

    def test_manual_owner_branch_sha_and_intent_remain_required(self):
        env = self.environment()
        self.assertEqual(evidence.runtime_context(env)["scriptCommit"], "b" * 40)
        for name, value in {
            "GITHUB_ACTIONS": "false", "GITHUB_EVENT_NAME": "push", "GITHUB_REPOSITORY": "other/repo",
            "GITHUB_REPOSITORY_OWNER": "other", "GITHUB_REF": "refs/heads/main",
            "GITHUB_ACTOR": "other", "GITHUB_TRIGGERING_ACTOR": "other", "REVIEWED_COMMIT": "a" * 40,
            "GITHUB_WORKFLOW_REF": "other/workflow@main", "GITHUB_WORKFLOW_SHA": "a" * 40, "GITHUB_JOB": "release",
            "NOVATUBE_DATASYNC_CONFIRMATION": "COMPILER_NOVATUBE", "GITHUB_RUN_ATTEMPT": "",
            "NOVATUBE_UPLOAD_KEYSTORE_BASE64": "forbidden",
        }.items():
            with self.subTest(name=name), self.assertRaises(ValueError):
                evidence.runtime_context({**env, name: value})

    def test_script_revision_does_not_replace_original_binary_provenance(self):
        script = evidence.runtime_context(self.environment())
        binary = evidence.original_context()
        self.assertNotEqual(script["scriptCommit"], binary["sourceCommit"])
        self.assertEqual(binary["sourceCommit"], evidence.APP_COMMIT)
        self.assertEqual(binary["runId"], evidence.APP_RUN)
        self.assertEqual(binary["runAttempt"], evidence.APP_ATTEMPT)

    def test_workflow_exact_bytes_reject_changed_authority_or_binary(self):
        raw = (evidence.SCRIPT_ROOT / evidence.WORKFLOW).read_bytes()
        evidence.verify_workflow_bytes(raw)
        # Le YAML reste lisible à la revue ; son empreinte interdit aussi un
        # ajout discret d'étape ou de droit en dehors du scénario approuvé.
        for old, new in (
            (b"contents: read", b"contents: write"), (b"actions: read", b"actions: write"),
            (b"workflow_dispatch:", b"push:"),
            (b"github.triggering_actor == github.repository_owner", b"true"),
            (b"inputs.reviewed_commit == github.sha", b"true"),
            (evidence.APP_RUN.encode(), b"99999999999"),
            (evidence.ARTIFACT_ID.encode(), b"99999999999"),
            (b"if: success()", b"if: always()"),
        ):
            self.assertIn(old, raw)
            with self.subTest(old=old), self.assertRaises(ValueError):
                evidence.verify_workflow_bytes(raw.replace(old, new))
        self.assertIn(evidence.APP_COMMIT.encode(), raw)
        self.assertIn(evidence.CONFIRMATION.encode(), raw)
        marker = b"\n  capture_datasync:\n"
        self.assertEqual(raw.count(marker), 1)
        # Les jobs historiques possèdent leurs secrets propres. Le nouveau
        # job, dernier du fichier exactement épinglé, ne les reçoit jamais.
        own_job = raw.split(marker, 1)[1]
        self.assertNotIn(b"flutter build", own_job)
        self.assertNotIn(b"secrets.", own_job)

    def test_archive_requires_reviewed_hash_and_safe_single_level_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "download"
            source.mkdir()
            archive = source / "binary.zip"
            with zipfile.ZipFile(archive, "w") as writer:
                writer.writestr("build-provenance.json", "{}")
            with self.assertRaises(ValueError):
                evidence.extract_original_archive(source, root / "rejected")
            with patch.object(evidence, "ARCHIVE_SHA256", evidence.digest(archive)):
                output = evidence.extract_original_archive(source, root / "accepted")
                self.assertEqual((output / "build-provenance.json").read_text(), "{}")
            with zipfile.ZipFile(archive, "w") as writer:
                writer.writestr("../escape", "bad")
            with patch.object(evidence, "ARCHIVE_SHA256", evidence.digest(archive)), self.assertRaises(ValueError):
                evidence.extract_original_archive(source, root / "bad-path")
            self.assertFalse((root / "escape").exists())

    def test_only_real_recording_service_type_one_counts(self):
        raw = ("ACTIVITY MANAGER SERVICES\n"
               "  * ServiceRecord{abc u0 com.sevenmotion.novatube/.RecordingForegroundService}\n"
               "    isForeground=true foregroundId=1001 foregroundServiceType=0x00000001\n")
        self.assertEqual(evidence.foreground_service(raw), {"foreground": True, "type": 1})
        self.assertEqual(evidence.foreground_service("(nothing)"), {"foreground": False, "type": None})
        foreign = raw.replace("com.sevenmotion.novatube/", "com.other.app/")
        self.assertEqual(evidence.foreground_service(foreign), {"foreground": False, "type": None})
        for bad in (raw.replace("0x00000001", "0x00000002"), raw.replace("0x00000001", "3"),
                    raw.replace("foregroundServiceType=0x00000001", ""), raw.replace("foregroundId=1001", "foregroundId=1002")):
            with self.subTest(raw=bad), self.assertRaises(ValueError):
                evidence.foreground_service(bad)

    def test_navigation_rejects_other_package_missing_or_outside_elements(self):
        xml = '<hierarchy><node package="com.sevenmotion.novatube" text="REC" bounds="[50,100][150,200]" enabled="true"/></hierarchy>'
        self.assertEqual(evidence.target_bounds(xml, "REC"), (50, 100, 150, 200))
        for bad in (xml.replace(evidence.PACKAGE, "com.other.app"), xml.replace("REC", "Other"),
                    xml.replace("[150,200]", "[1500,200]"), xml.replace('enabled="true"', 'enabled="false"')):
            with self.subTest(xml=bad), self.assertRaises(ValueError):
                evidence.target_bounds(bad, "REC")

    def test_no_qualification_when_any_runtime_proof_is_missing(self):
        original = self.observations()
        evidence.qualify(original)
        changes = {"userRecTap": False, "userNotificationStopTap": False, "notificationPermission": False,
                   "serviceBackground": {"foreground": False, "type": None},
                   "serviceAfter": {"foreground": True, "type": 1},
                   "backgroundSizes": [50000, 50000], "stoppedSizes": [300000, 301000],
                   "notificationRemoved": False, "fixtureServerStopped": False, "replayMotion": False,
                   "recordingProbe": {"videoCodec": "h264", "audioCodec": "aac", "durationSeconds": 0}}
        for key, value in changes.items():
            with self.subTest(key=key), self.assertRaises(ValueError):
                evidence.qualify({**original, key: value})

    def test_stop_action_is_scoped_to_the_actual_recording_notification(self):
        def row(title, channel):
            return ('<node package="com.android.systemui" resource-id="com.android.systemui:id/expandableNotificationRow">'
                    f'<node package="com.android.systemui" text="{title}"/>'
                    f'<node package="com.android.systemui" text="{channel}"/>'
                    '<node package="com.android.systemui" text="Arrêter" bounds="[10,20][70,50]"/></node>')
        actual = row("Enregistrement en cours", evidence.CHANNEL)
        other = row("Other notification", "Other channel")
        selected = evidence.recording_notification('<hierarchy>' + actual + other + '</hierarchy>')
        self.assertNotIn("Other notification", selected)
        self.assertEqual(evidence.target_bounds(selected, "Arrêter", evidence.SYSTEM_UI), (10, 20, 70, 50))
        for xml in (other, '<hierarchy>' + actual + actual + '</hierarchy>'):
            with self.subTest(xml=xml), self.assertRaises(ValueError):
                evidence.recording_notification(xml)

    def test_flutter_surface_or_foreign_player_cannot_be_selected_as_native_video(self):
        xml = '<hierarchy><node package="com.sevenmotion.novatube" class="android.view.SurfaceView" bounds="[0,10][1080,1910]"/></hierarchy>'
        self.assertEqual(evidence.video_surfaces(xml), [(0, 10, 1080, 1910)])
        self.assertEqual(evidence.video_surfaces(xml.replace("android.view.SurfaceView", "io.flutter.embedding.android.FlutterSurfaceView")), [])
        self.assertEqual(evidence.video_surfaces(xml.replace(evidence.PACKAGE, "com.other.app")), [])

    def test_a_bounded_ts_tail_does_not_allow_truncated_screen_video(self):
        original = self.observations()
        for key, update in (("recordingProbe", {"decodedSeconds": 5}),
                            ("recordingProbe", {"excludedTailSeconds": 2}),
                            ("recordingProbe", {"decodeScope": "unchecked"}),
                            ("videoProbe", {"decodeScope": "all-except-final-1s", "excludedTailSeconds": 1})):
            with self.subTest(key=key, update=update), self.assertRaises(ValueError):
                evidence.qualify({**original, key: {**original[key], **update}})

    def test_truncated_video_and_out_of_order_actions_are_not_evidence(self):
        for timeline in ([2, 6, 20, 65], [2, 20, 6, 55], [2, 6, 9, 55], [], [2, 6, 20, float("nan")]):
            with self.subTest(timeline=timeline), self.assertRaises(ValueError):
                evidence.qualify({**self.observations(), "videoTimeline": timeline})


if __name__ == "__main__":
    unittest.main()
