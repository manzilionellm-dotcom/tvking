"""Droits administratifs sur une seule box émulée et un panel local jetable."""
import csv
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from panel_device import observe as panel
from optical_witness import open_fixture, motion, read_marker, screen, key
from optical_film import Recorder
from visible_launch import screen_evidence, LABELS
from android_ui import visible_nodes
from device_smoke import is_foreground


def run(out, status):
    if status not in ("frozen", "banned") or panel.ROOT != "http://127.0.0.1:18787":
        raise ValueError("Exiger le Worker local et une suspension de la liste prévue")
    out.mkdir()
    screen_dir = out / "ecrans"
    screen_dir.mkdir()
    targets = {"frozen": {"frozen", "gelé", "gele"}, "banned": {"suspended", "suspendu"}}[status]
    LABELS["suspension"] = targets | {"account", "compte", "temporarily", "temporairement"}
    results = {"status_test": status, "utc": datetime.now(timezone.utc).isoformat(), "film": None}
    def save():
        (out / "preuve.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
    os.environ["ZUNO_PRELOADED_BY_PANEL"] = "yes"
    open_fixture(out)
    initial = []
    moving = motion(out,"ouverture","A",12,initial,True)
    if not moving:
        key("KEYCODE_DPAD_CENTER")
        moving = motion(out,"confirmation","A",18,initial,True)
    (out/"initial.json").write_text(json.dumps(initial))
    if not moving:
        raise RuntimeError("Aucune mire A en mouvement avant la modification de droits")
    panel.token = panel.api("POST","/api/v1/auth/login",{"email":"admin","password":os.environ["ZUNO_QA_PASS"]})["token"]
    devices = panel.api("GET","/api/v1/devices")["items"]
    if len(devices)!=1:
        raise RuntimeError("Le D1 de test doit contenir exactement une box")
    recorder = Recorder(out/"film")
    try:
        recorder.start()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        results["film_start_error"] = type(exc).__name__
    try:
        # Vérification des pixels immédiatement avant la révocation, même si l'encodeur a tardé.
        last = []
        if not motion(out,"avant-suspension","A",12,last,True):
            raise RuntimeError("L'origine visuelle a disparu avant la révocation")
        results["before"] = last[-2:]
        results["request_begin_s"] = time.monotonic()
        answer = panel.api("PATCH","/api/v1/devices/"+str(devices[0]["id"]),{"block_status":status})
        results["worker_answer_s"] = time.monotonic()
        results["updated"] = answer.get("updated")==1 and answer.get("block_status")==status
        save()
        if not results["updated"]:
            raise RuntimeError("La révocation n'a pas été écrite")
        deadline = time.monotonic()+160
        inspect_at = time.monotonic()+2
        positive = None
        rows = []
        ledger = out / "samples.csv"
        with ledger.open("w",newline="") as file:
            writer=csv.writer(file)
            writer.writerow(["before_s","after_s","channel","counter","capture_ok"])
            while time.monotonic()<deadline:
                start=time.monotonic()
                try:
                    ch,n,_=read_marker(screen())
                    ok=True
                except (OSError,ValueError,RuntimeError,subprocess.SubprocessError):
                    ch=n=None
                    ok=False
                end=time.monotonic()
                writer.writerow([start,end,ch,n,ok]);file.flush()
                rows.append((start,end,ch,n,ok))
                if end>=inspect_at and positive is None:
                    try:
                        ev=screen_evidence(screen_dir,"look-"+str(len(rows)))
                        labels=set(ev["labels"])
                        words=set()
                        if not labels & targets:
                            nodes=visible_nodes(panel.PACKAGE)
                            for label,_,_,_ in nodes:
                                words.update(label.casefold().replace("."," ").split())
                        hits=(labels|words)&targets
                        if hits and is_foreground(panel.PACKAGE):
                            positive=time.monotonic()
                            results["lock_screen"]=dict(time=positive,visible_words=sorted(hits),sensor="pixels" if labels&targets else "accessibility")
                            save()
                    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError):
                        pass
                    inspect_at=time.monotonic()+5
                if positive and end>=positive+15:
                    break
                time.sleep(.08)
        results["captures"]=len(rows)
        results["failed_captures"]=sum(not r[4] for r in rows)
        results["last_visible_after_panel_s"]=max([r[1] for r in rows if r[2] in ("A","B")],default=results["worker_answer_s"])-results["worker_answer_s"]
        results["visible_after_verified_lock"]=sum(r[0]>=positive and r[2] in ("A","B") for r in rows) if positive else None
        results["window_after_lock_s"]=(rows[-1][1]-positive) if positive else None
        results["max_sampling_gap_s"]=max((y[1]-x[0] for x,y in zip(rows,rows[1:])),default=None)
        save()
    finally:
        results["film"]=recorder.finish()
        save()
    if not positive or results["visible_after_verified_lock"]!=0:
        raise RuntimeError("Suspension visuelle non confirmée ou contenu de la mire observé après son écran")
if __name__=="__main__":
    run(Path(sys.argv[1]),sys.argv[2])
