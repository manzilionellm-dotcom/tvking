"""Film plein cadre des mires. Les pixels privés sont lus seulement dans un répertoire temporaire."""
import csv
from collections import Counter
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unicodedata
import numpy as np
from PIL import Image, ImageDraw
from android_film_clock import ffprobe, marker_values, winscope

W,H=960,540

def normalized(s):
    return ' '.join(re.findall(r'[a-z0-9]+',''.join(c for c in unicodedata.normalize('NFKD',s.lower()) if not unicodedata.combining(c))))

def ocr(im,psm):
    buf=io.BytesIO();im.save(buf,'PNG')
    r=subprocess.run(['tesseract','stdin','stdout','--psm',str(psm),'tsv'],input=buf.getvalue(),capture_output=True,
        timeout=15,check=True,env={**os.environ,'OMP_THREAD_LIMIT':'1'})
    words=[]
    for d in csv.DictReader(io.StringIO(r.stdout.decode(errors='replace')),delimiter='\t',quoting=csv.QUOTE_NONE):
        word=normalized(d.get('text') or '')
        if not word or float(d.get('conf',-1))<48:continue
        x,y,w,h=[int(d[k]) for k in ('left','top','width','height')]
        words.append((word,(x,y,x+w,y+h)))
    return words

FORBIDDEN={'activation','activate','mac','qr','address','adresse','id','device','appareil','code','pin','password','identifiant','token','http','login','suspendu','suspended','banned'}
HUB={'live','direct','films','movies','series','server','serveur','settings','reglages','search','recherche'}
GRID={'live','direct','mire','a','b','search','recherche','channels','chaines','favorites','favoris'}
LOAD={'mire','a','b','1','2','loading','the','channel','chargement','de','la','chaine','haut','bas','pour','zapper','up','down','to','change','haut bas','up down'}

def safe_ui(im,kind):
    if im is None:return None
    w,h=im.size;l6=ocr(im,6);l11=ocr(im,11)
    labels={p for p,_ in l6+l11}
    if labels&FORBIDDEN:return None
    allowed=HUB if kind=='accueil' else GRID
    if kind=='accueil' and len(HUB&labels)<4:return None
    if kind=='direct' and not {'mire','a','b'}<=labels:return None
    # Licences et adresses restent invisibles. Le fond est réduit à douze
    # cases, insuffisantes pour reproduire du texte ou une matrice QR.
    masked=im.resize((4,3),Image.Resampling.BOX).resize(im.size,Image.Resampling.NEAREST)
    twice={p for p,_ in l6}&{p for p,_ in l11}
    exposed=0
    for word,box in l11:
        x,y,x2,y2=box
        if word in allowed&twice and y<h*.87 and (x2-x)<w*.23 and (y2-y)<h*.12:
            masked.paste(im.crop(box),(x,y));exposed+=1
    return masked if exposed>=2 else None


def panel(im):
    a=np.asarray(im);bg=np.median(a[::16,::16,:],axis=(0,1)).astype(np.uint8)
    if bg.max()>70 or (np.max(np.abs(a.astype(np.int16)-bg),axis=2)<12).mean()<.88:return None
    l6,l11=ocr(im,6),ocr(im,11)
    def qualifies(items):
        s={x for x,_ in items}
        return (not (s&FORBIDDEN) and 'mire' in s and bool(s&{'a','b'}) and
            ({'loading','channel'}<=s or {'chargement','chaine'}<=s))
    if not qualifies(l6) or not qualifies(l11):return None
    labels={p for p,_ in l6}&{p for p,_ in l11}
    ch=next((s for s in ('a','b') if s in labels),None)
    if not ch:return None
    # Le panneau de TvPlayerScreen place les mots et la roue au centre. Les
    # mêmes mots passent deux segmentations. Le reste conserve le fond uni.
    regions=[b for s,b in l11 if s in LOAD&labels and b[0]>.18*W and b[2]<.82*W and b[1]>.12*H and b[3]<.9*H and b[3]-b[1]<H*.16]
    if not regions:return None
    return bg,regions,ch.upper()


