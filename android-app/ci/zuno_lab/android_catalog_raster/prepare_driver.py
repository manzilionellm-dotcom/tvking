"""Prépare le contrôleur hôte jetable, sans retoucher l'APK."""
from pathlib import Path
import sys
mode=sys.argv[1]
p=Path('ci/zuno_lab/android_catalog_cycles/run.py')
s=p.read_text()
needle="if key == 'mpegts':\n"
if s.count(needle)!=1:raise ValueError('Relire le serveur média')
insert=needle+'''            with (out/'media-requests.csv').open('a') as f:
                csv.writer(f).writerow([datetime.now(timezone.utc).isoformat(), time.monotonic()])
'''
if mode=='wait-1080-refus':insert+='''            self.send_response(503)
            self.send_header('Content-Length','0'); self.end_headers(); return
'''
p.write_text(s.replace(needle,insert))
q=Path('ci/zuno_lab/android_catalog_anr/observe.py');s=q.read_text()
old="values.sort(key=lambda x:-x['cpu_ps']);record("
assert s.count(old)==1
s=s.replace(old,'''values.sort(key=lambda x:-x['cpu_ps'])
            top=values[:6]
            if top:
                tids=" ".join(str(t['tid']) for t in top)
                # Lire les comm en une commande. Android peut refuser pour une app release.
                info=adb('shell',f'for t in {tids}; do echo "$t $(cat /proc/{pid}/task/$t/comm 2>/dev/null)"; done',lim=2)
                mapping=dict((v[0],v[1]) for ln in info.splitlines() if len(v:=ln.strip().split(maxsplit=1))==2)
                for val in top:val['comm']=mapping.get(str(val['tid']))
            record(''')
q.write_text(s)
