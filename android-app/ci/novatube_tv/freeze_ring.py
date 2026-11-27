"""Capture the scheduler and codec activity leading up to an out-of-band freeze trigger."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

root=Path(sys.argv[1]);dst=root/'perfetto';dst.mkdir(exist_ok=True)
adb=['adb','-s',os.environ.get('ANDROID_SERIAL','emulator-5554')]
stop=False

def terminate(*_):
    global stop
    stop=True

def record(**fields):
    with (dst/'events.jsonl').open('a') as log:log.write(json.dumps({'monotonic':time.monotonic(),'utc':time.time(),**fields})+'\n')

config = b"""
buffers { size_kb: 12288 fill_policy: RING_BUFFER }
buffers { size_kb: 1024 fill_policy: RING_BUFFER }
data_sources { config { name: "linux.ftrace" target_buffer: 0 ftrace_config {
  ftrace_events: "sched/sched_switch" ftrace_events: "sched/sched_waking"
  ftrace_events: "power/cpu_frequency" atrace_categories: "video" atrace_categories: "gfx"
  compact_sched { enabled: true }
} } }
data_sources { config { name: "linux.process_stats" target_buffer: 1
  process_stats_config { scan_all_processes_on_start: true proc_stats_poll_ms: 1000 } } }
trigger_config { trigger_mode: STOP_TRACING triggers { name: "nt_freeze_visible" stop_delay_ms: 1000 } trigger_timeout_ms: 6300000 }
"""
signal.signal(signal.SIGTERM,terminate)
while not (root/'observation-start.json').exists() and not stop:time.sleep(.25)
flag=root/'freeze-trigger'
seen = flag.stat().st_mtime_ns if flag.exists() else 0
for trial in range(4):
    if stop:break
    remote=f'/data/misc/perfetto-traces/nt_freeze_{trial}.pftrace'
    out=dst/f'capture-{trial}.pftrace'
    with (dst/f'command-{trial}.log').open('wb') as log:
        proc=subprocess.Popen(adb+['shell','perfetto','--txt','-c','-','-o',remote],stdin=subprocess.PIPE,stdout=log,stderr=log)
        proc.stdin.write(config);proc.stdin.close()
        record(phase='armed',trial=trial)
        reason='end_of_window'
        while not stop and proc.poll() is None and not (root/'long-result.json').exists():
            stamp=flag.stat().st_mtime_ns if flag.exists() else 0
            if stamp>seen:
                seen=stamp; reason='incident';break
            time.sleep(.25)
        if proc.poll() is None:
            trig=subprocess.run(adb+['shell','/system/bin/trigger_perfetto','nt_freeze_visible'],stdout=log,stderr=log,timeout=10)
            if trig.returncode:
                trig=subprocess.run(adb+['shell','perfetto','--txt','-c','-'],input=b'activate_triggers: "nt_freeze_visible"\n',stdout=log,stderr=log,timeout=10)
            record(phase='trigger_sent',trial=trial,reason=reason,rc=trig.returncode)
            try:proc.wait(timeout=14)
            except subprocess.TimeoutExpired:
                record(phase='trigger_timeout',trial=trial);proc.terminate();break
        get=subprocess.run(adb+['pull',remote,str(out)],capture_output=True,timeout=12)
        record(phase='collected',trial=trial,source_exit=proc.returncode,pull_exit=get.returncode,bytes=out.stat().st_size if out.exists() else 0)
        if reason=='end_of_window' or get.returncode or not out.exists() or out.stat().st_size<64:break
        # Incident-level snapshots from multiple observers can share the same underlying stall.
        for _ in range(30):
            if stop:break
            time.sleep(.25)
        if flag.exists():seen=flag.stat().st_mtime_ns
