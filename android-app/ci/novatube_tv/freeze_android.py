#!/usr/bin/env python3
"""Observe an isolated Android QA emulator. No media-server or app callbacks drive the clocks."""
import argparse
import fcntl
import concurrent.futures
import json
import os
import re
import signal
import shlex
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


def request_private_threads(bridge, base, tag):
    # run-as switches UID only for the debuggable fixture; no adb root is required.
    pkg=bridge.pkg
    relative="files/freeze-diag-"+tag+".txt"
    script=(
        f"printf '%s' {tag} > files/freeze-diag.request.tmp && mv files/freeze-diag.request.tmp files/freeze-diag.request || exit 2; "
        + f"for i in $(seq 1 30); do if test -r {relative}; then cat {relative} && rm {relative}; exit 0; fi; sleep 0.2; done; exit 6"
    )
    rc, data, err=bridge.call("exec-out","run-as "+pkg+" sh -c "+shlex.quote(script),timeout=12)
    ok=rc==0 and data.startswith(b"pid=") and b"thread id=" in data
    (base/"java-stacks-private.txt").write_bytes(data)
    (base/"java-stacks-private.stderr.txt").write_bytes(err)
    return {"rc":rc,"valid_java_stacks":ok,"bytes":len(data),**timestamp()}


def snapshot(bridge, out, reason, pid=None, trigger_ns=None, campaign=None):
    # Also serialise the terminal capture (a second process) with any in-flight incident.
    campaign = campaign or out.parent
    campaign.mkdir(parents=True, exist_ok=True)
    with (campaign/".android-capture.lock").open("a") as guard:
        fcntl.flock(guard.fileno(),fcntl.LOCK_EX)
        return capture_state(bridge,out,reason,pid,trigger_ns)


