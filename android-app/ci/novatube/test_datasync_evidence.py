#!/usr/bin/env python3
"""Régressions de refus ; ces tests ne simulent pas une preuve Android réussie."""

from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
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

    def test_android35_observed_types_field_keeps_exact_datasync_identity(self):
        # Extrait réel REC5, failure-services.txt, artefact 14117811234.
        raw = ("ACTIVITY MANAGER SERVICES (dumpsys activity services)\n"
               "  * ServiceRecord{ef52dbd u0 com.sevenmotion.novatube/.RecordingForegroundService c:com.sevenmotion.novatube}\n"
               "    isForeground=true foregroundId=1001 types=0x00000001 "
               "foregroundNoti=Notification(channel=recording_channel flags=FOREGROUND_SERVICE actions=1)\n")
        self.assertEqual(evidence.foreground_service(raw), {"foreground": True, "type": 1})
        for bad in (raw.replace('types=0x00000001', 'types=0x00000002'),
                    raw.replace('types=0x00000001', 'types=0x00000003'),
                    raw.replace('types=0x00000001', ''),
                    raw.replace('types=0x00000001', '') + '    other types=0x00000001\n',
                    raw.replace('types=0x00000001', 'types=0x00000001 foregroundServiceType=0x00000001'),
                    raw.replace('foregroundId=1001', 'foregroundId=1002')):
            with self.subTest(raw=bad), self.assertRaises(ValueError):
                evidence.foreground_service(bad)
        self.assertEqual(evidence.foreground_service(raw.replace(evidence.PACKAGE, 'other.app')),
                         {"foreground": False, "type": None})

    def test_observed_m3u_form_exposes_an_unlabelled_editor(self):
        # Extrait des nœuds réels de phone-unqualified-ui.xml,
        # artefact 14116006161 du run 43599127964. Le libellé flottant
        # « M3U URL » visible sur le PNG n'existe pas dans ce XML.
        title = '<node package="com.sevenmotion.novatube" class="android.view.View" content-desc="Add my source" enabled="true" bounds="[168,105][1038,214]"/>'
        mode = '<node package="com.sevenmotion.novatube" class="android.view.View" content-desc="M3U / URL" enabled="true" clickable="true" bounds="[434,567][735,685]"/>'
        editor = '<node NAF="true" package="com.sevenmotion.novatube" class="android.widget.EditText" text="" content-desc="" enabled="true" password="false" focused="true" bounds="[42,867][1038,1021]"/>'
        xml = '<hierarchy>' + title + mode + editor + '</hierarchy>'
        self.assertNotIn(evidence.normalized("M3U URL"), evidence.observed_labels(xml))
        self.assertEqual(evidence.m3u_editor_bounds(xml, "Add my source", "M3U / URL"), (42, 867, 1038, 1021))
        for bad in (xml.replace(title, ""), xml.replace(mode, ""),
                    xml.replace(editor, editor + editor),
                    xml.replace('password="false"', 'password="true"'),
                    xml.replace(evidence.PACKAGE, "com.other.app"),
                    xml.replace('[1038,1021]', '[1200,1021]')):
            with self.subTest(xml=bad), self.assertRaises(ValueError):
                evidence.m3u_editor_bounds(bad, "Add my source", "M3U / URL")

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

    def test_observed_native_video_container_is_specific_and_unambiguous(self):
        # Nœuds du vrai 09-live-player.xml, run 43599920601/artifact14116232276.
        # Le PNG montre la mire dans ces bounds ; aucune SurfaceView nommée
        # n'existe dans le XML. Ces nombres sont une donnée de test seulement.
        common = 'package="com.sevenmotion.novatube" text="" content-desc="" enabled="true" clickable="false" scrollable="false" long-clickable="false" bounds="[0,656][1079,1263]"'
        container = '<node class="android.widget.FrameLayout" ' + common + '><node class="android.view.View" ' + common + '/></node>'
        xml = '<hierarchy>' + container + '</hierarchy>'
        self.assertEqual(evidence.video_surfaces(xml), [(0, 656, 1079, 1263)])
        for bad in (xml.replace(evidence.PACKAGE, "com.other.app"),
                    xml.replace('content-desc=""', 'content-desc="Other widget"'),
                    xml.replace('clickable="false"', 'clickable="true"'),
                    xml.replace('scrollable="false"', 'scrollable="true"'),
                    xml.replace('[0,656][1079,1263]', '[0,0][1080,1920]'),
                    xml.replace('[0,656][1079,1263]', '[0,0][1000,750]'),
                    xml.replace('[0,656][1079,1263]', '[0,0][320,180]'),
                    xml.replace('[0,656][1079,1263]', '[0,656][1078,1263]', 1)):
            with self.subTest(xml=bad):
                self.assertEqual(evidence.video_surfaces(bad), [])
        with self.assertRaises(ValueError):
            evidence.video_surfaces('<hierarchy>' + container + container + '</hierarchy>')

    def test_a_bounded_ts_tail_does_not_allow_truncated_screen_video(self):
        original = self.observations()
        for key, update in (("recordingProbe", {"decodedSeconds": 5}),
                            ("recordingProbe", {"excludedTailSeconds": 2}),
                            ("recordingProbe", {"decodeScope": "unchecked"}),
                            ("videoProbe", {"decodeScope": "all-except-final-1s", "excludedTailSeconds": 1})):
            with self.subTest(key=key, update=update), self.assertRaises(ValueError):
                evidence.qualify({**original, key: {**original[key], **update}})

    def observed_player_controls(self):
        # Nœuds observés : lecteur masqué REC3, barre visible REC2.
        # Une suite XML teste la navigation, jamais une réussite Android.
        common = 'package="com.sevenmotion.novatube" text="" content-desc="" enabled="true" clickable="false" scrollable="false" long-clickable="false" bounds="[0,656][1079,1263]"'
        video = '<node class="android.widget.FrameLayout" ' + common + '><node class="android.view.View" ' + common + '/></node>'
        channel = '<node package="com.sevenmotion.novatube" class="android.view.View" content-desc="NT&#10;Novatube_test_pattern&#10;LIVE&#10;Demonstration&#10;1 / 1" enabled="true" bounds="[0,0][1080,1920]"/>'
        rec = '<node package="com.sevenmotion.novatube" class="android.view.View" content-desc="REC" enabled="true" clickable="true" bounds="[330,1521][493,1752]"/>'
        return video, channel, rec

    def test_hidden_controls_are_revealed_and_rec_uses_the_fresh_recognized_xml(self):
        video, channel, rec = self.observed_player_controls()
        hidden = '<hierarchy>' + video + '</hierarchy>'
        visible = '<hierarchy>' + video + channel + rec + '</hierarchy>'
        device = Mock()
        device.hierarchy.side_effect = [hidden, visible]
        with tempfile.TemporaryDirectory() as directory, patch.object(evidence.time, "sleep"):
            flow = evidence.Scenario(device, None, {}, Path(directory))
            xml = flow.player_controls([evidence.CHANNEL, "REC"])
            flow.tap_rectangle(evidence.target_bounds(xml, "REC"), "REC")
            self.assertEqual(xml, visible)
            self.assertEqual(device.hierarchy.call_count, 2)
            self.assertEqual([item.args for item in device.command.call_args_list], [
                ("shell", "input", "tap", "539", "959"),
                ("shell", "input", "tap", "411", "1636"),
            ])
            self.assertEqual(flow.events[-1]["target"], "REC")

    def test_player_controls_still_require_both_channel_and_rec_in_novatube(self):
        video, channel, rec = self.observed_player_controls()
        cases = [(partial, [evidence.CHANNEL, "REC"]) for partial in (
            video + channel, video + rec,
            (video + channel + rec).replace(evidence.PACKAGE, "other.app"), "")]
        # Après le tap REC, attendre Stop ne doit jamais retoucher REC.
        cases.append((video + channel + rec, [evidence.CHANNEL, "Stop"]))
        for partial, required in cases:
            now, device = [0], Mock()
            device.hierarchy.return_value = '<hierarchy>' + partial + '</hierarchy>'
            def advance(seconds):
                now[0] += seconds
            with self.subTest(xml=partial), tempfile.TemporaryDirectory() as directory, \
                    patch.object(evidence.time, "monotonic", side_effect=lambda: now[0]), \
                    patch.object(evidence.time, "sleep", side_effect=advance):
                flow = evidence.Scenario(device, None, {}, Path(directory))
                with self.assertRaises(ValueError):
                    flow.player_controls(required, timeout=2)
                device.command.assert_not_called()

    def test_portrait_container_requires_recording_title_and_stays_replay_only(self):
        video, channel, _ = self.observed_player_controls()
        # Le wrapper est observé sur le direct ; sa taille portrait vient
        # du StackFit.expand de relecture et reste à confirmer sur Android.
        portrait = video.replace('[0,656][1079,1263]', '[0,0][1080,1794]')
        xml = '<hierarchy>' + portrait + channel + '</hierarchy>'
        self.assertEqual(evidence.replay_video_bounds(xml), (0, 0, 1080, 1794))
        self.assertEqual(evidence.video_surfaces(xml), [])
        for bad in (xml.replace(channel, ''), xml.replace(evidence.PACKAGE, 'other.app'),
                    xml.replace('class="android.view.View"', 'class="io.flutter.embedding.android.FlutterSurfaceView"'),
                    xml.replace('clickable="false"', 'clickable="true"'),
                    xml.replace('content-desc=""', 'content-desc="Flutter root"'),
                    xml.replace(portrait, portrait + portrait),
                    xml.replace(portrait, video),
                    xml.replace('[0,0][1080,1794]', '[0,0][1081,1794]'),
                    xml.replace('[0,0][1080,1794]', '[0,0][1080,1793]', 1),
                    '<hierarchy>' + channel + '<node class="android.view.View" package="com.sevenmotion.novatube" bounds="[0,0][1080,1920]"/></hierarchy>'):
            with self.subTest(xml=bad), self.assertRaises(ValueError):
                evidence.replay_video_bounds(bad)

    def test_replay_motion_requires_opened_recording_and_fully_stopped_source(self):
        alive_thread, alive_process = Mock(), Mock()
        alive_thread.is_alive.return_value = True
        alive_process.poll.return_value = None
        cases = [(False, {}), (True, {'stopped': False}), (True, {'server': object()}),
                 (True, {'thread': alive_thread}), (True, {'processes': {alive_process}})]
        for opened, changes in cases:
            device = Mock()
            state = dict(stopped=True, server=None, thread=None, processes=set(), lock=threading.Lock())
            with self.subTest(opened=opened, fields=list(changes)), tempfile.TemporaryDirectory() as directory:
                flow = evidence.Scenario(device, None, {}, Path(directory))
                flow.replay_opened = opened
                with self.assertRaises(ValueError):
                    flow.motion('replay', fixture_server=SimpleNamespace(**{**state, **changes}))
                device.hierarchy.assert_not_called()
                device.binary.assert_not_called()

    def test_truncated_video_and_out_of_order_actions_are_not_evidence(self):
        for timeline in ([2, 6, 20, 65], [2, 20, 6, 55], [2, 6, 9, 55], [], [2, 6, 20, float("nan")]):
            with self.subTest(timeline=timeline), self.assertRaises(ValueError):
                evidence.qualify({**self.observations(), "videoTimeline": timeline})

    def test_initial_live_contrast_wait_is_bounded_and_does_not_replace_motion(self):
        video, _, _ = self.observed_player_controls()
        # Contraste réel REC6 = 2. Le seuil exact 25 ne suffit toujours pas.
        for contrasts, accepted, capture_delay in (([2, 25, 26], True, 0), ([2, 2], False, 0), ([26], False, 3)):
            now, device, helpers = [0], Mock(), Mock()
            device.hierarchy.return_value = '<hierarchy>' + video + '</hierarchy>'
            device.binary.return_value = b'diagnostic-png'
            helpers.png_dimensions.return_value = (1080, 1920)
            def advance(seconds):
                now[0] += seconds
            samples = [bytes([0, value]) * (64 * 36 // 2) for value in contrasts]
            def next_sample(*arguments, **keywords):
                now[0] += capture_delay
                return samples.pop(0)
            with self.subTest(contrasts=contrasts), tempfile.TemporaryDirectory() as directory, \
                    patch.object(evidence.time, "monotonic", side_effect=lambda: now[0]), \
                    patch.object(evidence.time, "sleep", side_effect=advance), \
                    patch.object(evidence, "command", side_effect=next_sample):
                flow = evidence.Scenario(device, helpers, {}, Path(directory))
                with patch.object(flow, "motion") as motion:
                    if accepted:
                        flow.await_live_contrast(timeout=3)
                    else:
                        with self.assertRaises(ValueError):
                            flow.await_live_contrast(timeout=2)
                    motion.assert_not_called()
                seen = [event for event in flow.events if event["action"] == "live-readiness-sample"]
                self.assertEqual([event["contrastRange"] for event in seen], contrasts)
                self.assertEqual([event["elapsedSeconds"] for event in seen],
                                 [index + (index + 1) * capture_delay for index in range(len(contrasts))])
                self.assertEqual(len(list(Path(directory).glob('live-readiness-*.png'))), len(contrasts))
                device.command.assert_not_called()

    def test_rec_target_freshness_reserves_a_second_before_overlay_expiry(self):
        with tempfile.TemporaryDirectory() as directory:
            flow = evidence.Scenario(Mock(), None, {}, Path(directory))
            self.assertFalse(flow.controls_are_fresh())
            flow.controls_revealed_at = 100
            for stamp, expected in ((100, True), (104.999, True), (105, False),
                                    (106.081, False), (99.99, False)):
                with self.subTest(stamp=stamp), patch.object(evidence.time, "monotonic", return_value=stamp):
                    self.assertEqual(flow.controls_are_fresh(), expected)

    def test_reveal_is_followed_immediately_by_xml_and_expired_rec_is_never_returned(self):
        video, channel, rec = self.observed_player_controls()
        hidden = '<hierarchy>' + video + '</hierarchy>'
        visible = '<hierarchy>' + video + channel + rec + '</hierarchy>'
        # REC4 a rendu le XML à 6,081 s : il ne doit plus autoriser un tap.
        for dump_seconds, accepted in ((4.5, True), (6.081, False)):
            now, calls, device = [0], [0], Mock()
            def hierarchy():
                calls[0] += 1
                if calls[0] == 1:
                    return hidden
                now[0] += dump_seconds
                return visible
            def advance(seconds):
                now[0] += seconds
            device.hierarchy.side_effect = hierarchy
            with self.subTest(dump_seconds=dump_seconds), tempfile.TemporaryDirectory() as directory, \
                    patch.object(evidence.time, "monotonic", side_effect=lambda: now[0]), \
                    patch.object(evidence.time, "sleep", side_effect=advance) as sleep:
                flow = evidence.Scenario(device, None, {}, Path(directory))
                if accepted:
                    self.assertEqual(flow.player_controls([evidence.CHANNEL, "REC"], timeout=5, fresh=True), visible)
                    sleep.assert_not_called()
                else:
                    with self.assertRaises(ValueError):
                        flow.player_controls([evidence.CHANNEL, "REC"], timeout=5, fresh=True)
                self.assertEqual(calls[0], 2)
                self.assertEqual([item.args for item in device.command.call_args_list], [
                    ("shell", "input", "tap", "539", "959")])


if __name__ == "__main__":
    unittest.main()
