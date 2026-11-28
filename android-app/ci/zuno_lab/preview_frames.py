"""Encode deux pistes de compteurs expurgées et mesure les limites de la transition."""
import csv
import json
from pathlib import Path
import subprocess
import struct
import statistics

import numpy as np
from PIL import Image
from android_film_clock import decode, ffprobe, winscope
from optical_film import digest, safe_movie


def luma(image):
    return np.asarray(image.convert("L").resize((960,540),Image.Resampling.BOX))


def read(frame, geom):
    if geom is None:
        return "", None
    x,y,step=geom
    values=frame[round(y),np.rint(x+step*np.arange(30)).astype(int)]
    name,n=decode(values)
    return (name,n) if name and 0<=n<3000 else ("",None)


def full(frame):
    h,w=frame.shape
    for top,bottom in ((0,0),(0,24),(0,48),(24,0),(24,24),(48,0),(48,48)):
        a,b=top*h/1080,bottom*h/1080
        vh=min(h-a-b,w*9/16); vw=vh*16/9
        g=((w-vw)/2+vw*496/1920,a+(h-a-b-vh)/2+vh*650/1080,vw/60)
        value=read(frame,g)
        if value[0]:
            return value
    return "",None


def locate_preview(frame):
    """Position réelle dans la colonne droite ; préambule, parité et contre-échantillons."""
    h,w=frame.shape
    ys=np.arange(round(.08*h),round(.77*h))
    xs=np.arange(round(.61*w),round(.78*w),1)
    for ratio in (470/1280,.35,.38,.33,.40):
        step=w*ratio/60
        places=np.rint(xs[:,None]+step*np.arange(30)).astype(int)
        data=frame[ys[:,None,None],places[None,:,:]]
        white=data>=190
        valid=(np.all((data<=60)|white,axis=2)
               &np.all(white[:,:,:7]==[1,0,1,1,0,1,0],axis=2)
               &white[:,:,29]&((white[:,:,8:28].sum(axis=2)%2)==white[:,:,28]))
        candidates={}
        for iy,ix in zip(*np.nonzero(valid)):
            g=(float(xs[ix]),float(ys[iy]),step)
            name,n=read(frame,g)
            if name:
                candidates.setdefault((name,n),[]).append(g)
        if candidates:
            best=max(candidates.values(),key=len)
            # Le code doit présenter une aire. Une ligne de glyphes isolée ne suffit pas.
            if len({v[0] for v in best})>=2 and len({v[1] for v in best})>=2:
                center=np.median(np.asarray(best),axis=0)
                return min(best,key=lambda v:abs(v[0]-center[0])+abs(v[1]-center[1]))
    return None


def export(private,folder,index,geom):
    pts=[float(f["best_effort_timestamp_time"]) for f in
         ffprobe(private,"-select_streams","v:0","-show_frames","-show_entries","frame=best_effort_timestamp_time")["frames"]]
    try:
        elapsed,met=winscope(private)
    except (OSError,ValueError,KeyError,IndexError,AssertionError,StopIteration,RuntimeError,struct.error) as error:
        elapsed=[None]*len(pts);met={"unavailable":type(error).__name__}
    cmd=["ffmpeg","-nostdin","-v","error","-i",str(private),"-map","0:v:0","-vf","scale=960:540:flags=area,format=gray",
         "-threads","1","-fps_mode","passthrough","-f","rawvideo","-"]
    rows=[]
    with subprocess.Popen(cmd,stdout=subprocess.PIPE) as proc:
        while data:=proc.stdout.read(960*540):
            if len(data)!=960*540:raise ValueError("Trame partielle")
            frame=np.frombuffer(data,dtype=np.uint8).reshape(540,960)
            if geom is None and len(rows)<30 and len(rows)%5==0:
                geom=locate_preview(frame)
            rows.append((read(frame,geom),full(frame)))
        if proc.wait()!=0:raise ValueError("Décodage interrompu")
    if not rows or len(rows)!=len(pts) or len(elapsed)!=len(rows):raise ValueError("Nombre d’images incohérent")
    with (folder/f"frames-{index}.csv").open("w",newline="") as f:
        writer=csv.writer(f);writer.writerow(("pts","elapsed","preview","preview_counter","full","full_counter"))
        for t,e,(p,s) in zip(pts,elapsed,rows):writer.writerow((t,e,*p,*s))
    for j,name in enumerate(("apercu","plein")):
        safe_movie(folder/f"{name}-{index}.mkv",pts,[row[j] for row in rows])
    gaps=[b-a for a,b in zip(pts,pts[1:])]
    (folder/f"film-{index}.json").write_text(json.dumps({"geometry":geom,"frames":len(pts),"clock":met,
        "sha256_source_privee":digest(private),"max_gap_ms":round(1000*max(gaps,default=0),3),
        "median_interval_ms":round(1000*statistics.median(gaps),3) if gaps else None,
        "mean_fps":len(gaps)/sum(gaps) if gaps and sum(gaps)>0 else None}))


