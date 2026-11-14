"""Refus du banc et des courses d'observation, sans réseau ni Android."""
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import mediaplayback_observations as observed
import mediaplayback_runtime as runtime
import run_mediaplayback_evidence as ci


class MediaPlaybackRuntimeTest(unittest.TestCase):
    def test_original_helpers_cannot_replace_the_reviewed_ui_scenario(self):
        # Un processus Python neuf évite que les imports des autres tests
        # masquent le défaut. Le second checkout contient un scénario ancien ;
        # ses helpers sont voulus, mais son scénario ne doit jamais remplacer
        # celui du banc courant. Aucun appareil ou résultat vidéo n'est simulé.
        with tempfile.TemporaryDirectory() as folder:
            original = Path(folder)
            modules = original / "ci/novatube"
            modules.mkdir(parents=True)
            (modules / "run_play_evidence.py").write_text("ORIGIN = 'binary-helpers'\n")
            (modules / "mediaplayback_scenario.py").write_text(
                "raise AssertionError('Le scénario archivé ne doit pas être chargé')\n")
            code = """
from pathlib import Path
import sys
current, original = map(Path, sys.argv[1:])
sys.path.insert(0, str(current))
import mediaplayback_runtime as runtime
helpers = runtime.rec.original_helpers(original)
assert Path(helpers.__file__).parent == original / 'ci/novatube'
from mediaplayback_scenario import execute_ui
assert execute_ui is runtime.execute_ui
assert Path(sys.modules[execute_ui.__module__].__file__).parent == current
"""
            result = subprocess.run([sys.executable, "-c", code,
                str(Path(__file__).resolve().parent), str(original)],
                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

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

    def test_passive_set_uri_rejection_requires_complete_matching_soap_exchange(self):
        # Format de la vraie capture média2. Ces octets ne sont jamais envoyés
        # à l'app ou au renderer : on teste seulement le lecteur passif PCAP.
        service = 'urn:schemas-upnp-org:service:AVTransport:1'
        request_body = ('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
            '<u:SetAVTransportURI xmlns:u="' + service + '"><InstanceID>0</InstanceID><CurrentURI>'
            + observed.DIRECT_URI + '</CurrentURI><CurrentURIMetaData></CurrentURIMetaData>'
            '</u:SetAVTransportURI></s:Body></s:Envelope>').encode()
        response_body = ('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
            '<faultcode>s:Client</faultcode><detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'
            '<errorCode>716</errorCode><errorDescription>Resource not found</errorDescription>'
            '</UPnPError></detail></s:Fault></s:Body></s:Envelope>').encode()
        request = (b'POST /Control/Playbin/RygelAVTransport HTTP/1.1\r\nsoapaction: "'
            + service.encode() + b'#SetAVTransportURI"\r\ncontent-length: '
            + str(len(request_body)).encode() + b'\r\n\r\n' + request_body)
        response = (b'HTTP/1.1 500 Internal server error\r\nContent-Length: '
            + str(len(response_body)).encode() + b'\r\n\r\n' + response_body)
        control = 'http://192.0.2.1:19494/Control/Playbin/RygelAVTransport'

        def read(incoming, outgoing, port=19494):
            pcap = observed.Pcap(Path('/unused'), '192.0.2.17', 325)
            flow = {'request': observed.Prefix(), 'response': observed.Prefix(), 'firstAt': 100, 'lastAt': 101}
            for key, data in (('response', incoming), ('request', outgoing)):
                flow[key].start = 1
                flow[key].feed(1, data)
            pcap.flows[(port, 34610)] = flow
            return pcap.direct_rejections(control)

        self.assertEqual(read(request, response)[0]['upnpErrorCode'], 716)
        invalid = [(request, response[:-1], 19494), (request[:-1], response, 19494),
            (request.replace(b'pattern.mp4', b'foreign.mp4'), response, 19494),
            (request, response.replace(b'>716<', b'>714<'), 19494),
            (request, response.replace(b'500', b'200'), 19494),
            (request.replace(b'#SetAVTransportURI', b'#GetTransportInfo'), response, 19494),
            (request.replace(b'POST /Control/', b'POST /OtherXX/'), response, 19494),
            (request, response, 19495)]
        for incoming, outgoing, port in invalid:
            with self.subTest(port=port, incoming=incoming, outgoing=outgoing):
                self.assertEqual(read(incoming, outgoing, port), [])

    def test_uri_change_during_soap_reads_cannot_be_recorded_as_direct_stopped(self):
        probe = observed.RendererProbe.__new__(observed.RendererProbe)
        probe.done = Mock()
        probe.done.is_set.side_effect = [False, True]
        media = lambda value: ('<root><CurrentURI>' + value + '</CurrentURI></root>').encode()
        probe.soap = Mock(side_effect=[media(observed.DIRECT_URI),
            b"<root><CurrentTransportState>STOPPED</CurrentTransportState></root>",
            media("http://192.0.2.17:12345/relay/Abcd1234Ef.mp4")])
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
            probe.wait_stopped("http://192.0.2.17:12345/relay/Abcd1234Ef.mp4", timeout=1)
        connection.assert_not_called()


if __name__ == "__main__":
    unittest.main()
