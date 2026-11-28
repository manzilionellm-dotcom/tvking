"""75 s sur le lecteur du paquet livré ; le compositeur et le décodeur gardent leurs unités propres."""
import csv,hashlib,io,json,math,os,re,shlex,statistics,subprocess,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from optical_witness import APK_PACKAGE,open_fixture,motion,key
from android_ui import visible_nodes

def adb(*args,binary=False):
    try:
        p=subprocess.run(['adb',*args],timeout=7,capture_output=True)
        return p.stdout if binary else p.stdout.decode(errors='replace')
    except (OSError,subprocess.SubprocessError):return b'' if binary else ''
def shell(*args):return adb('shell',shlex.join(args))
def h(s):return hashlib.sha256(s.encode()).hexdigest()[:16]
def layers():
    return set(l.strip() for l in shell('dumpsys','SurfaceFlinger','--list').splitlines() if APK_PACKAGE in l and 'SurfaceView' in l and len(l)<512)
def timing(name):
    data=shell('dumpsys','SurfaceFlinger','--latency',name).splitlines()
    period=int(data[0]) if data and data[0].isdigit() and 1e6<int(data[0])<1e9 else None
    rows=[]
    for line in data[1:]:
        row=line.split()
        if len(row)==3 and all(x.isdigit() for x in row):
            a,b,c=map(int,row)
            if all(0<t<2**63-1 for t in (a,b,c)):rows.append((a,b,c))
    return period,rows
def metrics(raw,pkg,pid):
    result=[]
    for line in raw.splitlines():
        if not re.search(r'(?<![\w.])'+re.escape(pkg)+r'(?![\w.])',line):continue
        if not re.search(r'video/(?:avc|hevc|vp9|av01)',line,re.I):continue
        if 'mediacodec' not in line.lower() and 'frames_rendered' not in line.lower():continue
        # Deux formats AOSP : item (package,pid,uid) ou export statsd package_name.
        stamp=re.search(r'\('+re.escape(pkg)+r',\s*(\d+),\s*\d+\)',line)
        if stamp and stamp[1]!=pid:continue
        sid=re.search(r'(?:log[-_]session[-_]id|session[-_]id)\s*[:=]\s*["\']?([A-Za-z0-9._-]{4,})',line,re.I)
        if not sid:continue
        fields={}
        for name in ('frames-rendered','frames-dropped','frames-skipped','frames-released','frame-rate','width','height'):
            match=re.search(r'(?:\.|\b)'+name.replace('-',r'[-_]')+r'\s*[:=]\s*(\d+(?:[.]\d+)?)',line,re.I)
            if match:fields[name]=float(match[1])
        if fields:
            result.append(dict(session_digest=h(sid[1]),pid_in_record=bool(stamp),fields=fields))
    return result
def display():
    raw=shell('dumpsys','display')
    info=[]
    # Seule l'entrée DisplayInfo de l'écran utilisé est admissible ; les autres modes supportés ne sont pas des mesures.
    for line in raw.splitlines():
        if 'DisplayInfo{' not in line or not re.search(r'displayId[ =]+0\b',line):continue
        mode=re.search(r'\bmode(?:Id)?[ =]+(\d+)',line)
        override=re.search(r'\brenderFrameRate[ =]+([\d.]+)',line)
        native=None
        if mode:
            blocks=re.findall(r'\{(?:id|modeId)[= ]+(\d+),[^{}]*?\b(?:fps|refreshRate)[= ]+([\d.]+)[^{}]*\}',line)
            native=next((float(v) for k,v in blocks if k==mode[1]),None)
        if mode or override:info.append(dict(mode=int(mode[1]) if mode else None,active_mode_hz=native,render_frame_rate=float(override[1]) if override else None))
    return info
def summary(values):
    if not values:return None
    vals=sorted(values)
    return dict(n=len(vals),median=statistics.median(vals),p95=vals[math.ceil(.95*len(vals))-1],max=vals[-1])
def cadence(text):
    pattern=r'(?:decoder output|sortie d[eé]codeur)\s*[:.]?\s*(\d+[,.]\d+)\s*(?:frames|images)\s*/\s*s[^\n]{0,9}?(\d+)\s*(?:dropped|perdues)\s*/\s*(\d+[,.]\d+)\s*s\b'
    m=re.search(pattern,text,re.I)
    return dict(rendered_fps=float(m[1].replace(',','.')),dropped=int(m[2]),window_s=float(m[3].replace(',','.'))) if m else None
def label(out):
    key('KEYCODE_INFO');time.sleep(.35)
    raw=adb('exec-out','screencap','-p',binary=True)
    text=''
    if raw:
        try:
            from PIL import Image
            im=Image.open(io.BytesIO(raw));bbox=(0,int(im.height*.55),im.width,int(im.height*.94));crop=im.crop(bbox);mem=io.BytesIO();crop.save(mem,format='PNG')
            text=subprocess.run(['tesseract','stdin','stdout','--psm','6'],input=mem.getvalue(),capture_output=True,timeout=7).stdout.decode(errors='replace')
        except (ValueError,OSError,subprocess.SubprocessError):pass
    got=cadence(text)
    if got:return {'sensor':'pixels_ocr',**got}
    try:values=visible_nodes(APK_PACKAGE)
    except (ValueError,OSError,subprocess.SubprocessError):values=[]
    for s,*_ in values:
        if got:=cadence(s):return {'sensor':'accessibilite_du_paquet',**got}
    return None
