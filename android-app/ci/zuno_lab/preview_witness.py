"""Série fixe de vrais OK sur des lignes de la grille Direct ZUNO, puis BACK."""
import argparse
import csv
from functools import partial
import json
import math
import statistics
import time
from pathlib import Path
import re
import subprocess

from optical_film import Recorder, clocked_key
from optical_witness import event, key, observe_ui, open_fixture
from preview_frames import export, full, increasing, locate_preview, luma, read, score
from zuno_ui_path import control, normalized


def save(folder, cases):
    (folder/"trials.json").write_text(json.dumps(cases,indent=2,ensure_ascii=False))
    stats={"planned":len(cases),"commands":sum(c.get("sent") is True for c in cases),
        "dispatch_uncertain":sum(c.get("sent")=="uncertain" for c in cases),
        "failures":sum(c.get("sent") is True and c["status"] not in ("observed","ui_origin_only") for c in cases),
        "not_sent":sum(c.get("sent") is False for c in cases)}
    for name in ("observed","ui_origin_only"):
        group=[r for r in cases if r["status"]==name]
        stat={"count":len(group)}
        for metric in ("preview_marker_exit_ms","first_full_ms","movement_ms"):
            v=sorted(c[metric][1] for c in group if c.get(metric))
            if v:
                stat[metric]={"n":len(v),"median_upper":statistics.median(v),"p95_upper_successes":v[math.ceil(.95*len(v))-1],
                              "worst_upper":v[-1],"under_3000_upper":sum(t<3000 for t in v)}
        stats[name]=stat
    stats["primary_complete"]=len(cases)==30 and stats["observed"]["count"]==len(cases)
    # Ne jamais attribuer aux commandes non observées un P95 de succès.
    if stats["primary_complete"]:stats["primary_p95_first_full_upper_ms"]=stats["observed"]["first_full_ms"]["p95_upper_successes"]
    (folder/"summary.json").write_text(json.dumps(stats,indent=2))


def grid_state(folder, known_geometry=None):
    ns,ts,size,image,focused=observe_ui(folder,"preview-grid",retry=False)
    labels=[]
    for name in ("a","b"):
        label="mire "+name
        in_rows=[n for n in ns if .23*size[0]<n[1]<.64*size[0]]
        in_text=[w for w in ts if .23*size[0]<w[1]<.64*size[0]]
        location=control(in_rows,in_text,size,[label])
        if location is None:
            location=next(((n[1],n[2]) for n in in_rows if re.search(r"\b"+label+r"\b",normalized(n[0]))),None)
        labels.append(location)
    grid=all(labels) and abs(labels[1][1]-labels[0][1])>.02*size[1]
    focused_set={n.upper() for f in focused for n in ("a","b") if re.search(r"\bmire "+n+r"\b",normalized(f))}
    selected=focused_set.pop() if grid and len(focused_set)==1 else None
    if image is None:return grid, selected, None, ("",None)
    f=luma(image)
    if full(f)[0]:return False,None,None,("",None)
    g=known_geometry
    if grid and (g is None or not read(f,g)[0]):g=locate_preview(f)
    return grid,selected,g,read(f,g)


