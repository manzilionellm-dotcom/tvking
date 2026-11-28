"""Adjoint à la route panel déjà validée le contrôle externe de chaque zap."""
from pathlib import Path
import runpy
runpy.run_path('android-app/ci/zuno_lab/android_catalog_normal_long/preparer.py',run_name='__main__')
p=Path('android-app/ci/zuno_lab/android_catalog_normal/normal.py');s=p.read_text()
def edit(old,new):
 global s
 if s.count(old)!=1:raise ValueError('Relire le pilote de reprise')
 s=s.replace(old,new)
edit("srcs={}","""srcs={}
media_history=[]
media_tx={}
sys.path.insert(0,str(Path('android-app/ci/zuno_lab/android_catalog_normal_reprise').resolve()))
from mire import write_stream""")
a=s.index("   srcs[act]=srcs.get(act,0)+1;note('media_requested'");b=s.index("  srcs[act]=srcs.get(act,0)+1\n",a)
s=s[:a]+"""   srcs[act]=srcs.get(act,0)+1;media_history.append((act,time.monotonic()));note('media_requested',stream=act)
   self.send_response(200);self.send_header('Content-Type','video/mp2t');self.end_headers()
   clip=(Path(os.environ['RUNNER_TEMP'])/'mires-grille'/('A.ts' if act=='media.1' else 'B.ts')) if act in ('media.1','media.2') else Path('android-app/ci/zuno_lab/android_catalog_fixture/mire.ts')
   write_stream(self,clip,lambda:media_tx.__setitem__(act,time.monotonic()))
   return
"""+s[b:]
a=s.index(' # Fin de la saisie initiale,');b=s.index(' # Refuser les nouvelles réponses catalogue',a)
s=s[:a]+Path(__file__).with_name('pilote.py.src').read_text()+s[b:]
compile(s,str(p),'exec');p.write_text(s)
