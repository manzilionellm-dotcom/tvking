"""Align each decoded video frame on true Android elapsedRealtime using both Winscope tracks."""
import argparse
import collections
import csv
import json
import math
from pathlib import Path
import statistics
import struct
import subprocess
import sys

# Même bande de 30 cellules que les mires de regional_live_source.py.
def decode(row):
    if len(row)!=30 or any(60<x<190 for x in row): return '', ''
    bits=[int(x>=190) for x in row]
    if bits[:7]!=[1,0,1,1,0,1,0] or bits[-1]!=1: return '', ''
    counter=bits[8:28]
    if sum(counter)%2!=bits[-2]: return '', ''
    return ('B' if bits[7] else 'A'),sum(v << i for i,v in enumerate(counter))

V1=b'#VV1NSC0PET1ME!#'
V2=b'#VV1NSC0PET1ME2#'


def ffprobe(mp4, *args):
    out=subprocess.check_output(['ffprobe','-v','error',*args,'-of','json',str(mp4)])
    return json.loads(out)


def winscope(mp4):
    streams=ffprobe(mp4,'-show_entries','stream=index,codec_type,codec_tag_string,width,height')['streams']
    seq={s['index'] for s in streams if s['codec_type']=='data' and s['codec_tag_string']=='mett'}
    if len(seq)!=2: raise ValueError('Expected two independently identifiable mett metadata tracks')
    data=mp4.read_bytes()
    def boxes(begin,end):
        while begin < end:
            size,kind=struct.unpack_from('>I4s',data,begin)
            hdr=8
            if size==1:
                size=struct.unpack_from('>Q',data,begin+8)[0];hdr=16
            if size==0: size=end-begin
            if not hdr<=size<=end-begin: raise ValueError('Invalid MP4 atom')
            yield kind,begin+hdr,begin+size
            begin+=size
    def child(parent,name):
        return next((a,b) for k,a,b in boxes(*parent) if k==name)
    top=(0,len(data))
    mdat=[(a,b) for k,a,b in boxes(*top) if k==b'mdat']
    tracks=[(a,b) for k,a,b in boxes(*child(top,b'moov')) if k==b'trak']
    buffers=[]
    for trak in tracks:
        table=child(child(child(trak,b'mdia'),b'minf'),b'stbl')
        stsd=child(table,b'stsd')[0]
        desc=next(boxes(stsd+8,child(table,b'stsd')[1]))[0]
        if desc!=b'mett': continue
        stsz=child(table,b'stsz')[0]
        fixed,n=struct.unpack_from('>II',data,stsz+4)
        if n!=1: raise ValueError('Expected one sample on each metadata track')
        size=fixed or struct.unpack_from('>I',data,stsz+12)[0]
        offkind,off,_=next((k,a,b) for k,a,b in boxes(*table) if k in (b'stco',b'co64'))
        if struct.unpack_from('>I',data,off+4)[0]!=1: raise ValueError('Multiple chunks on metadata track')
        pos=struct.unpack_from('>I' if offkind==b'stco' else '>Q',data,off+8)[0]
        if not any(a<=pos and pos+size<=b for a,b in mdat): raise ValueError('Bad metadata sample offset')
        buffers.append(data[pos:pos+size])
    if len(buffers)!=2: raise ValueError('Invalid mux metadata tracks')
    legacy,current=None,None
    for buf in buffers:
        if buf.startswith(V1):
                n=struct.unpack_from('<I',buf,16)[0]
                assert len(buf)==20+n*8
                legacy=[v[0]/1e6 for v in struct.iter_unpack('<Q',buf[20:])]
        if buf.startswith(V2):
                version,offset,n=struct.unpack_from('<IQI',buf,16)
                assert version==2 and len(buf)==32+n*8
                current=[v[0]/1e9 for v in struct.iter_unpack('<Q',buf[32:])]
    assert legacy and current and len(legacy)==len(current)
    mdiff=max(abs(a-b) for a,b in zip(legacy,current))
    if mdiff>0.005: raise ValueError('Disagreement between independent elapsedRealtime tracks')
    frames=ffprobe(mp4,'-select_streams','v:0','-show_frames','-show_entries','frame=best_effort_timestamp_time')['frames']
    pts=[float(f['best_effort_timestamp_time']) for f in frames]
    if len(pts)!=len(current): raise ValueError('Video/metadata frame count mismatch')
    if any(b<=a for a,b in zip(current,current[1:])): raise ValueError('Non-monotonic video clock')
    pdiff=max(abs((p-pts[0])-(t-current[0])) for p,t in zip(pts,current))
    if pdiff>0.002: raise ValueError('Video presentation times disagree with timings from metadata')
    return current,{'frames':len(pts),'v1_v2_max_diff_ms':mdiff*1000,'pts_max_diff_ms':pdiff*1000,
                    'duration_s':current[-1]-current[0]}


