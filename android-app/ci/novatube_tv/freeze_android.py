#!/usr/bin/env python3
"""Observe an isolated Android QA emulator. No media-server or app callbacks drive the clocks."""
import argparse
import concurrent.futures
import json
import os
import re
import signal
import sqlite3
import subprocess
import sys
import tarfile
import threading
import time
from pathlib import Path

PKG = "com.sevenmotion.novatube.tv"
CADENCE = re.compile(r'\bwindow_ms=(\d+) rendered=(\d+) dropped=(\d+)')
SIGNALS = re.compile(r'NovaTubeFreeze|ExoPlaybackException|Playback error|FATAL EXCEPTION|NovaTubeQA.*engine_exhausted')
STOP = threading.Event()


def timestamp():
    return {"utc_ns": time.time_ns(), "host_mono_ns": time.monotonic_ns()}


def log_object(path, obj):
    with path.open("a", encoding="utf8") as out:
        out.write(json.dumps({**timestamp(), **obj}, ensure_ascii=False) + "\n")


class Bridge:
    def __init__(self, serial, pkg):
        self.cmd = ["adb"] + (["-s", serial] if serial else [])
        self.pkg = pkg

    def call(self, *args, timeout=8):
        try:
            p = subprocess.run(self.cmd + list(args), capture_output=True, timeout=timeout)
            return p.returncode, p.stdout, p.stderr
        except (subprocess.TimeoutExpired, OSError) as ex:
            return 124, b"", str(ex).encode()

    def shell(self, code, timeout=8):
        return self.call("shell", code, timeout=timeout)

    def processes(self):
        rc, data, _ = self.shell("pidof " + self.pkg)
        return [int(x) for x in data.split() if x.isdigit()] if rc == 0 else []

    def emulator_check(self):
        for key in ("ro.kernel.qemu", "ro.boot.qemu"):
            if self.shell("getprop " + key)[1].strip() == b"1":
                return
        raise SystemExit("Cette sonde exporte l’état local et requiert un émulateur QA.")


def is_sqlite(file):
    with file.open("rb") as stream:return stream.read(16) == b"SQLite format 3\x00"


def dump_database(bridge, base):
    # The fixture is synthetic; never export files from other packages.
    pkg = bridge.pkg
    mode = bridge.shell("id -u")[1].strip()
    prefix = "" if mode == b"0" else f"run-as {pkg} "
    cmd = (
        f"cd /data/user/0/{pkg} && find . -type f "
        r"\( -name '*.db' -o -name '*.db-wal' -o -name '*.db-shm' -o -name '*.db-journal' "
        r"-o -name '*.sqlite*' -o -path './databases/*' \) "
        r"-exec tar cf - {} +"
    )
    rc, data, err = bridge.call("exec-out", prefix + "sh -c " + "'" + cmd.replace("'","'\"'\"'") + "'", timeout=20)
    (base/"sqlite.stderr.txt").write_bytes(err)
    if rc or not data:
        return {"rc": rc, "archive_bytes": len(data), "status": "unavailable_or_no_databases"}
    archive = base/"sqlite.tar"
    archive.write_bytes(data)
    inspection = {}
    try:
        with tarfile.open(archive) as tar:
            for obj in tar:
                name = obj.name
                if not obj.isfile() or not name.startswith("./") or ".." in Path(name).parts:
                    continue
                f = tar.extractfile(obj)
                dest = base/"sqlite-copy"/name
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(f.read())
        for dest in (base/"sqlite-copy").rglob("*"):
            if not dest.is_file() or not is_sqlite(dest):
                continue
            con = sqlite3.connect(dest.as_uri()+"?mode=ro", uri=True)
            try:
                inspection[str(dest.relative_to(base/"sqlite-copy"))] = {
                    "quick_check": con.execute("pragma quick_check").fetchall(),
                    "tables": con.execute("select name from sqlite_master where type='table' order by name").fetchall(),
                    "user_version": con.execute("pragma user_version").fetchone(),
                }
            finally:
                con.close()
    except (OSError, tarfile.TarError, sqlite3.Error) as ex:
        inspection["error"] = str(ex)
    return {"rc":rc,"archive_bytes":len(data),"copied_without_stopping_app":True,"validation":inspection}


