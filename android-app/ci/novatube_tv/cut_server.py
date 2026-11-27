"""Two read-only HTTP views of the same locally generated HLS media."""
import functools
import http.server
import json
from pathlib import Path
import threading
import time


def serve(directory, out):
    lock = threading.Lock()

    class Handler(http.server.SimpleHTTPRequestHandler):
        def do_GET(self):
            if self.server.server_port == 18471 and self.path.startswith(('/A/', '/B/')) and (out / 'gate.closed').exists():
                self.send_error(503, 'Scheduled media outage')
                return
            super().do_GET()

        def log_request(self, code='-', size='-'):
            client = self.headers.get('X-QA-Witness') == 'independent'
            row = {'time': time.monotonic(), 'code': int(code), 'path': self.path,
                   'role': 'witness' if client else 'app', 'port': self.server.server_port,
                   'user_agent': self.headers.get('User-Agent', '')}
            with lock, (out / 'http.jsonl').open('a') as log:
                print(json.dumps(row), file=log)

    handler = functools.partial(Handler, directory=str(directory))
    origin = http.server.ThreadingHTTPServer(('127.0.0.1', 18473), handler)
    threading.Thread(target=origin.serve_forever, daemon=True).start()
    return http.server.ThreadingHTTPServer(('127.0.0.1', 18471), handler)