def main(out):
    out.mkdir(parents=True,exist_ok=True)
    private=out.parent/'navigation-privee';private.mkdir(exist_ok=True)
    pid=shell('pidof','-s',APK_PACKAGE).strip()
    if not pid.isdigit():raise RuntimeError('Processus absent avant ouverture')
    before=layers();result=dict(package=APK_PACKAGE,pid_initial=pid,display_start=display(),media_before=metrics(shell('dumpsys','media.metrics'),APK_PACKAGE,pid))
    write=lambda:(out/'mesure.json').write_text(json.dumps(result,indent=2,ensure_ascii=False))
    write();open_fixture(private)
    if not motion(private,'A-initiale','A',25,[]):raise RuntimeError('Mire A mobile initiale absente')
    start=time.monotonic()
    raw={};periods={};polled=[];prior={};coverage={};known=layers();list_at=start
    while time.monotonic()-start<75:
        tick=time.monotonic()
        if tick-list_at>=5:
            known=layers();list_at=tick
        for ln in sorted(known):
            per,rows=timing(ln)
            if per:periods.setdefault(ln,set()).add(per)
            if not rows:continue
            present={r[1] for r in rows}
            if ln not in raw:
                raw[ln]={};coverage[ln]=[]
            # Le premier anneau peut précéder l'intervalle : fixer le dernier
            # timestamp déjà présent, puis calculer seulement les mises à jour.
            if ln in prior:
                old=prior[ln]
                contiguous=bool(present&old)
                coverage[ln].append(contiguous)
                last=max(old)
                raw[ln].update({r[1]:r for r in rows if r[1]>last})
            prior[ln]=present
        polled.append([tick-start,time.monotonic()-tick])
        time.sleep(max(0,.9-(time.monotonic()-tick)))
    end=time.monotonic();same=shell('pidof','-s',APK_PACKAGE).strip()==pid
    result.update(actual_seconds=end-start,same_pid=same,display_end=display(),polls=polled,layers=[])
    with (out/'composition.csv').open('w') as f:
        writer=csv.writer(f);writer.writerow(['layer_digest','desired_ns','actual_present_ns','ready_ns'])
        for ln,records in raw.items():
            seq=[records[k] for k in sorted(records)]
            for row in seq:writer.writerow([h(ln),*row])
            gaps=[(b[1]-a[1])/1e6 for a,b in zip(seq,seq[1:])]
            result['layers'].append(dict(layer_digest=h(ln),exists_before_open=ln in before,buffer_layer='BLAST' in ln,frames=len(seq),
                output_period_ns=sorted(periods.get(ln,set())),all_poll_rings_overlap=all(coverage[ln]),missing_ring_overlaps=coverage[ln].count(False),
                presented_intervals_ms=summary(gaps),jitter_abs_from_40ms=summary([abs(n-40) for n in gaps]),fps_observe=(len(seq)-1)/((seq[-1][1]-seq[0][1])/1e9) if len(seq)>1 else None))
    scope=Path(os.environ['TRACE_SOURCE'])
    req=[json.loads(l) for l in scope.read_text().splitlines()] if scope.exists() else []
    relevant=[r for r in req if r['ch']=='A' and r['name'].endswith('.ts') and r['end']>=start and r['start']<=end]
    inner=[r for r in relevant if r['start']>=start and r['end']<=end]
    with (out/'segments.json').open('w') as f:json.dump(relevant,f)
    result.update(motion_after=bool(motion(private,'A-finale','A',20,[])),media_end=metrics(shell('dumpsys','media.metrics'),APK_PACKAGE,pid),
                  source=dict(duration_s=end-start,segments_overlapping=len(relevant),segments_entire=len(inner),lower_payload_bps=sum(r['body_bytes'] for r in inner)*8/(end-start),upper_payload_bps=sum(r['body_bytes'] for r in relevant)*8/(end-start)))
    write()
    result['decoder_label_after_observation']=label(out)
    key('KEYCODE_BACK');time.sleep(3)
    result['media_after_close']=metrics(shell('dumpsys','media.metrics'),APK_PACKAGE,pid)
    result['conventions']='SurfaceFlinger mesure les présentations des surfaces du paquet, pas les compteurs internes du décodeur. Un registre codec sans l’identité du paquet et de la session est exclu. La ligne du lecteur rapporte sa propre fenêtre Media3. Le débit borne les octets de corps TS écrits par la source sur la fenêtre.'
    write()
    if not same or not result['motion_after'] or not relevant:raise RuntimeError('Conditions de lecture non confirmées aux deux bornes')
if __name__=='__main__':main(Path(sys.argv[1]))
