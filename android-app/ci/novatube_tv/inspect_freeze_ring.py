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
def call(args, limit=8):
    try: return subprocess.run(adb+args,capture_output=True,timeout=limit)
    except subprocess.TimeoutExpired as e: return subprocess.CompletedProcess(args,124,e.stdout or b"",e.stderr or b"timeout")

cfg=dst/"freeze-perfetto.pbtxt";cfg.write_bytes(config)
remote_cfg='/data/local/tmp/nt_freeze_qa.pbtxt'
push=call(['push',str(cfg),remote_cfg])
record(phase='push',rc=push.returncode,err=push.stderr.decode(errors='replace')[-400:])
if push.returncode:sys.exit(1)
for trial in range(4):
    if stop:break
    remote=f'/data/misc/perfetto-traces/nt_freeze_{trial}.pftrace'
    out=dst/f'capture-{trial}.pftrace'
    with (dst/f'command-{trial}.log').open('ab') as log:
        launch=call(['shell','perfetto','--txt','--background-wait','-c',remote_cfg,'-o',remote],16)
        log.write(launch.stdout + launch.stderr)
        record(phase='armed',trial=trial,rc=launch.returncode)
        if launch.returncode:break
        reason='end_of_window'
        while not stop and not (root/'long-result.json').exists():
            stamp=flag.stat().st_mtime_ns if flag.exists() else 0
            if stamp>seen:
                seen=stamp;reason='incident';break
            time.sleep(.2)
        trig=call(['shell','/system/bin/trigger_perfetto','nt_freeze_visible'])
        log.write(trig.stdout+trig.stderr)
        record(phase='trigger_sent',trial=trial,reason=reason,rc=trig.returncode)
        if trig.returncode:break
        # The trace is closed asynchronously after stop_delay_ms. A collector can
        # briefly break the ADB channel; the detached Android writer survives.
        limit=time.monotonic()+25
        prev=-1; stable=0
        while time.monotonic()<limit:
            time.sleep(.5)
            st=call(['shell','stat','-c','%s',remote],4)
            try:size=int(st.stdout.strip())
            except ValueError:size=-1
            if size>4096 and size==prev:stable+=1
            else:stable=0
            prev=size
            if stable>=3:
                get=call(['exec-out','cat',remote],15)
                if get.returncode==0 and len(get.stdout)==size:
                    out.write_bytes(get.stdout);break
                log.write(get.stderr)
            if st.returncode:log.write(st.stderr)
        record(phase='collected',trial=trial,bytes=out.stat().st_size if out.exists() else 0,last_stat=prev)
        if not out.exists() or reason=='end_of_window':break
        for _ in range(24):
            if stop or (root/'long-result.json').exists():break
            time.sleep(.25)
        if flag.exists():seen=flag.stat().st_mtime_ns
        if (root/'long-result.json').exists():break
