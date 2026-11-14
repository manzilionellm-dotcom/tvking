#!/usr/bin/env python3
"""Régressions de refus du contrat ; aucun test ne prétend exécuter Android."""

import copy
import unittest
from unittest.mock import Mock

import mediaplayback_scenario as media


class MediaPlaybackScenarioTest(unittest.TestCase):
    def sample(self, phase, second, size):
        uri = "http://192.0.2.10:31531/relay/Abcd1234Ef.mp4"
        return {"phase": phase, "atUtc": f"2026-11-14T14:00:{second:02d}+00:00", "uri": uri, "relayUri": uri,
                "transportState": "PLAYING", "rendererGetObserved": True, "relayConnectionClosed": False,
                "relayBytes": size, "directErrorObserved": True, "directStoppedObserved": True,
                "videoMotion": True, "frameFiles": [phase + f"-{index}.png" for index in range(3)],
                "frameContrast": [100, 105, 106], "frameDifferences": [5.0, 6.0],
                "receiverVideoWindow": {"id": "0x600001", "bounds": [0, 0, 640, 360],
                                        "display": ":94.0", "rendererPid": 1234}}

    def observations(self):
        connected = self.sample("connected", 1, 10000)
        start, end = self.sample("background-start", 5, 20000), self.sample("background-end", 15, 50000)
        video = {"videoCodec": "h264", "durationSeconds": 70, "decodeScope": "entire-file", "excludedTailSeconds": 0}
        return {"guestIp": "192.0.2.10", "notificationPermission": True, "liveMotion": True,
                "rendererName": "NOVATUBE test renderer", "castConnectedLabel": "Casting on",
                "castDescription": "Casting on NOVATUBE test renderer", "castStopLabel": "Stop casting",
                "userCastTargetTap": True, "userCastNotificationStopTap": True,
                "serviceBefore": {"foreground": False, "type": None},
                "serviceDuring": {"foreground": True, "type": 2},
                "serviceBackground": {"foreground": True, "type": 2},
                "serviceAfterNotificationStop": {"foreground": False, "type": None},
                "castNotificationVisible": True, "castNotificationRemoved": True, "homeObserved": True,
                "stillBackground": True, "backgroundAfterNotificationStop": True,
                "castNotificationStop": {"key": "0|com.sevenmotion.novatube|1002|null|10217",
                    "package": media.PACKAGE, "id": 1002, "channel": "cast_playback_channel",
                    "title": media.CHANNEL, "description": "Casting on NOVATUBE test renderer",
                    "actionLabel": "Stop casting", "uiPackage": media.SYSTEM_UI, "appBackgroundAtTap": True,
                    "tapAction": "observed-notification-action0", "actionBounds": [147, 1268, 730, 1394]},
                "rendererConnected": connected, "rendererBackgroundStart": start, "rendererBackgroundEnd": end,
                "rendererStoppedAfterNotification": {"transportState": "STOPPED", "relayConnectionClosed": True,
                                    "relayUri": connected["relayUri"], "relayBytes": 55000,
                                    "oldUriRefused": True, "oldUriHttpStatus": 404},
                "phoneVideoProbe": video, "rendererVideoProbe": copy.deepcopy(video),
                "phoneVideoTimeline": [2, 10, 30, 40], "rendererVideoTimeline": [1, 9, 29, 39]}

    def test_playback_service_is_distinct_from_recording_and_combined_types(self):
        raw = ("  * ServiceRecord{test u0 com.sevenmotion.novatube/.PlaybackForegroundService}\n"
               "    isForeground=true foregroundId=1002 types=0x00000002\n")
        self.assertEqual(media.playback_service(raw), {"foreground": True, "type": 2})
        recording = raw.replace("PlaybackForegroundService", "RecordingForegroundService").replace("1002", "1001").replace("00000002", "00000001")
        self.assertEqual(media.playback_service(recording), {"foreground": False, "type": None})
        for bad in (raw.replace("1002", "1001"), raw.replace("00000002", "00000003"),
                    raw.replace("00000002", "00000001"), raw.replace("types=0x00000002", ""),
                    raw.replace("types=0x00000002", "types=0x00000002 foregroundServiceType=2"), raw + raw):
            with self.subTest(raw=bad), self.assertRaises(ValueError):
                media.playback_service(bad)

    def test_relay_uri_must_belong_to_the_observed_android_address(self):
        good = self.sample("connected", 1, 10000)["relayUri"]
        self.assertEqual(media.validate_relay_uri(good, "192.0.2.10"), good)
        for bad in (good.replace("192.0.2.10", "127.0.0.1"), good.replace("192.0.2.10", "192.0.2.11"),
                    good.replace(".mp4", ".ts"),
                    good.replace("/relay/", "/direct/"), good + "?different=1", good.replace("Abcd1234Ef", "invalid"),
                    good.replace("http://", "http://user:password@"), "http://127.0.0.1:18765/vod/pattern.mp4"):
            with self.subTest(uri=bad), self.assertRaises(ValueError):
                media.validate_relay_uri(bad, "192.0.2.10")

    def test_missing_transfer_decoder_and_direct_failure_observations_are_rejected(self):
        original = self.observations()
        media.qualify(original)
        changes = {"rendererGetObserved": False, "relayConnectionClosed": True, "relayBytes": 0,
                   "directErrorObserved": False, "directStoppedObserved": False, "transportState": "PAUSED_PLAYBACK",
                   "videoMotion": False, "frameContrast": [100, 25, 100], "frameDifferences": [1.0, 5.0],
                   "frameFiles": ["same.png"] * 3, "receiverVideoWindow": {}, "atUtc": "2026-11-14T14:00:15"}
        for key, value in changes.items():
            bad = copy.deepcopy(original)
            bad["rendererBackgroundEnd"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                media.qualify(bad)

    def test_background_continuity_and_real_stop_are_required(self):
        original = self.observations()
        mutations = [
            ("rendererBackgroundEnd", "relayBytes", original["rendererBackgroundStart"]["relayBytes"]),
            ("rendererBackgroundEnd", "atUtc", "2026-11-14T14:00:12+00:00"),
            ("rendererBackgroundEnd", "frameFiles", original["rendererBackgroundStart"]["frameFiles"]),
            ("rendererBackgroundEnd", "phase", "connected"),
            ("rendererStoppedAfterNotification", "transportState", "PLAYING"),
            ("rendererStoppedAfterNotification", "relayConnectionClosed", False),
            ("rendererStoppedAfterNotification", "oldUriHttpStatus", 200),
            ("rendererStoppedAfterNotification", "oldUriRefused", False),
            ("rendererStoppedAfterNotification", "relayUri", "http://192.0.2.10:31531/relay/Other12345.mp4"),
            ("phoneVideoProbe", "decodeScope", "unchecked"),
            ("rendererVideoProbe", "durationSeconds", 30),
        ]
        for group, key, value in mutations:
            bad = copy.deepcopy(original)
            bad[group][key] = value
            with self.subTest(group=group, key=key), self.assertRaises(ValueError):
                media.qualify(bad)
        for key in ("userCastTargetTap", "userCastNotificationStopTap", "castNotificationVisible", "castNotificationRemoved",
                    "stillBackground", "backgroundAfterNotificationStop"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                media.qualify({**original, key: False})
        with self.assertRaises(ValueError):
            media.qualify({**original, "serviceBackground": {"foreground": True, "type": 1}})

    def test_notification_stop_cannot_be_replaced_by_old_app_stop_or_another_row(self):
        original = self.observations()
        old = copy.deepcopy(original)
        old.pop("userCastNotificationStopTap")
        old["userStopCastingTap"] = True
        with self.assertRaises(ValueError):
            media.qualify(old)
        for key, value in (("package", "other.app"), ("id", 1001), ("channel", "playback_channel"),
                           ("appBackgroundAtTap", False), ("uiPackage", media.PACKAGE),
                           ("key", "0|com.sevenmotion.novatube|1001|null|10217"),
                           ("description", "Lecture audio en arrière-plan"), ("actionLabel", "Arrêter"),
                           ("tapAction", "app-stop-button"), ("actionBounds", [])):
            bad = copy.deepcopy(original)
            bad["castNotificationStop"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                media.qualify(bad)

    def test_notification_action_is_scoped_to_unique_enabled_novatube_systemui_row(self):
        # XML de régression structurelle, aucun appareil ni vidéo simulé.
        description, stop_label = "Casting on NOVATUBE test renderer", "Stop casting"
        row = ('<node package="com.android.systemui" resource-id="com.android.systemui:id/expandableNotificationRow" bounds="[32,990][1040,1400]">'
               '<node package="com.android.systemui" resource-id="android:id/app_name_text" text="NOVATUBE"/>'
               '<node package="com.android.systemui" resource-id="android:id/title" text="NOVATUBE_TEST_PATTERN"/>'
               '<node package="com.android.systemui" resource-id="android:id/text" text="Casting on NOVATUBE test renderer"/>'
               '<node package="com.android.systemui" resource-id="android:id/action0" text="STOP CASTING" content-desc="Stop casting" '
               'enabled="true" clickable="true" bounds="[147,1268][730,1394]"/></node>')
        xml = '<hierarchy>' + row + '</hierarchy>'
        self.assertEqual(media.cast_notification_action_bounds(xml, description, stop_label), (147, 1268, 730, 1394))
        for bad in (xml.replace('text="NOVATUBE"', 'text="Other app"'), xml.replace(description, 'Casting on Other renderer'),
                    xml.replace('enabled="true"', 'enabled="false"'), xml.replace('clickable="true"', 'clickable="false"'),
                    xml.replace('android:id/action0', 'android:id/action1'), xml.replace('[147,1268][730,1394]', '[0,0][730,1394]'),
                    xml.replace(media.SYSTEM_UI, media.PACKAGE), '<hierarchy>' + row + row + '</hierarchy>'):
            with self.subTest(xml=bad), self.assertRaises(ValueError):
                media.cast_notification_action_bounds(bad, description, stop_label)

    def test_native_notification_identity_rejects_old_audio_and_wrong_key_or_action(self):
        # Format provenant de NotificationRecord.dump Android15 ; données de
        # test locales, jamais utilisées pour répondre à l'app ou au renderer.
        key = "0|com.sevenmotion.novatube|1002|null|10217"
        record = ('NotificationRecord(0x000001: pkg=com.sevenmotion.novatube user=UserHandle{0} id=1002 tag=null key=' + key + ': Notification())\n'
                  '  key=' + key + '\n'
                  '  effectiveNotificationChannel=NotificationChannel{mId=\'cast_playback_channel\', mName=Diffusion Cast}\n'
                  '    android.title=String (Novatube_test_pattern)\n'
                  '    android.text=String (Casting on NOVATUBE test renderer)\n'
                  '    [0] "Stop casting" -> PendingIntent{00001}\n')
        self.assertEqual(media.cast_notification_identity(record, key, "Casting on NOVATUBE test renderer", "Stop casting")["id"], 1002)
        for bad in (record.replace('id=1002', 'id=1001'), record.replace('cast_playback_channel', 'playback_channel'),
                    record.replace('Casting on NOVATUBE test renderer', 'Lecture audio en arrière-plan'),
                    record.replace('"Stop casting"', '"Arrêter"'), record.replace('PendingIntent{00001}', 'null'),
                    record.replace('pkg=' + media.PACKAGE, 'pkg=other.app'), record + record):
            with self.subTest(record=bad), self.assertRaises(ValueError):
                media.cast_notification_identity(bad, key, "Casting on NOVATUBE test renderer", "Stop casting")
        for invalid in (key.replace('|1002|', '|1001|'), key.replace('0|', '1|', 1), key + '|extra', key + '\n' + key):
            with self.subTest(key=invalid), self.assertRaises(ValueError):
                media.cast_notification_identity(record, invalid, "Casting on NOVATUBE test renderer", "Stop casting")

    def test_cast_button_requires_observed_enabled_unique_semantics(self):
        # Vrai bouton du XML REC7 ; ces bounds ne servent qu'à la régression.
        node = ('<node package="com.sevenmotion.novatube" class="android.widget.Button" '
                'content-desc="Cast to a TV" enabled="true" clickable="true" bounds="[642,118][999,244]"/>')
        xml = '<hierarchy>' + node + '</hierarchy>'
        self.assertEqual(media.unique_button(xml, "Cast to a TV"), (642, 118, 999, 244))
        for bad in (xml.replace(media.PACKAGE, "other.app"), xml.replace('enabled="true"', 'enabled="false"'),
                    xml.replace('clickable="true"', 'clickable="false"'), '<hierarchy>' + node + node + '</hierarchy>'):
            with self.subTest(xml=bad), self.assertRaises(ValueError):
                media.unique_button(bad, "Cast to a TV")

    def test_connected_picker_uses_observed_stop_label_without_claiming_playback(self):
        # Forme réellement observée dans média2 : la feuille n'est pas fermée
        # par le choix. Le vrai Stop de cette feuille n'est pas Stop casting.
        prefix = '<node package="com.sevenmotion.novatube" '
        connected = prefix + 'content-desc="Casting on"/>'
        name = prefix + 'content-desc="NOVATUBE test renderer"/>'
        stop = prefix + 'content-desc="Stop" enabled="true" clickable="true" bounds="[796,1348][993,1474]"/>'
        xml = '<hierarchy>' + connected + name + stop + '</hierarchy>'
        scenario = media.MediaPlaybackScenario.__new__(media.MediaPlaybackScenario)
        scenario.device = Mock()
        scenario.observe = Mock(return_value=xml)
        scenario.translated = {"castConnected": "Casting on", "castStop": "Stop"}.__getitem__
        self.assertEqual(scenario.cast_state("NOVATUBE test renderer", picker=False), xml)
        for bad in (xml.replace('Casting on', 'Searching'), xml.replace('NOVATUBE test renderer', 'Other renderer'),
                    xml.replace('content-desc="Stop"', 'content-desc="Stop casting"'),
                    '<hierarchy>' + connected + name + stop + stop + '</hierarchy>'):
            scenario.observe.return_value = bad
            with self.subTest(xml=bad), self.assertRaises(ValueError):
                scenario.cast_state("NOVATUBE test renderer", picker=False)


if __name__ == "__main__":
    unittest.main()
