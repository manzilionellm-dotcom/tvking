"""Répétitions isolées. Le diagnostic APK reste celui de 46091531061."""
import csv
from datetime import datetime,timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time
import zipfile

out,apk,movie,mode=Path(sys.argv[1]),Path(sys.argv[2]),Path(sys.argv[3]),sys.argv[4]
pkg='com.sevenmotion.tv.seven_tv.lab.catalog'
out.mkdir(exist_ok=True,parents=True)
temp=Path(os.environ['RUNNER_TEMP'])
source=Path('ci/zuno_lab/android_catalog_cycles/run.py').read_text()
def edit(old,new):
    global source
    if source.count(old)!=1:raise RuntimeError('Pilote de capture à relire')
    source=source.replace(old,new)
edit('for i in range(1,31):','for i in range(1,2):')
edit("while time.monotonic()-start<900:", "while time.monotonic()-start<12:")
edit("900-(time.monotonic()-start)","12-(time.monotonic()-start)")
edit("==30 and state['cycles'][-1]['closes']==30","==1 and state['cycles'][-1]['closes']==1")
if mode!='immediate-meminfo':
    edit('threading.Thread(target=sampleresources,daemon=True).start()', 'pass  # désactiver le dumpsys meminfo répété')
    edit("sample('avant',0)", "pass  # aucune collecte du tas avant les entrées")
if mode=='wait-light':
    edit("for i in range(1,2):","time.sleep(55)\n    for i in range(1,2):")
edit("adb('shell','input','keyevent',str(key))", """at=time.monotonic()
    adb('shell','input','keyevent',str(key))
    with (out/'actual-keys.csv').open('a') as f:
        csv.writer(f).writerow([datetime.now(timezone.utc).isoformat(),at,key,round(time.monotonic()-at,3)])""")
driver=temp/'catalog-triage.py';driver.write_text(source)
def now():return datetime.now(timezone.utc).isoformat()
def adb(*args,lim=5):
    try:
        return subprocess.run(['adb',*args],capture_output=True,text=True,timeout=lim).stdout.strip()
    except (OSError,subprocess.TimeoutExpired):return ''
def record(reason,fields):
    with (out/'observer.jsonl').open('a') as f:f.write(json.dumps({'utc':now(),'mono':time.monotonic(),'event':reason,**fields})+'\n')
def clean(s):
    s=re.sub(r'(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}|https?://\S+|/data/(?:user|app)/\S+','[expurgé]',s)
    return s
def dump_exit():
    s=adb('shell','dumpsys','activity','exit-info',pkg)
    parts=re.split(r'(?=ApplicationExitInfo\s*(?:#|\())',s)
    lines=[p for p in parts if ('reason=' in p and pkg in p)]
    result=[]
    for part in lines:
        fields={k:m.group(1) for k,regex in {
           'timestamp':r'timestamp=([0-9T .:+-]+)', 'pid':r'\bpid=(\d+)', 'process':r'\bprocess=([^\s,}]+)',
           'reason':r'\breason=(\d+\s*\([^)]*\))', 'subreason':r'\bsubreason=(\d+\s*\([^)]*\))',
           'status':r'\bstatus=(\d+)', 'pss':r'\bpss=(\d+)', 'rss':r'\brss=(\d+)'}.items() if (m:=re.search(regex,part))}
        result.append(fields)
    return result
def last_anr():
    d=adb('shell','dumpsys','activity','lastanr',lim=12)
    if pkg not in d:return []
    return [clean(ln.strip())[:380] for ln in d.splitlines() if
            re.search(r'ANR in |Input dispatching timed out|\bReason:|^\s*PID:|^\s*Time:|CPU usage from',ln)][:16]
