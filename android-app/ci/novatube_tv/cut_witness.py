"""Continuously checks a fresh complete MPEG-TS segment at the ungated origin and the route status."""
import json
from pathlib import Path
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

out = Path(sys.argv[1])
headers = {'X-QA-Witness': 'independent'}


def read(port, path):
    with urlopen(Request(f'http://127.0.0.1:{port}/A/{path}', headers=headers), timeout=2) as response:
        return response.read()


with (out / 'witness.jsonl').open('w', buffering=1) as log:
    while True:
        row = {'start': time.monotonic()}
        try:
            manifest = read(18473, 'index.m3u8')
            segment = manifest.decode().strip().splitlines()[-1]
            data = read(18473, segment)
            row.update(origin_segment=segment, origin_bytes=len(data), transport_sync=len(data) >= 188 and len(data)%188 == 0 and data[0] == data[188] == 71)
            for path, key in [('index.m3u8','manifest_code'), (segment,'segment_code')]:
                try:
                    read(18471, path)
                    row[key] = 200
                except HTTPError as exc:
                    row[key] = exc.code
        except Exception as exc:
            row['error'] = str(exc)
        row['end'] = time.monotonic()
        print(json.dumps(row), file=log)
        time.sleep(.65)
