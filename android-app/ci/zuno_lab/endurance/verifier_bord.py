from pathlib import Path
import csv,hashlib,json,os,signal,subprocess,time,tempfile
import argparse
args=argparse.ArgumentParser()
args.add_argument('fixture',type=Path);args.add_argument('module',type=Path);args.add_argument('output',type=Path)
args.add_argument('--match',nargs=2)
opts=args.parse_args()
source=opts.fixture.resolve(); module=opts.module.resolve();dest=opts.output
with tempfile.TemporaryDirectory() as tmpd:
    tmp=Path(tmpd); d=tmp/'A'
    child=subprocess.Popen(['python3',str(source),str(d)],env={**os.environ,'PYTHONPATH':str(module)},stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    try:
        deadline=time.monotonic()+24
        while not (d/'s000000003.ts').exists() and time.monotonic()<deadline and child.poll() is None:time.sleep(.2)
        assert (d/'s000000003.ts').is_file(),child.stderr.read().decode() if child.poll() is not None else 'mire en retard'
        playlist=(d/'index.m3u8').read_text()
    finally:
        child.send_signal(signal.SIGINT);child.wait(timeout=10)
    cases=[]
    for i in range(4):
        seg=d/f's{i:09d}.ts';params=['ffmpeg','-v','error','-nostdin','-threads','1','-i',str(seg),'-map','0:v:0','-vf','crop=960:2:480:650','-pix_fmt','gray','-fps_mode','passthrough','-f','rawvideo','pipe:1']
        data=subprocess.check_output(params);assert len(data)%(960*2)==0
        values=[]
        for k in range(0,len(data),1920):
            levels=[data[k+16+32*j] for j in range(30)]
            assert all(v<60 or v>190 for v in levels)
            b=[int(x>=190) for x in levels]
            assert b[:8]==[1,0,1,1,0,1,0,0] and b[-1]==1 and sum(b[8:28])%2==b[-2]
            values.append(sum(v<<j for j,v in enumerate(b[8:28])))
        assert values==list(range(i*50,(i+1)*50)),values[:12]
        cases.append({'segment':seg.name,'images':len(values),'premier_compteur':values[0],'dernier_compteur':values[-1],'sha256_octets_locaux':hashlib.sha256(seg.read_bytes()).hexdigest()})
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps({'origine':'Même commande ffmpeg fixture.py et même module de marquage de la compilation ; exécution locale indépendante des 6 runners','fixture_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'marker_module_sha256':hashlib.sha256((module/'regional_live_source.py').read_bytes()).hexdigest(),'playlist_initiale':'#EXT-X-MEDIA-SEQUENCE:0' in playlist,'cadence':25,'gop':50,'duree_segment_s':2,'mappage_confirme':cases},indent=2,ensure_ascii=False)+'\n')

if opts.match and [r['sha256_octets_locaux'] for r in cases[:2]]!=opts.match:raise SystemExit('Les images ont été décodées mais les segments ne reproduisent pas les octets CI.')
