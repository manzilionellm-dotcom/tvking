"""Exporte uniquement les champs numériques et les phases connues des sondes."""
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys
import time

pattern=re.compile(r'ZUNO_PHASE (dart_zap|dart_open|native_open|prepare|decoder_ready|native_first_render) ticks=(\d+)(?: channel=(A|B|unknown) gen=(\d+) event_ms=(-?\d+))?')
monotonic=re.compile(r'^\[?\s*(\d+\.\d+)')
with subprocess.Popen(['adb','logcat','-v','monotonic','-T','1','ZunoLabPhase:I','flutter:I','*:S'],
                      stdout=subprocess.PIPE,text=True,errors='replace') as proc:
    with Path(sys.argv[1]).open('a',buffering=1) as output:
        for line in proc.stdout:
            m=pattern.search(line)
            if not m: continue
            clock=monotonic.search(line)
            print(json.dumps(dict(phase=m[1],runtime_ticks=int(m[2]),channel=m[3],
                                  generation=int(m[4]) if m[4] else None,
                                  media_event_ms=int(m[5]) if m[5] else None,
                                  android_log_s=float(clock[1]) if clock else None,
                                  host_received_s=time.monotonic(),utc=datetime.datetime.now(datetime.timezone.utc).isoformat())),file=output)