def snapshot(bridge, out, reason, pid=None):
    start = timestamp()
    base = out/("snapshot-"+str(start["utc_ns"]))
    base.mkdir(parents=True)
    pid = pid or next(iter(bridge.processes()), None)
    meta = {"reason": reason, "pid":pid, "started":start}
    (base/"trigger.json").write_text(json.dumps(meta,indent=2))
    tasks = {
        "android-clock": "date -u; cat /proc/uptime; getprop ro.build.fingerprint; id",
        "codec": "dumpsys media.codec",
        "metrics": "dumpsys media.metrics",
        "surface": "dumpsys SurfaceFlinger --list",
        "processes": "ps -A -T",
        "alarms": "dumpsys power",
        "network": "ip link; ip -s route; ss -tanop; iptables -nvL OUTPUT",
        "logcat": "logcat -b all -d -v epoch -t 7500",
    }
    if pid:
        tasks.update({
          "process":f"cat /proc/{pid}/status; cat /proc/{pid}/limits; cat /proc/{pid}/smaps_rollup; cat /proc/{pid}/io; ls -l /proc/{pid}/fd",
          "meminfo":f"dumpsys meminfo {pid}",
          "thread-wait":f'for t in /proc/{pid}/task/*; do echo "$t"; cat "$t/comm" "$t/wchan" "$t/stack" 2>&1; done',
        })
    def capture_task(item):
        key,cmd=item
        rc, data, err = bridge.shell(cmd,timeout=16)
        (base/(key+".txt")).write_bytes(data + (b"\nSTDERR\n"+err if err else b""))
        return key,{"rc":rc,"bytes":len(data),**timestamp()}
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        fut={pool.submit(capture_task,item) for item in tasks.items()}
        db=pool.submit(dump_database,bridge,base)
        img=bridge.call("exec-out","screencap","-p",timeout=12)
        if img[0]==0 and img[1].startswith(b"\x89PNG"):
            (base/"screen.png").write_bytes(img[1])
        meta["task_results"]=dict(f.result() for f in fut)
        meta["sqlite"]=db.result()
    # Stop-the-world diagnostics follow the lightweight timestamped snapshots.
    # Android's SIGQUIT requests ART's thread dump. Never force-stop / restart.
    if pid and pid in bridge.processes():
        for key,cmd in [
            ("art","kill -3 "+str(pid)+"; sleep 1; ls -lt /data/anr; f=$(ls -t /data/anr/anr* 2>/dev/null | head -1); if test -n \"$f\"; then cat \"$f\"; fi"),
            ("native","debuggerd -b "+str(pid)),
        ]:
            k,stats=capture_task((key,cmd)); meta["task_results"][k]=stats
    meta["finished"]=timestamp()
    (base/"snapshot.json").write_text(json.dumps(meta,indent=2))


