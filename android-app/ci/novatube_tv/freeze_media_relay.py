"""Local TCP relay for the isolated emulator fixture. The origin stays reachable directly."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import selectors
import signal
import socket
import socketserver
import threading
import time


LISTEN = ('127.0.0.1', 18472)
ORIGIN = ('127.0.0.1', 18471)


class Relay(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    request_queue_size = 64

    def __init__(self, log):
        self.log = log
        self.lock = threading.Lock()
        super().__init__(LISTEN, RelayConnection)

    def record(self, phase, **fields):
        with self.lock:
            self.log.write(json.dumps({'phase': phase, 'host_monotonic': time.monotonic(),
                                       'utc': datetime.now(timezone.utc).isoformat(), **fields}) + '\n')


class RelayConnection(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        start = time.monotonic()
        traffic = {'client_to_origin_bytes': 0, 'origin_to_client_bytes': 0}
        reason = 'eof'
        try:
            with socket.create_connection(ORIGIN, timeout=4) as origin, selectors.DefaultSelector() as sel:
                # A closed write half does not discard the reverse direction.
                for src, dst, direction in [(client,origin,'client_to_origin_bytes'),
                                           (origin,client,'origin_to_client_bytes')]:
                    src.settimeout(15)
                    sel.register(src,selectors.EVENT_READ,(dst,direction))
                while sel.get_map():
                    events = sel.select(20)
                    if not events:
                        reason='idle_timeout'
                        break
                    for key,_ in events:
                        data = key.fileobj.recv(65536)
                        peer,direction = key.data
                        if data:
                            peer.sendall(data)
                            traffic[direction] += len(data)
                        else:
                            sel.unregister(key.fileobj)
                            try:
                                peer.shutdown(socket.SHUT_WR)
                            except OSError:
                                pass
        except OSError as exc:
            reason=f'{type(exc).__name__}({exc.errno})'
        finally:
            self.server.record('connection', start_monotonic=start,
                               duration_s=round(time.monotonic()-start,4),
                               peer_host=self.client_address[0], reason=reason, **traffic)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('out',type=Path)
    args=p.parse_args()
    args.out.mkdir(parents=True,exist_ok=True)
    stop=threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    with (args.out/'media-relay.jsonl').open('a',buffering=1) as log, Relay(log) as relay:
        relay.timeout=.5
        relay.record('ready',listen=LISTEN,origin=ORIGIN)
        while not stop.is_set():
            relay.handle_request()
        relay.record('stop')


if __name__ == '__main__':
    main()