def render_panel(im,definition):
    bg,regions,ch=definition
    out=Image.new('RGB',im.size,tuple(map(int,bg)))
    for box in regions:out.paste(im.crop(box),box[:2])
    # La roue n'est exposée que dans son anneau géométrique. Aucun caractère
    # ni code n'est copié dans les autres régions susceptibles de varier.
    source=np.asarray(im);mask=np.max(np.abs(source.astype(np.int16)-bg),axis=2)>28
    for box in regions:
        x,y,x2,y2=box;mask[y:y2,x:x2]=False
    ys,xs=np.nonzero(mask[:,int(W*.48):int(W*.52)])
    xs=xs+int(W*.48)
    candidates=[b for b in regions if (b[2]-b[0])>10]
    if candidates:
        for cy in range(int(.34*H),int(.70*H),2):
            cx=W//2
            selected=(np.abs(xs-cx)<=16)&(np.abs(ys-cy)<=16)
            sy,sx=ys[selected],xs[selected]
            if len(sx)<22:continue
            radius=np.hypot(sx-cx,sy-cy)
            if np.mean((radius>=9)&(radius<=15))>.95:
                ann=np.zeros((H,W),dtype=bool);ann[sy,sx]=True
                image=np.asarray(out).copy();image[ann]=source[ann];return Image.fromarray(image)
    return out