def watch(bridge, out, duration, armfile, stall, campaign):
    state={"last_render":None,"last_error":None,"last_sample":None}
    lock=threading.Lock()
    def read_log():
        # Keep all time-stamped Android buffers, including MediaCodec, Media3,
        # crashes and OS process events, while the media source can be offline.
        with (out/"logcat-epoch.txt").open("ab",buffering=0) as raw:
            proc=subprocess.Popen(bridge.cmd+["logcat","-b","all","-v","epoch","-T","1"], stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            try:
                for line in proc.stdout:
                    if STOP.is_set():break
                    raw.write(line)
                    s=line.decode("utf8","replace").rstrip()
                    m=CADENCE.search(s)
                    if m:
                        window,frames,lost=map(int,m.groups())
                        entry={"window_ms":window,"rendered":frames,"dropped":lost,"android_line":s}
                        log_object(out/"cadence.jsonl",entry)
                        with lock:
                            state["last_sample"]=time.monotonic()
                            if frames:state["last_render"]=time.monotonic()
                    if SIGNALS.search(s):
                        log_object(out/"player-events.jsonl",{"android_line":s})
                        if "Playback error" in s or "kind=player_error" in s or "FATAL EXCEPTION" in s:
                            with lock: state["last_error"]=time.monotonic()
            finally:
                proc.terminate()
    threading.Thread(target=read_log,daemon=True).start()
    def external_triggers():
        seen=set()
        while not STOP.is_set():
            for request in campaign.glob("freeze-events/event-*/request.json"):
                if request in seen: continue
                try:
                    payload=json.loads(request.read_text())
                except (OSError, ValueError):continue
                seen.add(request)
                log_object(out/"external-triggers.jsonl",{"request":str(request.relative_to(campaign))})
                (campaign/"freeze-trigger").touch()
                dest=request.parent/"android"
                threading.Thread(target=snapshot,args=(bridge,dest,str(payload.get("reason","external_detector")),None),daemon=False).start()
            STOP.wait(.2)
    threading.Thread(target=external_triggers,daemon=True).start()
    started=time.monotonic(); last_pid=None; last_snap=0.; snapshots=0; last_dump=0.
    fired=False
    while not STOP.is_set() and time.monotonic()-started<duration:
        loop=time.monotonic()
        armed=armfile is None or armfile.exists()
        pids=bridge.processes(); pid=pids[0] if pids else None
        reason=None
        if pid:
            rc,raw,err=bridge.shell(f"cat /proc/uptime; cat /proc/{pid}/stat; cat /proc/{pid}/status | grep -E 'Threads:|VmRSS:|VmSwap:'; cat /proc/net/dev",timeout=4)
        else:
            rc,raw,err=1,b"",b"no target PID"
        log_object(out/"heartbeat.jsonl",{"pids":pids,"rc":rc,"state":raw.decode(errors="replace"),"stderr":err.decode(errors="replace"),"armed":armed})
        if loop-last_dump>20:
            rc,codec,_err=bridge.shell("dumpsys media.codec",timeout=5)
            log_object(out/"codec-periodic.jsonl",{"rc":rc,"state":codec.decode(errors="replace")})
            last_dump=loop
        with lock: s=dict(state)
        if armed:
            request=out/"request-snapshot"
            if request.exists():
                reason=request.read_text().strip() or "external_detector"
                request.unlink(missing_ok=True)
            elif s["last_error"] and s["last_error"]>last_snap:
                reason="player_error"
            elif last_pid and pid!=last_pid:
                reason="process_changed_or_unavailable"
            elif s["last_render"] and loop-s["last_render"]>stall and not fired:
                reason="no_decoder_output"
            if reason and loop-last_snap>20 and snapshots<6:
                last_snap=loop;snapshots+=1;fired=True
                (campaign/"freeze-trigger").touch()
                log_object(out/"triggers.jsonl",{"reason":reason,"pid":pid})
                t=threading.Thread(target=snapshot,args=(bridge,out,reason,pid),daemon=False)
                t.start()
            if s["last_render"] and loop-s["last_render"]<stall:fired=False
        last_pid=pid
        STOP.wait(max(.1,2.0-(time.monotonic()-loop)))
    STOP.set()


def main():
    if len(sys.argv) >= 3 and sys.argv[1] not in ("watch", "capture") and not sys.argv[1].startswith("-"):
        job=Path(sys.argv[1])
        args=["watch", "--out", str(job/"android-health"), "--campaign", str(job), "--package", sys.argv[2]]
        sys.argv[1:]=args+sys.argv[3:]
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("mode",choices=("watch","capture"))
    p.add_argument("--out",type=Path,required=True)
    p.add_argument("--serial")
    p.add_argument("--package",default=PKG)
    p.add_argument("--duration",type=int,default=4800)
    p.add_argument("--stall",type=float,default=8.0)
    p.add_argument("--arm-file",type=Path)
    p.add_argument("--campaign",type=Path)
    p.add_argument("--reason",default="operator")
    a=p.parse_args(); a.out.mkdir(parents=True,exist_ok=True)
    if not re.fullmatch(r"[A-Za-z0-9_.]+",a.package):p.error("invalid package")
    b=Bridge(a.serial,a.package); b.emulator_check()
    signal.signal(signal.SIGTERM,lambda *_:STOP.set())
    if a.mode=="capture":snapshot(b,a.out,a.reason)
    else:watch(b,a.out,a.duration,a.arm_file,a.stall,a.campaign or a.out)

if __name__=="__main__":main()
