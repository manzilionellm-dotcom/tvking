"""Align each decoded video frame on true Android elapsedRealtime using both Winscope tracks."""
import json
from pathlib import Path
import struct
import subprocess

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