stop=threading.Event()
known=set()
def watch():
    previous_pid=None;last_stall=None
    while not stop.is_set():
        pid=adb('shell','pidof',pkg,lim=2).strip();t=time.monotonic()
        if pid.isdigit():
            known.add(pid)
            if pid!=previous_pid:record('pid_present',{'pid':pid})
            # ps lit les structures procfs : aucune injection, vidage de tas ou pause du processus.
            s=adb('shell','ps','-T','-p',pid,'-o','TID,%CPU,NAME',lim=3)
            values=[]
            for line in s.splitlines()[1:]:
                m=re.match(r'\s*(\d+)\s+([0-9.]+)\s+([^/\s][^\s]{0,40})\s*$',line)
                if m:values.append({'tid':int(m[1]),'cpu_ps':float(m[2]),'thread':clean(m[3])})
            values.sort(key=lambda x:-x['cpu_ps']);record('thread_sample',{'pid':pid,'read_s':round(time.monotonic()-t,3),'threads':values[:12]})
            ef=out/'events.jsonl'
            if ef.exists():
                try:
                    line=ef.read_text().splitlines()[-1];last=json.loads(line)
                except (IndexError,ValueError):last={}
                then=last.get('host_monotonic')
                if then is not None and t-then>9 and last_stall!=then:
                    last_stall=then
                    record('probe_silent_target_still_alive',{'pid':pid,'gap_s':round(t-then,3),'last_event':last.get('event'),'activity':last_anr()})
        elif previous_pid:
            record('pid_absent',{'previous':previous_pid,'exit':dump_exit(),'lastanr':last_anr()})
        previous_pid=pid
        stop.wait(3)
def stacks():
    archive=temp/'triage-private.zip'
    try:
        code=subprocess.run(['adb','bugreport',str(archive)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=190).returncode
    except (OSError,subprocess.TimeoutExpired):code=-1
    result={'bugreport_return':code,'anr_files':0,'matched_pid_files':0,'threads':{}}
    if archive.is_file() and zipfile.is_zipfile(archive):
      with zipfile.ZipFile(archive) as z:
       for f in z.infolist():
        if '/data/anr/' not in f.filename or f.file_size>48*1024*1024:continue
        result['anr_files']+=1
        text=z.read(f).decode('utf-8','replace')
        for section in re.split(r'(?m)(?=^----- pid \d+ at )',text):
            pid=re.match(r'^----- pid (\d+) at ',section)
            if not pid or pid[1] not in known or not re.search(r'^Cmd line:\s*'+re.escape(pkg)+r'\s*$',section,re.M):continue
            result['matched_pid_files']+=1
            lines=section.splitlines(); collected=[]
            for i,line in enumerate(lines):
                tag=re.match(r'^"([^"]+)"',line)
                if not tag or not re.search(r'(^main$|\.ui$|\.raster$|\.platform$|DartWorker|FlutterEngine|ExoPlayer)',tag[1]):continue
                collected.append(clean(line)); result['threads'][tag[1]]=result['threads'].get(tag[1],0)+1
                for ln in lines[i+1:i+27]:
                    if not ln.strip() or ln.startswith('"'):break
                    if re.search(r'(?:native: #|^\s*#\d|^\s+at |\| state=)',ln):collected.append(clean(ln))
            if collected:
                (out/f'stacks-{pid[1]}-{result["matched_pid_files"]}.txt').write_text('\n'.join(collected)+'\n')
      archive.unlink(missing_ok=True)
    return result
before=dump_exit()
record('start',{'mode':mode,'before_exit':before,'device_epoch':adb('shell','date','+%s')})
thread=threading.Thread(target=watch,daemon=True);thread.start()
rc=subprocess.run([sys.executable,str(driver),str(out),str(apk),str(movie)]).returncode
time.sleep(2);stop.set();thread.join(timeout=10)
after=dump_exit();matched=[e for e in after if e.get('pid') in known and str(e.get('reason','')).startswith('6 ') and e not in before]
result={'mode':mode,'driver_rc':rc,'pids_seen':sorted(known),'before':before,'after':after,'new_anr_same_pid':matched,
        'lastanr':last_anr(),'ended':now(),'remaining_pid':adb('shell','pidof',pkg)}
if matched or result['lastanr']:result['stacks']=stacks()
(out/'triage.json').write_text(json.dumps(result,indent=2,ensure_ascii=False))
print(json.dumps(result,ensure_ascii=False))
if rc:sys.exit(1)