def known_tiles(actual,reference):
    # 24x15 rectangles fixes. Les pixels proviennent du film ; chaque octet
    # publié est identique à celui de la référence après la même quantification.
    # Les zones de divergence couvrent tout le rectangle, jamais le contour du texte.
    a=np.asarray(actual);r=np.asarray(reference);safe=np.empty_like(a);safe[:]=(20,28,38)
    yy,xx=np.indices((H,W));safe[(xx+yy)%14<2]=(47,65,85)
    kept=0;raw=0
    for y in range(0,H,36):
        for x in range(0,W,40):
            v=a[y:y+36,x:x+40];w=r[y:y+36,x:x+40]
            for step in (1,8,16,32,64):
                if np.array_equal(v//step,w//step):
                    safe[y:y+36,x:x+40]=v if step==1 else v//step*step+step//2
                    kept+=1;raw+=step==1;break
    return Image.fromarray(safe),kept/360,raw/360


def ref_frames(assets,temp,markers):
    output={}
    for ch in ('A','B'):
        ns=sorted({n for name,n in markers if name==ch and isinstance(n,int) and 0<=n<3000})
        if not ns:continue
        d=temp/ch;d.mkdir();filt=d/'select.txt'
        filt.write_text("select='"+'+'.join(f'eq(n,{n})' for n in ns)+"',scale=960:540:flags=bilinear")
        subprocess.run(['ffmpeg','-nostdin','-v','error','-threads','2','-i',str(assets/(ch+'.mkv')),
            '-filter_script:v',str(filt),'-an','-fps_mode','passthrough','-threads','1','-pix_fmt','rgb24',str(d/'%05d.ppm')],check=True,timeout=160)
        files=sorted(d.glob('*.ppm'))
        if len(files)!=len(ns):raise ValueError('Repères absents de la mire de référence')
        output.update({(ch,n):p for n,p in zip(ns,files)})
    return output


def compile_movie(images,pts,dst):
    fr=['ffconcat version 1.0']
    for i,p in enumerate(images):
        fr+=['file '+p.name,'option framerate 1000']
        if i+1<len(pts):
            delta=round((pts[i+1]-pts[0])*1000)-round((pts[i]-pts[0])*1000)
            if delta<=0:raise ValueError('Deux trames à moins de 1 ms')
            fr.append(f'duration {delta/1000:.3f}')
    manifest=images[0].parent/'plan.ffconcat';manifest.write_text('\n'.join(fr)+'\n')
    subprocess.run(['ffmpeg','-v','error','-nostdin','-safe','0','-f','concat','-i',str(manifest),'-an','-threads','2',
        '-fps_mode','passthrough','-enc_time_base','1:1000','-video_track_timescale','1000','-bf','0','-c:v','libx264','-crf','17','-pix_fmt','yuv420p','-movflags','+faststart',str(dst)],check=True,timeout=180)
    new=[float(f['best_effort_timestamp_time']) for f in ffprobe(dst,'-select_streams','v:0','-show_frames','-show_entries','frame=best_effort_timestamp_time')['frames']]
    if len(new)!=len(pts) or max(abs((a-pts[0])-(b-new[0])) for a,b in zip(pts,new))>.0011:raise ValueError('PTS exportés incohérents')


def export(private,out,clip,assets):
    pts=[float(f['best_effort_timestamp_time']) for f in ffprobe(private,'-select_streams','v:0','-show_frames','-show_entries','frame=best_effort_timestamp_time')['frames']]
    try:clock,_=winscope(private)
    except (ValueError,KeyError,IndexError,AssertionError,StopIteration):clock=[None]*len(pts)
    markers,_=marker_values(private)
    if len(markers)!=len(pts) or len(clock)!=len(pts):raise ValueError('Longueurs des pistes divergentes')
    with tempfile.TemporaryDirectory() as td:
        work=Path(td);refs=ref_frames(assets,work,markers);photos=[];records=[];best={};cache=None
        proc=subprocess.Popen(['ffmpeg','-v','error','-nostdin','-i',str(private),'-map','0:v:0','-vf','scale=960:540:flags=area','-fps_mode','passthrough',
           '-threads','1','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
        for i,(ch,n) in enumerate(markers):
            buf=proc.stdout.read(W*H*3)
            if len(buf)!=W*H*3:raise ValueError('Trame tronquée')
            im=Image.frombytes('RGB',(W,H),buf);scene='intervalle-masque';fraction=0;raw=0;channel=''
            output=Image.new('RGB',(W,H),(18,18,18))
            ref=refs.get((ch,n))
            if ref:
                with Image.open(ref) as original:masked,fraction,raw=known_tiles(im,original)
                if fraction>=.33:
                    output=masked;scene='mire-verifiee';channel=ch
                    if fraction>best.get(ch,(0,None))[0]:best[ch]=(fraction,output.copy())
            else:
                # Le mouvement de la roue peut varier. Une définition est
                # réutilisée seulement si tous les pixels des mots validés restent identiques.
                if cache and all(im.crop(b).tobytes()==cache[1].crop(b).tobytes() for b in cache[0][1]):
                    definition=cache[0]
                elif i==0 or pts[i]>=next_ocr:
                    definition=panel(im);next_ocr=pts[i]+.4 if definition is None else pts[i]
                    cache=(definition,im) if definition else None
                else:definition=None
                if definition:
                    output=render_panel(im,definition);scene='panneau-verifie';channel=definition[2]
                    if 'panneau' not in best:best['panneau']=(0,output.copy())
            if i==0 or ref:next_ocr=pts[i]
            if scene=='intervalle-masque':
                ImageDraw.Draw(output).text((24,H-35),'Intervalle masque - image non verifiee',fill=(210,210,210))
            p=work/f'image-{i:06d}.png';output.save(p,compress_level=2);photos.append(p)
            records.append((i,pts[i],clock[i],scene,channel,n if scene=='mire-verifiee' else None,round(fraction,4),round(raw,4)))
        if proc.stdout.read(1) or proc.wait()!=0:raise ValueError('Nombre de trames inattendu')
        compile_movie(photos,pts,out/f'lecteur-{clip:02d}.mp4')
        for ch,(_,image) in best.items():image.save(out/f'lecteur-{clip:02d}-{ch}.png')
        with (out/f'images-{clip:02d}.csv').open('w',newline='') as f:
            w=csv.writer(f);w.writerow(('frame','pts','elapsed_android','scene','chaine','compteur','fraction_cadre_verifiee','fraction_rvb_exacte'));w.writerows(records)
        with open(private,'rb') as f:sha=hashlib.file_digest(f,'sha256').hexdigest()
        (out/f'film-{clip:02d}.json').write_text(json.dumps({'frames':len(pts),'sha256_source_privee':sha,'scenes':dict(Counter(r[3] for r in records)),
            'horloge_android':all(t is not None for t in clock),'pixels_diffusion':'Le hachurage bleu-gris indique un rectangle expurge. Les scenes non reconnues sont masquees.'},indent=2))
