"""Observe the composited moving marker independently of the player and its logs."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def dump(path, obj):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False) + "\n")
    tmp.replace(path)


def observe(out, screenshot, channel, seconds):
    work = Path(__file__).resolve().parent
    start = time.monotonic()
    wall_start = time.time()
    phase = os.environ["FREEZE_SCENARIO"]
    dump(out / "observation-start.json", {"monotonic": start, "unix": wall_start, "target": channel,
                                          "seconds": seconds, "scenario": phase})
    faults = None
    if phase.startswith("loss"):
        faults = subprocess.Popen([sys.executable, str(work / "freeze_faults.py"), str(out),
                                   "--every", "30", "--seconds", str(seconds)])
    if phase in ("tunnel-direct", "tunnel-reverse"):
        faults = subprocess.Popen([sys.executable, str(work / "freeze_reverse_control.py"), str(out)])
    events_dir = out / "freeze-events"
    events_dir.mkdir(exist_ok=True)
    last_move = start
    last_valid = None
    previous_id = None
    newest_event = None
    rows = 0
    valid = 0
    moving_pairs = 0
    max_gap = 0
    next_heartbeat = start
    events = []
    try:
        with (out / "visible-frames.jsonl").open("w", buffering=1) as f:
            while time.monotonic() < start + seconds:
                actual, number, begin, end = screenshot()
                ok = actual == channel and number is not None
                row = {"start": round(begin-start,3), "end": round(end-start,3),
                       "channel": actual, "frame": number}
                f.write(json.dumps(row)+"\n")
                rows += 1
                if ok:
                    valid += 1
                # The encoded 25 Hz, 120 s fixture repeats at frame 3000.
                # Only a forward change across consecutive valid reads counts.
                moved = ok and previous_id is not None and 0 < (number - previous_id) % 3000 < 1500
                if moved:
                    moving_pairs += 1
                    max_gap = max(max_gap, end-last_move)
                    last_move = end
                    if newest_event is not None:
                        newest_event["motion_return_s"] = round(end-start,3)
                        dump(events_dir / newest_event["id"] / "recovery.json", newest_event)
                        newest_event = None
                previous_id = number if ok else None
                if ok:
                    last_valid = row
                if end-last_move >= 6 and newest_event is None:
                    event_id = f"event-{len(events)+1:03d}"
                    newest_event = {"id":event_id,"monotonic":end,"unix":time.time(),
                                    "detection_s":round(end-start,3),"last_motion_s":round(last_move-start,3),
                                    "last_identified":last_valid,"current":row,"threshold_s":6}
                    events.append(newest_event)
                    incident = events_dir / event_id
                    incident.mkdir()
                    dump(incident / "request.json", newest_event)
                    (out / "freeze-trigger").touch()
                    screenshot(str(incident / "screen"))
                if newest_event is not None:
                    elapsed=end-newest_event["monotonic"]
                    for delay in (20,55):
                        flag="screen_after_"+str(delay)
                        if elapsed>=delay and not newest_event.get(flag):
                            item=events_dir/newest_event["id"]/("after-"+str(delay)+"s")
                            screenshot(str(item))
                            newest_event[flag]=True
                if end>=next_heartbeat:
                    print(f"{phase}: {end-start:.1f}s, {valid}/{rows} identifiable, {len(events)} gaps", flush=True)
                    next_heartbeat=end+300
                time.sleep(max(0,min(2,start+seconds-time.monotonic())))
    finally:
        if faults is not None:
            if faults.poll() is None:
                try: faults.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    faults.terminate()
                    faults.wait(timeout=10)
            (out / "faults-exit.txt").write_text(str(faults.returncode))
        stop=time.monotonic()
        max_gap=max(max_gap,stop-last_move)
        dump(out/"long-result.json",{"scenario":phase,"wall_s":round(stop-start,3),"target":channel,
             "observations":rows,"identified":valid,"moving_pairs":moving_pairs,
             "max_gap_between_motion_s":round(max_gap,3),"last_motion_s":round(last_move-start,3),
             "events":events,"last_visible":last_valid,
             "completed_scheduled_window":stop>=start+seconds})
    screenshot("long-end")
    # Leave independent witnesses alive after the final sample or error.
    time.sleep(35)
