"""Relier le son effectivement rendu par l'AVD, le titre du lecteur et la mire visible."""
import csv,io,json,os,re,subprocess,sys,time
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from optical_witness import APK_PACKAGE,read_marker,open_fixture,key
from optical_film import clocked_key
from android_film_clock import decode
from real_film import ocr
from sonde import owners,PulseProbe
from emulateur_audio import EmulatorAudio,private_endpoint

def scr():
    # L'image et le titre viennent du même screencap.
    b=subprocess.run(['adb','exec-out','screencap','-p'],capture_output=True,timeout=7,check=True).stdout
    return Image.open(io.BytesIO(b)).convert('RGB')
def title(im):
    for psm in (11,6):
        words=ocr(im,psm)
        for name,box in words:
            if name!='mire':continue
            x,y,r,b=box
            for suffix,bb in words:
                if suffix in ('a','b') and 0<=bb[0]-r<im.width*.035 and abs((bb[1]+bb[3]-y-b)/2)<im.height*.014:
                    return suffix.upper(),[x,y,bb[2],bb[3]]
    return None,None
def marker(im):
    ch,n,_=read_marker(im)
    if ch and 0<=n<3000:return ch,n,'absolu'
    # Le voile dégradé des commandes peut assombrir le blanc. Conserver au
    # minimum 85 niveaux d'écart, le préambule complet, la parité, trois lignes.
    a=np.asarray(im.convert('L'));h,w=a.shape
    if w/h<1.5:return None,None,None
    for cut in (0,24,48):
        vh=min(h,w*9/16);vw=vh*16/9
        xs=np.rint((w-vw)/2+vw*(496+32*np.arange(30))/1920).astype(int)
        cy=round((h-vh)/2+vh*650/1080)-cut
        found=[]
        for yd in (-1,0,1):
            r=a[cy+yd,xs].astype(float);lo=float(r.min());hi=float(r.max())
            if hi-lo<85:break
            ch,n=decode(np.rint((r-lo)*255/(hi-lo)).astype(int))
            if not ch or n>=3000:break
            found.append((ch,n))
        if len(found)==3 and len(set(found))==1:return *found[0],'contraste_adaptatif'
    return None,None,None
def joined(pulse,lo,hi,destination):
    # Fenêtres du lecteur PCM entièrement avant et après l'acquisition de la
    # capture. Même classe de ton pendant toute cette tranche, aucune autre.
    past=[r for r in pulse.rows if lo-.55<=r['read_end']<=lo]
    future=[r for r in pulse.rows if hi<=r['read_start']<=hi+.55]
    if not past or not future:return False
    span=[r for r in pulse.rows if past[max(0,len(past)-2)]['read_start']<=r['read_start']<=future[min(1,len(future)-1)]['read_start']]
    return len(span)>=3 and all(r['tone']==destination and r['read_end']-r['read_start']<=.4 for r in span)
def shell(*args):return subprocess.run(['adb','shell',*args],capture_output=True,text=True,timeout=6).stdout
def guest_audio():
    uid=re.search(r'uid:(\d+)',shell('cmd','package','list','packages','-U',APK_PACKAGE))
    pid=shell('pidof','-s',APK_PACKAGE).strip()
    if not uid or not pid.isdigit():return {'media_zuno_active':None}
    blocks=re.split(r'(?=AudioPlaybackConfiguration\s+piid:)',shell('dumpsys','audio'),flags=re.I)
    active=[]
    for block in blocks:
        if 'AudioPlaybackConfiguration' not in block[:40]:continue
        line=block.splitlines()[0]
        u=re.search(r'u/pid:\s*(\d+)\s*/\s*(\d+)',line)
        if u and re.search(r'state:\s*started\b',line,re.I) and 'USAGE_MEDIA' in line:
            active.append((u[1],u[2]))
    return {'media_zuno_active':((uid[1],pid) in active) if active else None,
            'nombre_lecteurs_media_actifs_observes':len(active)}
def main(out):
    out.mkdir(parents=True,exist_ok=True);private=out.parent/'controle-prive';private.mkdir(exist_ok=True)
    result={'support':'émulateur Android TV, sink virtuel privé, FFT 100 ms ; aucune sortie micro ni onde publiée','scenes':[]}
    def save():(out/'synchronisme.json').write_text(json.dumps(result,indent=2,ensure_ascii=False))
    save();open_fixture(private)
    deadline=time.monotonic()+8
    while time.monotonic()<deadline:
        try:
            good,n=owners()
        except (OSError,ValueError,subprocess.SubprocessError):good,n=False,0
        if good:break
        time.sleep(.5)
    result.update(sink_zuno_proprietaire_emulateur=good,n_entrees_sink=n);save()
    if good:
        probe=PulseProbe();result['source_audio']='monitor Pulse privé du processus QEMU'
    else:
        result['source_audio']='sortie numérique du seul AVD du banc par streamAudio'
        try:private_endpoint()
        except (OSError,ValueError) as err:
            result['erreur_endpoint']=type(err).__name__;save();raise
        probe=EmulatorAudio()
    save();probe.start()
    try:
        for idx,ch in enumerate(('A','B','A')):
            record=dict(target=ch,captures=[]);result['scenes'].append(record)
            if idx:
                code=('KEYCODE_CHANNEL_DOWN','KEYCODE_CHANNEL_UP')[idx-1];begin=time.monotonic()
                lo,hi=clocked_key(code);record['ordre']=dict(touche=code,monotone_hote=[begin,time.monotonic()],uptime_android=[lo,hi])
            save()
            prev=None;shown=False;end=time.monotonic()+25;pair=False
            while time.monotonic()<end:
                lo=time.monotonic()
                try:im=scr()
                except (OSError,ValueError,subprocess.SubprocessError):continue
                hi=time.monotonic();channel,n,method=marker(im)
                if channel==ch and prev is not None and 0<(n-prev)%3000<300:pair=True
                prev=n if channel==ch else None
                title_ch,box=title(im)
                time.sleep(.18)
                if isinstance(probe,PulseProbe):auth,_=owners()
                else:auth=not probe.errors and probe.received>0
                sound=auth and joined(probe,lo,hi,ch)
                record['captures'].append(dict(hote_min=lo,hote_max=hi,marqueur=channel,compteur=n,methode=method,titre=title_ch,zone_titre=box,
                    ton_destination_autour_de_capture=sound,proprietaire_verifie=auth))
                # Sans attribution par Android du son, garder le résultat comme
                # coïncidence matérielle sur sink isolé alimenté par les mires.
                if pair and title_ch==ch and channel==ch and sound:
                    record['accord_simultane']=True;break
                if pair and not shown and not title_ch:
                    key('KEYCODE_INFO');shown=True;record['info_injectee_pour_lire_titre']=True
                time.sleep(.15)
            record['attribution_audio_android']=guest_audio();record['mouvement']=pair;record.setdefault('accord_simultane',False);save()
    finally:
        probe.stop()
        with (out/'frequences-sortie.csv').open('w') as f:
            writer=csv.DictWriter(f,fieldnames=['read_start','read_end','tone','hz','energy_fraction']);writer.writeheader();writer.writerows(probe.rows)
        result['n_fenetres_pcm']=len(probe.rows)
        result['paquets_api_sortie']=getattr(probe,'received',None)
        result['erreurs_sonde']=[e for e in probe.errors if e!='CANCELLED']
        save()
    if len(result['scenes'])!=3 or not all(r['accord_simultane'] for r in result['scenes']):raise RuntimeError('Correspondance audiovisuelle incomplète')
if __name__=='__main__':main(Path(sys.argv[1]))
