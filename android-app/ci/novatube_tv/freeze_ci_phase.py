"""Copy a checkpoint of a running soak without stopping playback."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import time

base = Path('pilot-results')
checkpoint = Path('freeze-checkpoint')
finished = Path('freeze-run.exit')
if sys.argv[1] == 'wait-final':
    while not finished.exists():
        time.sleep(15)
    raise SystemExit(int(finished.read_text().strip()))
while not finished.exists():
    origin = base/'observation-start.json'
    if origin.exists() and time.monotonic() - json.loads(origin.read_text())['monotonic'] >= 820:
        break
    time.sleep(5)
if (base / "device-logcat").is_dir():
    subprocess.run([sys.executable, str(Path(__file__).with_name("freeze_device_log.py")), "collect", str(base)])
checkpoint.mkdir(exist_ok=True)
for path in base.rglob('*'):
    if not path.is_file():
        continue
    if path.name in ('last.png','long-end.png','screen.png') or path.suffix in ('.json','.jsonl','.txt','.tsv','.csv','.log'):
        dest = checkpoint/path.relative_to(base)
        dest.parent.mkdir(parents=True,exist_ok=True)
        try:
            shutil.copyfile(path,dest)
        except FileNotFoundError:
            pass
