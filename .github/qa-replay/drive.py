"""Parcours graphique sur le fichier signé. Les flux et les identifiants sont fictifs."""
import collections, csv, io, json, os, re, shlex, subprocess, sys, time
from pathlib import Path
from PIL import Image, ImageChops

out=Path(sys.argv[1]); events=out/'fournisseur.jsonl'; pkg='com.sevenmotion.novatube.max'; proof={}; before=time.monotonic(); current=out/'courant.png'; step=''
def setstep(name):
    global step
    step=name; print('Étape',step,flush=True)
def save(): (out/'lecture.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2))
def adb(*args,timeout=10):return subprocess.run(['adb','-s','emulator-5554',*map(str,args)],capture_output=True,check=True,timeout=timeout).stdout
def key(k,pause=.7):adb('shell','input','keyevent',k);time.sleep(pause)
def snap(name=None):
    try:
        b=adb('exec-out','screencap','-p',timeout=24)
    except (subprocess.TimeoutExpired,subprocess.CalledProcessError):
        adb('shell','screencap','-p','/data/local/tmp/snapshot.png',timeout=28);b=adb('exec-out','cat','/data/local/tmp/snapshot.png',timeout=15)
    current.write_bytes(b)
    if name:(out/(name+'.png')).write_bytes(b)
    return b

def ocr():
    snap(); v=subprocess.run(['tesseract',str(current),'stdout','--psm','11','tsv'],capture_output=True,check=True,timeout=15).stdout.decode(errors='replace');lines=collections.defaultdict(list)
    for w in csv.DictReader(io.StringIO(v),delimiter='\t',quoting=csv.QUOTE_NONE):
        if w.get('level')=='5' and w.get('text','').strip():lines[tuple(w[k] for k in ('block_num','par_num','line_num'))].append(w)
    result=[]
    for words in lines.values():
        text=' '.join(w['text'] for w in words);pos=0;bounds=[]
        for w in words:
            l,t,wi,h=[int(w[k]) for k in ('left','top','width','height')]; bounds.append((pos,pos+len(w['text']),l,t,l+wi,t+h));pos+=len(w['text'])+1
        result.append((text,bounds))
    (out/'ecran-ocr.txt').write_text('\n'.join(v[0] for v in result));return result

def locate(data,expr):
    for line,bounds in data:
        m=re.search(expr,line,re.I)
        if not m:continue
        found=[b for b in bounds if b[0]<m.end() and m.start()<b[1]]
        if found:return ((min(b[2] for b in found)+max(b[4] for b in found))//2,(min(b[3] for b in found)+max(b[5] for b in found))//2)

def word(expr,limit=18,tap=False):
    end=time.monotonic()+limit
    while time.monotonic()<end:
        xy=locate(ocr(),expr)
        if xy:
            if tap:adb('shell','input','tap',*xy);time.sleep(.7)
            return True
        time.sleep(.4)
    return False

def must(value,why):
    if not value:raise RuntimeError(why)

def logs():
    return [json.loads(l) for l in events.read_text().splitlines() if l.strip()] if events.exists() else []

def got(label):return any(e['kind']==label for e in logs())

def color_sample(mode):
    img=Image.open(io.BytesIO(snap())).convert('RGB').resize((96,54)); pts=list(img.crop((9,5,87,49)).getdata());n=len(pts);
    if mode=='replay':count=sum(1 for r,g,b in pts if r>115 and r>1.9*(b+1) and r>1.9*(g+1))
    else:count=sum(1 for r,g,b in pts if b>110 and b>1.8*(r+1) and b>1.8*(g+1))
    return count/n,img

def playing(mode,limit=70):
    end=time.monotonic()+limit
    while time.monotonic()<end:
        pct,im=color_sample(mode)
        if pct>.48:
            time.sleep(1.3);pct2,im2=color_sample(mode)
            if pct2<=.48:continue
            # Le carré animé de la mire occupe le centre de la vidéo.
            roi=(34,16,62,38);diff=ImageChops.difference(im.crop(roi),im2.crop(roi)).convert('L'); changed=sum(n for level,n in enumerate(diff.histogram()) if level>10)
            if changed<8:continue
            snap('lecture-'+mode);proof[mode]={'fraction_couleur':round(min(pct,pct2),3),'pixels_centraux_changes':changed,'surface_capture':True};save();return True
        time.sleep(.8)
    return False

past=r'Past (?:programme|program|show)|[ÉE]missions pass[ée]es';hist=r'My (?:watch )?history|Mon historique';future=r'FUTURE\s+NOVA';listing=r'AURORA\s+QA';hub=r'^(?:.?\s*)?Guide(?:\s*.?)?$';current_program=r'LIVE\s+STUDIO';archive=r'ARCHIVE\s+ALPHA'
def open_channel(limit=50):
    deadline=time.monotonic()+limit;last_action=0
    while time.monotonic()<deadline:
        data=ocr()
        if locate(data,past) or locate(data,hist):return True
        if time.monotonic()-last_action<2.4:continue
        xy=locate(data,listing) or locate(data,hub)
        if xy:adb('shell','input','tap',*xy);last_action=time.monotonic();time.sleep(1)
        else:time.sleep(.7)
    return False

def back_to_channel():
    for _ in range(3):
        key('KEYCODE_BACK',1.5)
        if open_channel(8):return True
    return False

def run():
    setstep('import de la liste personnelle')
    must(word(r'Add.*?M3[Uu1]',25,True),'Accueil M3U absent');time.sleep(2)
    if not word(r'Add my source|Name \(optional\)|Sign in and load',14):
        must(word(r'Add.*?M3[Uu1]',7,True),'bouton M3U introuvable');must(word(r'Add my source|Name \(optional\)|Sign in and load',20),'formulaire absent')
    # Le champ des liens a l’autofocus. Les caractères & restent littéraux dans le shell Android.
    url='http://127.0.0.1:8783/get.php?username=lab&password=lab&type=m3u_plus&output=mpegts'
    adb('shell','input','text',shlex.quote(url));time.sleep(.5);snap('source-saisie');key('KEYCODE_ENTER',2)
    if not got('get_live_streams'):
        if not word(r'Sign in and load|Connect and load|Load playlist',5,True):key('KEYCODE_DPAD_CENTER',1)
    deadline=time.monotonic()+35
    while not got('get_live_streams') and time.monotonic()<deadline:
        if word(r'Sign in and load|Connect and load|Load playlist',3,True):time.sleep(1)
    must(got('get_live_streams'),'Aucun import Xtream reçu')
    proof['import']=True;save();setstep('ouverture du guide');must(open_channel(60),'Impossible d’ouvrir le guide de la chaîne');snap('guide-chaine')
    setstep('programme futur');must(word(future,20,True),'programme futur introuvable');must(word(r'^Close$|^Fermer$',18,True),'fiche du futur absente');must(not got('replay'),'archive ouverte pour un programme futur');proof['a_venir']=True;save()
    setstep('émission passée');must(word(past,20,True),'onglet du passé absent');must(word(archive,22,True),'émission passée absente');must(playing('replay',60),'mire du replay absente');must(got('replay') and not got('wrong_archive'),'adresse de replay erronée');time.sleep(4);save()
    setstep('historique après lecture');must(back_to_channel(),'retour au guide impossible');must(word(hist,20,True),'onglet historique absent');must(word(archive,30),'émission rejouée absente de l’historique');proof['historique']=True;snap('historique');save()
    setstep('retour au direct et repli Xtream');must(word(r'Current and upcoming|Upcoming|en cours et',18,True),'onglet du direct absent');must(word(current_program,20,True),'émission en cours absente');must(playing('live',95),'mire du direct absente');must(got('short404') and got('live'),'transition 404 vers /live non observée');proof['repli_direct']=True;save()
    setstep('état Android');must(adb('shell','pidof',pkg).strip(),'lecteur arrêté');crash=adb('logcat','-b','crash','-d').decode(errors='replace');must(not(re.search(r'FATAL EXCEPTION|Fatal signal',crash) and pkg in crash),'plantage du lecteur');proof['processus_actif']=True;save()

try:run()
except Exception as e:
    proof['echec']={'etape':step,'motif':str(e)[:160]};save()
    try:snap('dernier-ecran');ocr()
    except Exception:pass
    raise
finally:
    proof['duree_s']=round(time.monotonic()-before,1);proof['appels']=[e['kind'] for e in logs()];save()
