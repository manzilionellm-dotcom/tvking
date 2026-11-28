#!/usr/bin/env python3
"""Mesure deux révisions Flutter dans un ordre fixé, sur un même runner Linux."""
import argparse
import csv
import json
import math
import os
from pathlib import Path
import shutil
import statistics
import subprocess

SIZES = (5000, 20000, 30000, 50000)
OPTIONS = ["--no-pub", "--concurrency=1", "--reporter", "expanded",
           "--dart-define=PLAY_BUILD=true", "--dart-define=ZUNO_FREE_PLAYER=true",
           "--dart-define=ZUNO_EDITION=auto", "--dart-define=BACKEND_URL=http://127.0.0.1:9"]
ORACLE = Path(__file__).resolve().parent


def run(args, cwd, env):
    return subprocess.run(args, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, check=False)


def save(out, name, value):
    path = out / name
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


def compare(baseline, candidate, out):
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ | {"FLUTTER_SUPPRESS_ANALYTICS":"true", "DART_SUPPRESS_ANALYTICS":"true", "ZUNO_BENCH":"1"}
    trees = {"A":baseline, "B":candidate}
    schedule = list("ABBA" * 3)
    versions = {}
    for key, tree in trees.items():
        versions[key] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=tree, text=True).strip()
        app = tree / "android-app"
        here = app / "ci/zuno_lab_catalog_oracle"
        here.mkdir(parents=True, exist_ok=True)
        for name in ("m3u_benchmark_test.dart", "xtream_benchmark_test.dart"):
            shutil.copyfile(ORACLE / name, here / name)
        for args in (["flutter","--suppress-analytics","pub","get"], ["flutter","--suppress-analytics","gen-l10n"]):
            step = run(args, app, env)
            if step.returncode:
                raise RuntimeError(f"Préparation {key} : échec de {args[2]} (code {step.returncode})")
    save(out, "plan.json", {"versions":versions,"schedule":schedule,"sizes":SIZES,"raw_unit":"millisecondes",
        "sqlite":"vraie base locale, données synthétiques, fusion TV activée","network":"fournisseur HTTP simulé"})
    xtream, m3u, status = [], [], []
    for seq, key in enumerate(schedule,1):
        app = trees[key]/"android-app"
        raw = out / f"parser-{seq:02d}-{key}.json"
        case = {"pass":seq,"cycle":(seq-1)//4+1,"build":key,"sha":versions[key]}
        for kind in ("m3u", "xtream"):
            step = run(["flutter","--suppress-analytics","test",*OPTIONS,
                f"ci/zuno_lab_catalog_oracle/{kind}_benchmark_test.dart"], app,
                env | {"ZUNO_CATALOG_OUTPUT":str(raw)})
            if kind == "xtream":
                batch=[json.loads(line.split("ZUNO_BENCH ",1)[1]) for line in step.stdout.splitlines() if line.startswith("ZUNO_BENCH ")]
                xtream.extend(case | x for x in batch)
                ok=len(batch)==4 and [r["chaines_en_base"] for r in batch]==list(SIZES)
            else:
                batch = json.loads(raw.read_text())["samples"] if raw.is_file() else []
                m3u.extend(case | x for x in batch)
                ok=all(sum(r["entries"]==n for r in batch)==12 for n in SIZES)
            status.append(case | {"scenario":kind,"exit":step.returncode,"rows":len(batch),"valid":ok and step.returncode==0})
            save(out,"xtream.json",xtream)
            save(out,"m3u.json",m3u)
            save(out,"status.json",status)
            if not ok or step.returncode:
                raise RuntimeError(f"Passage {seq} {key} {kind} : code {step.returncode}, {len(batch)} résultats")
    summary=[]
    for kind, rows, column, timing, scale in (
        ("M3U parseur", m3u,"entries","us",0.001),
        ("Xtream import SQLite", xtream,"chaines_en_base","duree_ms",1),
    ):
        for key in trees:
            for n in SIZES:
                times=sorted(r[timing]*scale for r in rows if r["build"]==key and r[column]==n)
                summary.append({"scenario":kind,"build":key,"size":n,"n":len(times),"median_ms":statistics.median(times),
                    "p95_ms":times[math.ceil(.95*len(times))-1],"worst_ms":max(times),"lt_3s":sum(t<3000 for t in times)})
    for name,rows in (("xtream",xtream),("m3u",m3u),("summary",summary)):
        with (out/f"{name}.csv").open("w",newline="") as f:
            writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    save(out,"summary.json",summary)


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    for name in ("baseline","candidate","output"): parser.add_argument(name,type=Path)
    args=parser.parse_args()
    compare(args.baseline.resolve(),args.candidate.resolve(),args.output.resolve())