def marker_values(mp4):
    w,h=320,180
    positions=[]
    for t,b in ((0,0),(0,24),(0,48),(24,0),(24,24),(48,0),(48,48)):
        top=t*h/1080; bottom=b*h/1080
        vh=min(h-top-bottom,w*9/16)
        vw=vh*16/9;x=(w-vw)/2;y=top+(h-top-bottom-vh)/2
        positions.append([round(y+vh*650/1080)*w+round(x+vw*(496+32*i)/1920) for i in range(30)])
    proc=subprocess.Popen(['ffmpeg','-nostdin','-v','error','-i',str(mp4),'-map','0:v:0',
           '-vf','scale=320:180:flags=area,format=gray','-fps_mode','passthrough','-enc_time_base','1:1000000','-threads','1',
           '-f','rawvideo','-'],stdout=subprocess.PIPE)
    rows=[]
    while buf:=proc.stdout.read(w*h):
        if len(buf)!=w*h: raise ValueError('Truncated ffmpeg decoded frame')
        coded=[decode([buf[idx] for idx in pos]) for pos in positions]
        rows.append(coded)
    if proc.wait()!=0: raise ValueError('FFmpeg decode did not finish')
    score=[sum(bool(r[i][0]) for r in rows) for i in range(len(positions))]
    choice=max(range(len(score)),key=score.__getitem__)
    return [r[choice] for r in rows],{'geometry_index':choice,'decodable_frames':score[choice]}


def percentile(v,p):
    return sorted(v)[math.ceil(len(v)*p/100)-1] if v else None


def analyse(mp4, events=None):
    ts,proof=winscope(mp4)
    obs,quality=marker_values(mp4)
    if len(obs)!=len(ts): raise ValueError('Decoded pixel count mismatches Winscope track')
    gaps=[1000*(b-a) for a,b in zip(ts,ts[1:])]
    res={'clock':proof,**quality,'cadence_ms':{'p50':percentile(gaps,50),'p95':percentile(gaps,95),
                    'max':max(gaps)},'trials':[]}
    if events is None: return res,ts,obs
    keys=[row.split() for row in events.read_text().splitlines() if row.strip()]
    if len(keys)!=10: raise ValueError('Wrong number of key events')
    for j,(sid,target,key,begin,end) in enumerate(keys):
        begin,end=float(begin),float(end)
        next_begin=float(keys[j+1][3]) if j+1<len(keys) else ts[-1]+0.000001
        # uptime is truncated to a centisecond. Actual dispatch is between begin and end+10ms.
        item={'n':int(sid),'target':target,'key_before':begin,'key_after_plus_10ms':end+0.010}
        res['trials'].append(item)
        old='A' if target=='B' else 'B'
        prior=[(t,ch,n) for t,(ch,n) in zip(ts,obs) if begin-1.5<t<=begin and ch]
        if len(prior)<2 or prior[-1][1]!=old or not any(a[1]==b[1]==old and 0 < (b[2]-a[2])%(1<<20)<(1<<19) for a,b in zip(prior,prior[1:])):
            item['valid']=False;item['reason']='starting channel not confirmed in motion';continue
        if not begin<next_begin or end<begin or next_begin>end+15 or ts[-1]<=end or ts[0]>=begin:
            item['valid']=False;item['reason']='input window outside continuous capture';continue
        indices=[i for i,t in enumerate(ts) if begin<=t<next_begin]
        last=None;first=None;motion=None
        for i in indices:
            ch,n=obs[i]
            if ch==target:
                if first is None:first=i
                if last is not None and 0 < (n-last)%(1<<20)<(1<<19):motion=i;break
                last=n
            else:
                last=None
        if motion is None:
            item['valid']=False;item['reason']='no two advancing target markers';continue
        item.update(valid=True,input_window_ms=(end+0.010-begin)*1000,
                    first_lo_s=max(0,ts[first]-end-.010),first_hi_s=ts[first]-begin,
                    motion_lo_s=max(0,ts[motion]-end-.010),motion_hi_s=ts[motion]-begin,
                    first_index=first,motion_index=motion,
                    near_first_gap_ms=(ts[first]-ts[first-1])*1000,
                    near_motion_gap_ms=(ts[motion]-ts[motion-1])*1000)
    return res,ts,obs


if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('mp4',type=Path)
    p.add_argument('--keys', type=Path)
    p.add_argument('--output',type=Path)
    args=p.parse_args()
    res,ts,obs=analyse(args.mp4,args.keys)
    print(json.dumps({k:v for k,v in res.items() if k!='trials'},indent=2))
    if args.output:
        args.output.write_text(json.dumps(res,indent=2))
        with args.output.with_suffix('.csv').open('w') as file:
            csvout=csv.writer(file);csvout.writerow(('frame','elapsed_s','channel','counter'))
            csvout.writerows((i,t,*v) for i,(t,v) in enumerate(zip(ts,obs)))
