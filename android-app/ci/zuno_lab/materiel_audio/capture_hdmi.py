"""Dépouille un court enregistrement HDMI local des seules mires A/B et de leur son."""
import argparse,csv,io,json,math,re,subprocess
from pathlib import Path
import numpy as np
from PIL import Image
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'synchronisme'))
from sonde import tone, COUNT, RATE

def probe(src,*options):
    return json.loads(subprocess.check_output(['ffprobe','-v','error',*options,'-of','json',str(src)]))
def stamps(src,kind):
    rows=probe(src,'-select_streams',kind+':0','-show_frames','-show_entries','frame=best_effort_timestamp_time,nb_samples')['frames']
    return [(float(r['best_effort_timestamp_time']),int(r.get('nb_samples',0))) for r in rows if 'best_effort_timestamp_time' in r]
def observe(frame):
    h,w,_=frame.shape;s=np.array([frame[round(h*650/1080),round(w*(496+i*32)/1920)].mean() for i in range(30)])
    if s.max()-s.min()<85:return None
    s=(s-s.min())/(s.max()-s.min())
    if not np.all((s<.24)|(s>.74)):return None
    bits=(s>.74).astype(int)
    if list(bits[:7])!=[1,0,1,1,0,1,0] or bits[29]!=1 or bits[8:28].sum()%2!=bits[28]:return None
    n=sum(int(v)<<i for i,v in enumerate(bits[8:28]))
    return (('B' if bits[7] else 'A'),n) if n<3000 else None
def title_on_crop(frame,mode):
    buf=io.BytesIO();Image.fromarray(frame).save(buf,format='PNG')
    d=subprocess.run(['tesseract','stdin','stdout','--psm',str(mode),'tsv'],input=buf.getvalue(),capture_output=True,timeout=7)
    words=[r for r in csv.DictReader(io.StringIO(d.stdout.decode(errors='replace')),delimiter='\t',quoting=csv.QUOTE_NONE) if float(r['conf'])>48]
    for u in words:
        if u['text'].lower()!='mire':continue
        for v in words:
            if v['text'].upper() not in ('A','B'):continue
            x=int(v['left'])-int(u['left'])-int(u['width'])
            if -min(int(u['width']),int(v['width']))<=x<.04*frame.shape[1] and int(v['left'])>int(u['left']) and abs(int(v['top'])-int(u['top']))<max(8,.03*frame.shape[0]):return v['text'].upper()
    return None
def title(frame):
    h,w=frame.shape[:2]
    for sub,mode in ((frame,11),(frame[:h//5,:w//2],7),(frame[h*52//100:h*83//100,:w*70//100],6)):
        hit=title_on_crop(sub,mode)
        if hit:return hit
    return None
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('film',type=Path);ap.add_argument('sortie',type=Path)
    ap.add_argument('--cadre',help='x:y:largeur:hauteur du téléviseur dans le film, frontal et horizontal')
    a=ap.parse_args();streams=probe(a.film,'-show_streams')['streams'];audio=next((x for x in streams if x['codec_type']=='audio'),None)
    if audio is None:raise SystemExit('Piste audio absente du fichier fourni')
    vs=stamps(a.film,'v');au=stamps(a.film,'a')
    if not vs or not au:raise SystemExit('Horodatages audio/vidéo absents')
    if vs[-1][0]-vs[0][0]>120:raise SystemExit('Utiliser le court extrait de deux zaps, au plus 120 s')
    sr=int(audio['sample_rate']);jump=max((abs(a+n/sr-b) for (a,n),(b,_) in zip(au,au[1:])),default=0)
    if jump>.02:raise SystemExit('Temps audio discontinu, alignement INCERTAIN')
    audio_buf=subprocess.check_output(['ffmpeg','-nostdin','-v','error','-i',str(a.film),'-map','0:a:0','-vn','-ac','1','-ar',str(RATE),'-f','s16le','-'])
    pcm=np.frombuffer(audio_buf,dtype='<i2')
    vf='scale=960:540'
    if a.cadre:
        if not re.fullmatch(r'\d+:\d+:\d+:\d+',a.cadre):raise SystemExit('Cadre invalide')
        x,y,w,h=map(int,a.cadre.split(':'));vf=f'crop={w}:{h}:{x}:{y},'+vf
    proc=subprocess.Popen(['ffmpeg','-nostdin','-v','error','-i',str(a.film),'-map','0:v:0','-an','-vf',vf,'-fps_mode','passthrough','-pix_fmt','rgb24','-f','rawvideo','-'],stdout=subprocess.PIPE)
    rows=[];next_pts=-math.inf;last=None
    for ix,(pts,_) in enumerate(vs):
        buf=proc.stdout.read(960*540*3)
        if len(buf)!=960*540*3:raise SystemExit('Échantillons vidéo et PTS non appariés')
        if pts<next_pts:continue
        next_pts=pts+.24;img=np.frombuffer(buf,dtype=np.uint8).reshape(540,960,3)
        m=observe(img);ch,n=m or (None,None)
        title_name=title(img) if m else None
        center=round((pts-au[0][0])*RATE)
        spectral=[]
        for lo in (center-COUNT,center):
            if lo>=0 and lo+COUNT<=len(pcm):spectral.append(tone(pcm[lo:lo+COUNT])[0])
        correct_audio=bool(ch and spectral==[ch,ch])
        increasing=bool(last and ch and last[0]==ch and 0<(n-last[1])%3000<300 and pts-last[2]<.6)
        rows.append(dict(image=ix,pts=pts,mire=ch,compteur=n,titre=title_name,audio_avant_apres=spectral,mouvement=increasing,accord=bool(increasing and title_name==ch and correct_audio)))
        last=(ch,n,pts) if ch else None
    if proc.stdout.read(1) or proc.wait()!=0:raise SystemExit('Des images ne possèdent pas de PTS exploitable')
    a.sortie.write_text(json.dumps(dict(source='capture externe sur le câble HDMI ou caméra du seul téléviseur ; son enregistré dans le même fichier',max_discontinuite_audio_s=jump,mesures=rows),indent=2,ensure_ascii=False))
if __name__=='__main__':main()