def focus_line(folder,target,previous=None):
    geometry=None;last_marker=None;directed=False;last_step=None
    for _ in range(9):
        grid,focus,g,marker=grid_state(folder,geometry)
        if not grid:
            time.sleep(.4);continue
        geometry=g or geometry
        if focus==target:
            # L'aperçu peut avoir besoin de son délai local de 1,5 s.
            if marker[0]!=target:
                time.sleep(1.8)
                grid,focus,g,marker=grid_state(folder,geometry)
                geometry=g or geometry
            if grid and focus==target:
                return "focused_row",geometry,marker
        if directed and marker[0]==target and last_marker and last_marker!=target:
            # Un aperçu de A par défaut ne prouve pas que A a le focus.
            # Exiger un autre aperçu puis une seule touche qui l'a changé.
            return "preview_changed_on_row_direction",geometry,marker
        if marker[0]==target and not directed:
            # Amorcer le contrôle différentiel hors chronométrage.
            wanted="B" if target=="A" else "A"
        else:wanted=target
        current=focus or marker[0] or previous
        if current in ("A","B") and current!=wanted:
            direction="KEYCODE_DPAD_DOWN" if wanted=="B" else "KEYCODE_DPAD_UP"
            pair=(direction,current)
            if last_step==pair:
                time.sleep(.5);continue
            event(folder,"preview-focus-direction",key=direction,from_channel=current,to=wanted)
            key(direction);last_step=pair
            last_marker=marker[0] or None
            directed=wanted==target and bool(last_marker) and last_marker!=target
            time.sleep(1.9)
        else:
            time.sleep(.4)
    raise RuntimeError("Ligne cible non prouvée dans la grille")


def run(out,count):
    out.mkdir(parents=True,exist_ok=True)
    cases=[{"number":i+1,"target":"AB"[i%2],"planned_key":"KEYCODE_DPAD_CENTER","sent":False,"status":"not_attempted"} for i in range(count)]
    save(out,cases)
    # L'ajout de la liste s'arrête à la grille, avant tout tap sur une chaîne.
    try:
        open_fixture(out, stop_at_grid=True)
    except (ValueError,RuntimeError,OSError,subprocess.SubprocessError) as error:
        event(out,"preview-setup-unavailable",reason=type(error).__name__)
        raise
    previous=None
    for c in cases:
        d=out/f"trial-{c['number']:02d}";d.mkdir()
        rec=None
        try:
            origin,geom,marker=focus_line(out,c["target"],previous)
            c.update(row_evidence=origin,still_preview_channel=marker[0] or None,
                     preview_geometry=geom,status="origin_ready")
            rec=Recorder(d/"film",exporter=partial(export,geom=geom));rec.start()
            c.update(sent="uncertain",status="dispatch");save(out,cases)
            low,hi=clocked_key("KEYCODE_DPAD_CENTER")
            c.update(sent=True,key_elapsed_min=low,key_elapsed_max=hi,status="capturing");save(out,cases)
            time.sleep(9.5)
        except (OSError,RuntimeError,ValueError,subprocess.SubprocessError) as err:
            c.update(status="origin_unproved" if c["sent"] is False else "dispatch_or_capture_failed",
                     error_class=type(err).__name__)
        finally:
            collected=rec.finish() if rec is not None else False
            save(out,cases)
        if c["sent"] is not True:
            event(out,"preview-series-interrupted",number=c["number"],reason=c["status"])
            break
        files=sorted((d/"film").glob("frames-*.csv"))
        if not collected or len(files)!=1:
            c["status"]="film_collection_incomplete"
        else:
            with files[0].open() as stream:rows=list(csv.DictReader(stream))
            c.update(score(rows,c["target"],c["key_elapsed_min"],c["key_elapsed_max"]))
        save(out,cases)
        # Un seul BACK, puis preuve de retour des deux lignes de grille.
        # Si le lecteur n'a pas quitté la grille, ne pas en sortir par erreur.
        was_grid,_,_,_=grid_state(out,geom)
        if not was_grid:
            key("KEYCODE_BACK");c["back_sent"]=True;time.sleep(.7)
        else:c["back_sent"]=False
        c["returned_to_grid"]=any(grid_state(out,geom)[0] for _ in range(3))
        previous=c["target"] if c["returned_to_grid"] else None
        save(out,cases)
        if not c["returned_to_grid"]:break
    save(out,cases)
    if any(c["status"]!="observed" or not c.get("returned_to_grid") for c in cases):
        raise SystemExit("Série primaire incomplète : consulter chaque essai et les états UI seuls.")


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("out",type=Path);p.add_argument("--count",type=int,default=30)
    a=p.parse_args()
    if a.count<1 or a.count>30:p.error("nombre de passages entre 1 et 30")
    run(a.out,a.count)
