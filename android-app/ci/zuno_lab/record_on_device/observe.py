"""L'APK signé enregistre dix minutes, puis Android redémarre et le fichier est décodé."""
from datetime import datetime,timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from optical_witness import open_fixture,motion,key,APK_PACKAGE

folder='/sdcard/Android/data/'+APK_PACKAGE+'/files/Recordings'


def adb(*args,timeout=22):
    return subprocess.run(['adb',*args],text=True,capture_output=True,timeout=timeout)


def files():
    proc=adb('shell','find',folder,'-maxdepth','1','-type','f')
    return [f for f in proc.stdout.splitlines() if f.startswith(folder+'/') and f.endswith('.ts')]


def size(path):
    p=adb('shell','stat -c %s '+shlex.quote(path))
    return int(p.stdout.strip()) if p.stdout.strip().isdigit() else None


def stats(out):
    ledger=out.parent/'source'/'http.jsonl'
    if ledger.exists():
        events=[json.loads(l) for l in ledger.read_text().splitlines()]
        (out/'champs-source.json').write_text(json.dumps(sorted(events[0]) if events else []))


def run(out):
    out.mkdir()
    events=[]
    def emit(name,**kw):
        events.append(dict(event=name,time_s=time.monotonic(),utc=datetime.now(timezone.utc).isoformat(),**kw))
        (out/'session.json').write_text(json.dumps(events,indent=2))
    os.environ['ZUNO_PRELOADED_BY_PANEL']='yes'
    open_fixture(out)
    rows=[]
    if not motion(out,'avant','A',20,rows,True):
        key('KEYCODE_DPAD_CENTER')
        if not motion(out,'confirmation','A',30,rows,True):raise RuntimeError('Aucune chaîne active avant REC')
    before=set(files())
    entered=time.monotonic();key('KEYCODE_MEDIA_RECORD');emit('appui_REC')
    deadline=entered+40;created=None
    while time.monotonic()<deadline:
        names=set(files())-before
        if len(names)==1 and (size(next(iter(names))) or 0)>=188:
            created=names.pop();break
        time.sleep(1)
    if created is None:
        emit('creation_non_preuvee',visible_files=len(set(files())-before))
        raise RuntimeError('Aucun nouveau TS non vide attesté après la touche')
    begin=time.monotonic();emit('premiers_octets',bytes=size(created))
    while time.monotonic()-begin<605:
        stamp=time.monotonic()
        rt=motion(out,'pendant','A',5,[],False)
        service=adb('shell','dumpsys','activity','services',APK_PACKAGE).stdout
        svc=bool(re.search(r'isForeground=true|foregroundId=[1-9]',service))
        emit('lecture_REC',bytes=size(created),visible_motion=bool(rt),foreground_service=svc)
        time.sleep(max(0,min(20,605-(time.monotonic()-begin))-(time.monotonic()-stamp)))
    key('KEYCODE_MEDIA_RECORD');emit('arret_manuel',bytes=size(created))
    time.sleep(6)
    prefix=adb('shell','sha256sum '+shlex.quote(created)).stdout.split()
    if not prefix or not re.fullmatch(r'[a-f0-9]{64}',prefix[0]):raise RuntimeError('Empreinte du fichier indisponible')
    digest=prefix[0];emit('avant_redemarrage',sha256=digest,bytes=size(created))
    adb('reboot')
    time.sleep(4)
    for _ in range(140):
        try:
            if adb('shell','getprop','sys.boot_completed',timeout=5).stdout.strip()=='1':break
        except subprocess.SubprocessError:pass
        time.sleep(1)
    else:raise RuntimeError('Le redémarrage Android n’est pas confirmé')
    adb('shell','input','keyevent','KEYCODE_WAKEUP')
    adb('shell','wm','dismiss-keyguard')
    adb('reverse','tcp:18471','tcp:18471');adb('reverse','tcp:18789','tcp:18787')
    adb('shell','am','start','-n',APK_PACKAGE+'/com.example.tv_king.MainActivity')
    after=adb('shell','sha256sum '+shlex.quote(created)).stdout.split()
    if not after or after[0]!=digest:raise RuntimeError('Le fichier diffère après le redémarrage Android')
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp)/'rec.ts'
        subprocess.run(['adb','pull',created,str(p)],check=True,capture_output=True)
        with p.open('rb') as f:d=hashlib.file_digest(f,'sha256').hexdigest()
        if d!=digest:raise RuntimeError('La copie de contrôle diffère')
        cmd=['ffprobe','-v','error','-count_frames','-show_entries','format=duration,size:stream=codec_type,codec_name,width,height,nb_read_frames','-of','json',str(p)]
        media=json.loads(subprocess.check_output(cmd,timeout=220))
        emit('decode_apres_reboot',sha256=d,file=media)
        subprocess.run(['ffmpeg','-v','error','-threads','2','-i',str(p),'-map','0:v:0','-map','0:a:0','-f','null','-'],check=True,timeout=220)
        subprocess.run(['ffmpeg','-v','error','-ss','300','-i',str(p),'-t','2','-vf','scale=640:360','-threads','2','-c:v','libx264','-c:a','aac','-y',str(out/'extrait-midpoint.mp4')],check=True,timeout=45)
        duration=float(media['format']['duration']);vid=[s for s in media['streams'] if s['codec_type']=='video'];audio=[s for s in media['streams'] if s['codec_type']=='audio']
        good=duration>=598 and bool(vid and audio and int(vid[0]['nb_read_frames'])>=14900)
        emit('lecture_integrale_FFmpeg',valid=good)
        if not good:raise RuntimeError('Durée ou flux incomplet au décodage')
    stats(out)
if __name__=='__main__':run(Path(sys.argv[1]))