def capture_state(bridge, out, reason, pid, trigger_ns):
    start = timestamp()
    base = out/("snapshot-"+str(trigger_ns or start["utc_ns"]))
    base.mkdir(parents=True)
    pid = pid or next(iter(bridge.processes()), None)
    meta = {"reason": reason, "pid":pid, "started":start}
    (base/"trigger.json").write_text(json.dumps(meta,indent=2))
    root_path=f"/data/user/0/{bridge.pkg}"
    who=bridge.shell("id -u")[1].strip()
    files=f"cat {root_path}/files/blackbox.log; cat {root_path}/files/blackbox.1.log"
    if who != b"0":
        files=f"run-as {bridge.pkg} sh -c 'cat files/blackbox.log; cat files/blackbox.1.log'"
    tasks = {
        "flutter-blackbox":files,
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
    can_run_as=bridge.shell(f"run-as {bridge.pkg} id -u")[0]==0
    meta["adbd_root"]=who==b"0"; meta["run_as"]=can_run_as
    if who!=b"0" and can_run_as:
        for key in ("process","thread-wait"):
            if key in tasks:tasks[key]=f"run-as {bridge.pkg} sh -c "+shlex.quote(tasks[key])
    def capture_task(item):
        key,cmd=item
        start = timestamp()
        rc, data, err = bridge.shell(cmd,timeout=16)
        (base/(key+".txt")).write_bytes(data + (b"\nSTDERR\n"+err if err else b""))
        return key,{"rc":rc,"bytes":len(data),"start":start,"end":timestamp()}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        private=pool.submit(request_private_threads,bridge,base,str(start["utc_ns"])) if can_run_as else None
        db=pool.submit(dump_database,bridge,base)
        image=pool.submit(bridge.call,"exec-out","screencap","-p",timeout=12)
        # Queue secondary state only after the private Android stacks, SQLite and screen.
        fut=[pool.submit(capture_task,item) for item in tasks.items()]
        img=image.result()
        if img[0]==0 and img[1].startswith(b"\x89PNG"):(base/"screen.png").write_bytes(img[1])
        meta["task_results"]=dict(f.result() for f in fut)
        meta["sqlite"]=db.result()
        meta["java_private"]=private.result() if private else {"valid_java_stacks":False,"reason":"run_as_unavailable"}
    # On the production system image debuggerd requires root. The app-provided
    # Java stacks are available without SIGQUIT. Sample only the debuggable UID
    # after the primary snapshot and retain the profile's coverage limitations.
    meta["primary_finished"]=timestamp()
    (base/"snapshot.json").write_text(json.dumps(meta,indent=2))
    sampler=Path(__file__).with_name("inspect_sample_native.py")
    if can_run_as and pid and sampler.exists():
        try:
            pre=timestamp()
            prof=subprocess.run([sys.executable,str(sampler),str(base/"simpleperf"),bridge.pkg],
                                capture_output=True,timeout=45)
            (base/"simpleperf-command.txt").write_bytes(prof.stdout+prof.stderr)
            meta["simpleperf"]={"rc":prof.returncode,"start":pre,"end":timestamp()}
        except (OSError,subprocess.TimeoutExpired) as ex:meta["simpleperf"]={"error":str(ex)}
    elif who==b"0" and pid:
        name,r=capture_task(("native",f"debuggerd -b {pid}"))
        meta["task_results"][name]=r
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
    pending=[]
    queue_lock=threading.Lock()
    def submit_native(reason,pid):
        with queue_lock:pending.append((time.monotonic(),reason,pid))
    def dispatch():
        # Every optical request remains on disk. It wins over native candidates
        # from the same episode. One worker writes one primary directory per episode.
        seen=set();active=None;waiting=[];future=None;jobs=[]
        pool=concurrent.futures.ThreadPoolExecutor(max_workers=1)
        def publish(episode,source,path=None):
            link={"source":source,"primary":str(episode["path"].relative_to(campaign)),
                  "episode_start":episode["start"],**timestamp()}
            log_object(out/"snapshot-links.jsonl",link)
            if path:(path.parent/"android-snapshot-ref.json").write_text(json.dumps(link))
        def new_episode(t,reason,pid):
            ident=time.time_ns()
            group=out/"incidents"
            episode={"start":t,"path":group/("snapshot-"+str(ident)),"opt":None,"sources":set()}
            jobs.append((episode,group,reason,pid,ident))
            return episode
        while not STOP.is_set() or jobs or waiting:
            for request in sorted(campaign.glob("freeze-events/event-*/request.json")):
                if request in seen:continue
                try: payload=json.loads(request.read_text())
                except (OSError,ValueError):continue
                seen.add(request);t=payload.get("monotonic",time.monotonic())
                if not active or active["opt"] is not None or abs(t-active["start"])>15:
                    active=new_episode(t,"optical_stall",None)
                active["opt"]=request
                publish(active,"optical",request)
            with queue_lock:
                waiting.extend(pending);pending.clear()
            keep=[]
            for t,reason,pid in waiting:
                opt=active["opt"] if active else None
                same_active=False
                if opt:
                    done=opt.parent/"recovery.json"
                    if not done.exists():same_active=True
                    else:
                        try:
                            j=json.loads(done.read_text())
                            end=active["start"]+float(j["motion_return_s"])-float(j["detection_s"])
                            same_active=t<=end+1
                        except (OSError,KeyError,ValueError):same_active=abs(t-active["start"])<15
                if active and (same_active or abs(t-active["start"])<=12):
                    if reason not in active["sources"]:publish(active,reason);active["sources"].add(reason)
                    continue
                if not STOP.is_set() and time.monotonic()-t<3.5:
                    keep.append((t,reason,pid));continue
                active=new_episode(t,reason,pid);active["sources"].add(reason)
                publish(active,reason)
                (campaign/"freeze-trigger").touch()
            waiting=keep
            # Process queued episodes serially; interrupted ADB actions cannot
            # make a second reader take the first request away from its event.
            if future and future.done():
                try:future.result()
                except Exception as ex:log_object(out/"capture-failures.jsonl",{"error":str(ex)})
                future=None
            if jobs and future is None:
                _,group,reason,pid,ident=jobs.pop(0)
                future=pool.submit(snapshot,bridge,group,reason,pid,ident,campaign)
            if not STOP.is_set():STOP.wait(.2)
            elif jobs and future:time.sleep(.2)
        pool.shutdown(wait=True)
    dispatcher=threading.Thread(target=dispatch,daemon=False); dispatcher.start()
    armed_since=None
    started=time.monotonic(); last_pid=None; last_snap=0.; snapshots=0; last_dump=0.
    fired=False
    while not STOP.is_set() and time.monotonic()-started<duration:
        loop=time.monotonic()
        armed=armfile is None or armfile.exists()
        if armed and armed_since is None:
            # Source timestamps in this monitor are host monotonic. An error
            # during onboarding must never trigger a diagnostic after arming.
            armed_since=loop
            if armfile:
                try:armed_since=float(json.loads(armfile.read_text())["monotonic"])
                except (ValueError,KeyError,OSError):pass
            last_pid=None
        pids=bridge.processes(); pid=pids[0] if pids else None
        reason=None
        if pid:
            rc,raw,err=bridge.shell(f"cat /proc/uptime; cat /proc/{pid}/stat; cat /proc/{pid}/status | grep -E 'Threads:|VmRSS:|VmSwap:'; cat /proc/net/dev",timeout=4)
        else:
            rc,raw,err=1,b"",b"no target PID"
        log_object(out/"heartbeat.jsonl",{"pids":pids,"rc":rc,"state":raw.decode(errors="replace"),"stderr":err.decode(errors="replace"),"armed":armed})
        optical_request=next(campaign.glob("freeze-events/event-*/request.json"),None)
        # Before a verified visual stall retain logcat, frame counters, process
        # identity and passive OS reads only. Full dumps start at the visual gate.
        if loop-last_dump>20 and (optical_request or (campaign/"long-result.json").exists()):
            rc,codec,_err=bridge.shell("dumpsys media.codec",timeout=5)
            log_object(out/"codec-periodic.jsonl",{"rc":rc,"state":codec.decode(errors="replace")})
            last_dump=loop
        with lock: s=dict(state)
        if armed:
            request=out/"request-snapshot"
            if request.exists():
                reason=request.read_text().strip() or "external_detector"
                request.unlink(missing_ok=True)
            elif s["last_error"] and s["last_error"]>=armed_since and s["last_error"]>last_snap:
                reason="player_error"
            elif last_pid and pid!=last_pid:
                reason="process_changed_or_unavailable"
            elif s["last_render"] and s["last_render"]>=armed_since and s["last_sample"] and loop-s["last_sample"]<4 and loop-s["last_render"]>stall and not fired:
                reason="no_decoder_output"
            if reason and loop-last_snap>20 and snapshots<6:
                last_snap=loop;snapshots+=1;fired=True
                log_object(out/"triggers.jsonl",{"reason":reason,"pid":pid})
                # Native warnings are evidence only; optical requests own all heavy captures.
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
    if a.mode=="capture":snapshot(b,a.out,a.reason,campaign=a.campaign or a.out.parent)
    else:watch(b,a.out,a.duration,a.arm_file,a.stall,a.campaign or a.out)

if __name__=="__main__":main()
