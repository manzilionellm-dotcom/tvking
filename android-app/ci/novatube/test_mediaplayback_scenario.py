#!/usr/bin/env python3
"""Régressions de refus du contrat ; aucun test ne prétend exécuter Android."""

import copy
import unittest

import mediaplayback_scenario as media


class MediaPlaybackScenarioTest(unittest.TestCase):
    def sample(self, phase, second, size):
        uri = "http://192.0.2.10:31531/relay/Abcd1234Ef.ts"
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
                "userCastTargetTap": True, "userStopCastingTap": True,
                "serviceBefore": {"foreground": False, "type": None},
                "serviceDuring": {"foreground": True, "type": 2},
                "serviceBackground": {"foreground": True, "type": 2},
                "serviceAfter": {"foreground": False, "type": None},
                "notificationVisible": True, "notificationRemoved": True, "homeObserved": True, "stillBackground": True,
                "rendererConnected": connected, "rendererBackgroundStart": start, "rendererBackgroundEnd": end,
                "rendererStopped": {"transportState": "STOPPED", "relayConnectionClosed": True,
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
                    good.replace("/relay/", "/direct/"), good + "?different=1", good.replace("Abcd1234Ef", "invalid"),
                    good.replace("http://", "http://user:password@"), "http://127.0.0.1:18765/live/pattern.ts"):
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
            ("rendererStopped", "transportState", "PLAYING"),
            ("rendererStopped", "relayConnectionClosed", False),
            ("rendererStopped", "oldUriHttpStatus", 200),
            ("rendererStopped", "oldUriRefused", False),
            ("rendererStopped", "relayUri", "http://192.0.2.10:31531/relay/Other12345.ts"),
            ("phoneVideoProbe", "decodeScope", "unchecked"),
            ("rendererVideoProbe", "durationSeconds", 30),
        ]
        for group, key, value in mutations:
            bad = copy.deepcopy(original)
            bad[group][key] = value
            with self.subTest(group=group, key=key), self.assertRaises(ValueError):
                media.qualify(bad)
        for key in ("userCastTargetTap", "userStopCastingTap", "notificationVisible", "notificationRemoved", "stillBackground"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                media.qualify({**original, key: False})
        with self.assertRaises(ValueError):
            media.qualify({**original, "serviceBackground": {"foreground": True, "type": 1}})

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


if __name__ == "__main__":
    unittest.main()
