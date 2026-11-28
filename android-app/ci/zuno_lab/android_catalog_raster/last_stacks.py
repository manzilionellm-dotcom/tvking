import json,re,subprocess,sys
from pathlib import Path
out=Path(sys.argv[1]);p=out/'triage.json'
j=json.loads(p.read_text()) if p.exists() else {}
known=set(j.get('pids_seen',[]));pkg='com.sevenmotion.tv.seven_tv.lab.catalog'
def run(*args,seconds=30):
 try:return subprocess.run(['adb',*args],capture_output=True,text=True,timeout=seconds).stdout
 except (subprocess.TimeoutExpired,OSError):return ''
def scrub(line):
 line=re.sub(r'https?://\S+|(?:\b[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b','[expurgé]',line)
 return re.sub(r'/data/app/\S+?(/(?:base\.apk|lib/[^/]+/lib[^ /]+\.so))',r'[app]\1',line)
summary={'queried':[],'pids':sorted(known),'new_anr_same_pid':j.get('new_anr_same_pid',[])}
if j.get('new_anr_same_pid') or j.get('lastanr'):
 for source,cmd in [('activity-lastanr',('shell','dumpsys','activity','lastanr-traces')),('dropbox-anr',('shell','dumpsys','dropbox','--print','data_app_anr'))]:
  s=run(*cmd)
  summary['queried'].append({'source':source,'response_chars':len(s),'target_name_seen':pkg in s})
  txt=[]
  for sec in re.split(r'(?m)(?=^----- pid \d+ at )',s):
   m=re.match(r'^----- pid (\d+) at ',sec)
   if not m or m[1] not in known or not re.search(r'^Cmd line:\s*'+re.escape(pkg)+r'\s*$',sec,re.M):continue
   lines=sec.splitlines()
   for i,line in enumerate(lines):
    tag=re.match(r'^"([^"]+)"',line)
    if not tag or not re.search(r'(^main$|\.ui$|\.raster$|\.platform$|DartWorker|ExoPlayer|Flutter)',tag[1]):continue
    txt.append(scrub(line))
    for ln in lines[i+1:i+29]:
     if not ln.strip() or ln.startswith('"'):break
     if re.search(r'native: #|^\s*#\d|^\s+at |\| state=',ln):txt.append(scrub(ln))
  if txt:(out/(source+'.txt')).write_text('\n'.join(txt)+'\n')
(out/'stack-sources.json').write_text(json.dumps(summary,indent=2))
