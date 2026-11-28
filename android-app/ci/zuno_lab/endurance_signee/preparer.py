"""Réutilise les sondes d'endurance avec le paquet signé, deux chaînes et des journaux d'incidents séparés."""
from pathlib import Path
import shutil,sys
src=Path('android-app/ci/zuno_lab/endurance')
out=Path(sys.argv[1]);out.mkdir(exist_ok=True,parents=True)
for p in src.glob('*.py'):shutil.copy(p,out/p.name)
def edit(name,anchor,new):
 p=out/name;s=p.read_text()
 if s.count(anchor)!=1:raise ValueError(f'Relire {name}, point de collecte {anchor[:40]}')
 s=s.replace(anchor,new);compile(s,str(p),'exec');p.write_text(s)
edit('fixture.py',"d=Path(sys.argv[1]);d.mkdir()", "d=Path(sys.argv[1]);d.mkdir(parents=True,exist_ok=True);channel=sys.argv[2];assert channel in ('A','B')")
edit('fixture.py',"'A %{n}'", "'%s %%{n}'")
edit('fixture.py',"y=(h-th)/2\"","y=(h-th)/2\" % channel")
edit('fixture.py',"'testsrc2=size=1920x1080:rate=25'", "('testsrc2=size=1920x1080:rate=25' if channel=='A' else 'color=c=0x76143f:size=1920x1080:rate=25')")
edit('fixture.py',"'sine=frequency=440:sample_rate=48000'", "f'sine=frequency={440 if channel==\"A\" else 880}:sample_rate=48000'")
edit('fixture.py',"marker('A')","marker(channel)")
edit('fixture.py',"'threads','2'" if "'threads','2'" in (out/'fixture.py').read_text() else "'-threads','2'", "'-threads',('2' if channel=='A' else '1')")
edit('origin.py','r"/A/s(\\d{9})\\.ts"', 'r"/[AB]/s(\\d{9})\\.ts"')
anchor="        if role=='bootstrap' and path=='/start.m3u8':"
edit('origin.py',anchor,'''        if role=='canary' and path=='/channels.m3u':
            body=('#EXTM3U\\n'+''.join(f'#EXTINF:-1 group-title="LAB",Mire {ch}\\nhttp://{host}:18472/{ch}/index.m3u8\\n' for ch in ('A','B'))).encode()
            status,mime=200,'application/x-mpegURL'
        elif role=='bootstrap' and path=='/start.m3u8':''')
edit('origin.py',"(path=='/A/index.m3u8' or segment)", "(path in ('/A/index.m3u8','/B/index.m3u8') or segment)")
edit('origin.py',"state['media']/Path(path).name","state['media']/path.split('/')[1]/Path(path).name")
edit('origin.py',"path in ('/start.m3u8','/A/index.m3u8')","path in ('/start.m3u8','/channels.m3u','/A/index.m3u8','/B/index.m3u8')")
edit('observe.py',"PKG='com.sevenmotion.tv.seven_tv.lab.diagnostic'","PKG='com.sevenmotion.tv.seven_tv.lab'")
edit('observe.py',"    first_fault=None","    first_fault=None\n    first_freeze=None\n    first_capture_failure=None")
anchor="            if first_fault is None and (repeat>=4 or unreadable>=4):"
edit('observe.py',anchor,'''            if first_capture_failure is None and capture=='failed':
                first_capture_failure=state
                (out/'premiere-capture-ratee.json').write_text(json.dumps(state,indent=2))
            if first_freeze is None and repeat>=4:
                first_freeze=dict(**state,lower_bound_s=repeat)
                (out/'premier-gel-optique.json').write_text(json.dumps(first_freeze,indent=2))
                bands=[entry[2] if entry[2] is not None else Image.new('L',(300,30),128) for entry in ring]
                times=[entry[1] for entry in ring]
                delays=[max(10,round((b-a)*1000)) for a,b in zip(times,times[1:])]+[1000]
                if bands:bands[0].save(out/'premier-gel.gif',save_all=True,append_images=bands[1:],duration=delays,loop=0)
                if first_fault is not None:
                    # La première anomalie peut avoir été une capture manquante longtemps avant le gel.
                    incident_folder=out/'gel-confirme';incident_folder.mkdir(exist_ok=True)
                    threading.Thread(target=forensic,args=(incident_folder,last_pid),daemon=True).start()
            if first_fault is None and (repeat>=4 or unreadable>=4):''')
edit('observe.py',"'first_incident':first_fault" if "'first_incident':first_fault" in (out/'observe.py').read_text() else 'first_incident=first_fault)', 'first_incident=first_fault,first_optical_freeze=first_freeze,first_capture_failure=first_capture_failure)')