def increasing(a,b):
    return a is not None and b is not None and 0<(b-a)%3000<300


def score(rows,target,lower,upper,limit=9):
    """lower/upper encadrent l'appui sur Android ; PTS stricts et non interpolés."""
    result={"origin_pixels":False,"frame_count":len(rows),"status":"clock_missing"}
    data=[(float(r["elapsed"]),r["preview"],int(r["preview_counter"]) if r["preview_counter"] else None,
           r["full"],int(r["full_counter"]) if r["full_counter"] else None) for r in rows if r["elapsed"]]
    if len(data)<2:return result
    pre=[r for r in data if lower-1.5 <= r[0] <=lower]
    after=[r for r in data if upper<=r[0]<=upper+limit]
    around=[r for r in data if lower<r[0]<upper]
    if not pre or not after:return {**result,"status":"key_not_covered"}
    prev=pre[-1]
    if prev[3] or any(r[3] for r in pre[-2:]):return {**result,"status":"already_fullscreen"}
    moving=any(a[1]==b[1]==target and b[0]-a[0]<=.30 and increasing(a[2],b[2]) for a,b in zip(pre,pre[1:]))
    result["origin_pixels"]=moving and prev[1]==target
    def bounds(t,stamp):
        return [round(max(0,t-upper)*1000,2),round(max(0,stamp-lower)*1000,2)]
    # Toute image dans l'intervalle de dispatch peut suivre l'appui. Elle permet
    # une borne haute ; seule l'origine pré-appui confirmée autorise la série primaire.
    last_preview=prev[0];pending_exit=None;last_full=None;gap=False;wrong=False
    for r in around+after:
        stamp,p,pc,s,sc=r
        gap |= stamp-prev[0]>.30
        if p==target:
            last_preview=stamp;pending_exit=None
        elif result["origin_pixels"] and "preview_marker_exit_ms" not in result:
            if pending_exit is None:pending_exit=stamp
            else:result["preview_marker_exit_ms"]=bounds(last_preview,pending_exit)
        if s:
            if s!=target:wrong=True
            if s==target:
                if "first_full_ms" not in result:result["first_full_ms"]=bounds(prev[0],stamp)
                if last_full and stamp-last_full[0]<=.30 and increasing(last_full[1],sc) and "movement_ms" not in result:
                    result["movement_ms"]=bounds(prev[0],stamp)
                last_full=(stamp,sc)
            else:last_full=None
        else:last_full=None
        prev=r
        if "movement_ms" in result and ("preview_marker_exit_ms" in result or not result["origin_pixels"]):
            break
    result["capture_gap"]=gap
    result["wrong_channel"]=wrong
    if wrong:result["status"]="wrong_channel"
    elif gap:result["status"]="capture_gap"
    elif "movement_ms" in result:
        if not result["origin_pixels"]:result["status"]="ui_origin_only"
        elif "preview_marker_exit_ms" not in result:result["status"]="preview_exit_unresolved"
        else:result["status"]="observed"
    elif not after or after[-1][0]<upper+limit-.30:result["status"]="end_censored"
    else:result["status"]="timeout"
    return result
