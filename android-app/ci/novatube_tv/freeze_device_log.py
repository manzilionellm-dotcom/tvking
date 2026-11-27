#!/usr/bin/env python3
"""Keep a bounded Android-side Media3 journal independent of the ADB transport."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import threading
import time

STOP=threading.Event()
TAGS=("NovaTubeFreeze:V","NovaTubeQA:V","flutter:I","ExoPlayerImplInternal:V","ExoPlayerImpl:V",
      "MediaCodec:W","CCodec:W","Codec2Client:W","ACodec:W","MediaCodecVideoRenderer:W",
      "ActivityManager:I","AndroidRuntime:E","DEBUG:E","art:W","*:S")

def adb(args,timeout=10):
    cmd=["adb","-s",os.environ.get("ANDROID_SERIAL","emulator-5554"),*args]
    try:return subprocess.run(cmd,capture_output=True,timeout=timeout)
    except (subprocess.TimeoutExpired,OSError) as e:return subprocess.CompletedProcess(cmd,124,b"",str(e).encode())

class Journal:
    def __init__(self,root):
        name=re.sub(r"[^a-zA-Z0-9-]","-",os.environ.get("GITHUB_RUN_ID","local")+"-"+os.environ.get("FREEZE_SCENARIO","session"))
        self.remote="/data/local/tmp/nt-freeze-journal-"+name
        self.root=root/"device-logcat";self.root.mkdir(parents=True,exist_ok=True)

    def record(self,**obj):
        with (self.root/"transport.jsonl").open("a") as f:
            f.write(json.dumps(dict(mono=time.monotonic(),utc=time.time(),**obj))+"\n")

    def ensure(self):
        d=self.remote
        # The process has its own session and opens only regular files. Closing or
        # replacing an adb shell channel therefore does not close its stdout.
        script=f'''d={d}
mkdir -p "$d" || exit 2
pid=$(cat "$d/pid" 2>/dev/null)
if test -n "$pid" && tr '\\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq "$d/stream-"; then
  echo "alive $pid"; exit 0
fi
n=$(cat "$d/count" 2>/dev/null); n=$((n+1)); echo "$n" > "$d/count"
recent=1; if test "$n" -gt 1; then recent=4000; fi
setsid /system/bin/logcat -b main -b system -b crash -v epoch -T "$recent" -r 2048 -n 8 -f "$d/stream-$n.log" {' '.join(shlex.quote(t) for t in TAGS)} </dev/null >"$d/start-$n.txt" 2>&1 &
pid=$!; echo "$pid" > "$d/pid"; sleep .15
if ! kill -0 "$pid" 2>/dev/null; then cat "$d/start-$n.txt"; exit 3; fi
echo "started $pid $n"'''
        r=adb(["shell",script],6)
        self.record(action="recorder",rc=r.returncode,result=(r.stdout+r.stderr).decode(errors="replace")[-220:])
        return r.returncode==0

    def collect(self):
        with (self.root/"collect.lock").open("a") as lock:
            fcntl.flock(lock.fileno(),fcntl.LOCK_EX)
            d=self.remote
            script=f'cat /proc/uptime; for f in {d}/stream-*.log*; do test ! -f "$f" || stat -c "%i %s %n" "$f"; done'
            r=adb(["shell",script],5)
            if r.returncode:
                self.record(action="list_unavailable",rc=r.returncode)
                return False
            rows=r.stdout.decode(errors="replace").splitlines()
            meta=[];complete=True
            for row in rows[1:]:
                m=re.fullmatch(r"(\d+)\s+(\d+)\s+("+re.escape(d)+r"/stream-\d+\.log(?:\.\d+)?)\s*",row)
                if not m:continue
                inode,size,remote=m[1],int(m[2]),m[3]
                target=self.root/f"inode-{inode}.txt"
                off=target.stat().st_size if target.exists() else 0
                meta.append({"inode":inode,"size":size,"remote":remote.rsplit("/",1)[-1]})
                if off==size:continue
                if off>size:
                    self.record(action="truncated",inode=inode,old=off,size=size)
                    target.rename(target.with_name(f"inode-{inode}-prev-{time.time_ns()}.txt"));off=0
                cmd=f'exec 3< {remote} || exit 2; test "$(stat -L -c %i /proc/$$/fd/3)" = {inode} || exit 3; tail -c +{off+1} <&3 | head -c {size-off}'
                q=adb(["exec-out","sh -c "+shlex.quote(cmd)],18)
                if q.returncode or len(q.stdout)!=size-off:
                    complete=False;self.record(action="retry_chunk",inode=inode,offset=off,expected=size-off,actual=len(q.stdout),rc=q.returncode)
                    continue
                with target.open("ab") as f:f.write(q.stdout)
            self.record(action="collect",device_uptime=rows[0] if rows else None,files=meta,complete=complete)
            return complete and bool(meta)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode",choices=["watch","collect"]);p.add_argument("out",type=Path)
    p.add_argument("--seconds",type=int,default=6500);p.add_argument("--interval",type=int,default=30)
    a=p.parse_args();j=Journal(a.out);end=time.monotonic()+a.seconds
    signal.signal(signal.SIGTERM,lambda *_:STOP.set())
    if a.mode=="collect":
        for attempt in range(3):
            if j.collect():return
            time.sleep(.7)
        sys.exit(1)
    while not STOP.is_set() and time.monotonic()<end:
        if j.ensure():j.collect()
        STOP.wait(a.interval)
    j.collect()

if __name__=="__main__":main()
