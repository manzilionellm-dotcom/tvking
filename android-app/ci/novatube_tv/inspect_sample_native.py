"""Sample active native stacks on this debuggable QA app, after the primary snapshots."""
import gzip,json,os,re,subprocess,sys,time
from pathlib import Path
root=Path(sys.argv[1]);root.mkdir(parents=True,exist_ok=True)
pkg=sys.argv[2]
assert re.fullmatch(r"com\.sevenmotion\.novatube\.tv",pkg)
adb=["adb","-s",os.environ.get("ANDROID_SERIAL","emulator-5554")]
def invoke(cmd, label, binary=False):
    start=time.monotonic()
    try:p=subprocess.run(adb+cmd,capture_output=True,timeout=15)
    except subprocess.TimeoutExpired as e:p=subprocess.CompletedProcess(cmd,124,e.stdout or b'',e.stderr or b"timeout")
    if binary:return p
    (root/(label+".txt")).write_bytes(p.stdout+b"\n"+p.stderr)
    with (root/"commands.jsonl").open("a") as f:f.write(json.dumps({"label":label,"rc":p.returncode,"start":start,"end":time.monotonic()})+"\n")
    return p
pid=invoke(["shell","pidof",pkg],"pid").stdout.decode().strip().split()
if len(pid)!=1 or not pid[0].isdigit():sys.exit("no live application pid")
remote="/data/local/tmp/novatube-qa-native.data"
options=["-e","task-clock","-f","199","--call-graph","fp","--duration","2"]
r=invoke(["shell","simpleperf","record","--app",pkg,"-p",pid[0],*options,"-o",remote],"record-app")
prefix=["shell"];path=remote
if r.returncode:
    prefix=["shell","run-as",pkg];path="files/novatube-qa-native.data"
    r=invoke(prefix+["/system/bin/simpleperf","record","-p",pid[0],*options,"-o",path],"record-uid")
if r.returncode:sys.exit("simpleperf denied or unavailable")
rr=invoke(prefix+["simpleperf","report","-i",path,"-g","caller","--sort","tid,dso,symbol"],"report")
if rr.returncode:
    rr=invoke(prefix+["simpleperf","report","-i",path,"-g"],"report-simple")
d=invoke(prefix+["simpleperf","dump","-i",path],"dump")
data=invoke(["exec-out",*(prefix[1:]),"cat",path],"data",True)
if data.returncode==0 and data.stdout.startswith(b"PERFILE2"):
    (root/"native.perfdata").write_bytes(data.stdout)
if (root/"dump.txt").exists():
    with gzip.open(root/"dump.txt.gz","wb") as target:target.write((root/"dump.txt").read_bytes())
    (root/"dump.txt").unlink()
assert len(data.stdout)>512 and rr.returncode==0,(len(data.stdout),rr.returncode)
print("Native task-clock sample",len(data.stdout),rr.stdout.decode(errors="replace")[:300])
