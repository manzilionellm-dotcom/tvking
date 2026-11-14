"""Refus du banc et des courses d'observation, sans réseau ni Android."""
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import mediaplayback_observations as observed
import mediaplayback_runtime as runtime
import run_mediaplayback_evidence as ci


class MediaPlaybackRuntimeTest(unittest.TestCase):
    def test_namespace_guards_refuse_each_parent_view_before_any_action(self):
        for net, mount, pid, uid in (("net-parent", "mnt-child", 1, 0),
                                      ("net-child", "mnt-parent", 1, 0),
                                      ("net-child", "mnt-child", 2, 0),
                                      ("net-child", "mnt-child", 1, 1000)):
            with self.subTest(net=net, mount=mount, pid=pid, uid=uid), \
                 patch.object(runtime.os, "geteuid", return_value=uid), \
                 patch.object(runtime.os, "getpid", return_value=pid), \
                 patch.object(runtime.os, "readlink", side_effect=[net, mount]), \
                 self.assertRaises(ValueError):
                runtime.namespace_guards("net-parent", "mnt-parent")

    def test_context_refuses_actor_intent_branch_sha_and_secrets(self):
        owner, sha = ci.REPOSITORY.split("/")[0], "f" * 40
        env = {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REPOSITORY": ci.REPOSITORY, "GITHUB_REPOSITORY_OWNER": owner,
            "GITHUB_REF": "refs/heads/" + ci.BRANCH, "GITHUB_ACTOR": owner,
            "GITHUB_TRIGGERING_ACTOR": owner, "GITHUB_WORKFLOW_SHA": sha,
            "GITHUB_WORKFLOW_REF": ci.REPOSITORY + "/" + ci.WORKFLOW + "@refs/heads/" + ci.BRANCH,
            "GITHUB_SHA": sha, "REVIEWED_COMMIT": sha, "GITHUB_JOB": ci.JOB,
            "NOVATUBE_MEDIAPLAYBACK_CONFIRMATION": ci.CONFIRMATION,
            "GITHUB_RUN_ID": "1", "GITHUB_RUN_ATTEMPT": "1"}
        self.assertEqual(ci.context(env)["appCommit"], ci.rec.APP_COMMIT)
        for key, value in (("GITHUB_ACTOR", "visitor"), ("GITHUB_TRIGGERING_ACTOR", "visitor"),
                           ("REVIEWED_COMMIT", "a" * 40), ("GITHUB_REF", "refs/heads/main"),
                           ("NOVATUBE_MEDIAPLAYBACK_CONFIRMATION", "COMPILER_NOVATUBE"),
                           ("GH_TOKEN", "forbidden"), ("NOVATUBE_UPLOAD_KEY_ALIAS", "forbidden")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                ci.context({**env, key: value})

    def test_tcp_retransmission_and_reordering_never_inflate_body_bytes(self):
        prefix = observed.Prefix()
        prefix.start = 100
        raw = b"HTTP/1.1 200 OK\r\nContent-Type: video/mp2t\r\n\r\n" + b"z" * 4000
        prefix.feed(200, raw[100:1500])
        prefix.feed(100, raw[:300])
        prefix.feed(150, raw[50:])
        prefix.feed(100, raw)
        self.assertEqual(prefix.body_bytes(), 4000)

    def test_uri_change_during_soap_reads_cannot_be_recorded_as_direct_stopped(self):
        probe = observed.RendererProbe.__new__(observed.RendererProbe)
        probe.done = Mock()
        probe.done.is_set.side_effect = [False, True]
        media = lambda value: ('<root><CurrentURI>' + value + '</CurrentURI></root>').encode()
        probe.soap = Mock(side_effect=[media(observed.DIRECT_URI),
            b"<root><CurrentTransportState>STOPPED</CurrentTransportState></root>",
            media("http://192.0.2.17:12345/relay/Abcd1234Ef.ts")])
        probe.command, probe.pcap, probe.loopback = Mock(return_value=""), Mock(), Mock()
        probe.lock, probe.counter, probe.history, probe.errors = threading.Lock(), 0, [], []
        with tempfile.TemporaryDirectory() as folder:
            probe.stage = Path(folder)
            probe.watch()
        self.assertEqual(probe.history, [])
        self.assertIn("URI Rygel modifiée", probe.errors[0]["error"])

    def test_stale_stopped_does_not_authorize_old_token_http_probe(self):
        probe = observed.RendererProbe.__new__(observed.RendererProbe)
        probe.guest_ip, probe.lock = "192.0.2.17", threading.Lock()
        probe.history = [{"transportState": "STOPPED", "wallTime": 90}]
        probe.pcap = Mock()
        probe.pcap.relay.return_value = {"relayConnectionClosed": True}
        with patch.object(observed.time, "time", return_value=100), \
             patch.object(observed.time, "monotonic", side_effect=[0, 0, 2]), \
             patch.object(observed.time, "sleep"), \
             patch.object(observed.http.client, "HTTPConnection") as connection, \
             self.assertRaises(ValueError):
            probe.wait_stopped("http://192.0.2.17:12345/relay/Abcd1234Ef.ts", timeout=1)
        connection.assert_not_called()


if __name__ == "__main__":
    unittest.main()
