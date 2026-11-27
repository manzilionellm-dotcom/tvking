import csv
import subprocess
import time

def recover(out,seconds,channel,screenshot):
    entries=[]
    rule=['OUTPUT','-s','127.0.0.1/32','-o','lo','-p','tcp','--dport','18471','-j','REJECT']
    def sample(label,duration):
        deadline=time.monotonic()+duration
        while time.monotonic()<deadline:
            ch,n,b,e=screenshot()
            entries.append([label,ch,n,b,e])
    sample('before',4)
    subprocess.run(['sudo','iptables','-w','-I']+rule,check=True)
    begin=time.monotonic()
    try:
        sample('cut',seconds)
        with (out/f'cut-{seconds}-counter.txt').open('w') as f:
            subprocess.run(['sudo','iptables','-w','-L','OUTPUT','-n','-v','-x'],stdout=f,check=True)
    finally:
        subprocess.run(['sudo','iptables','-w','-D']+rule,check=True)
    restored=time.monotonic()
    sample('restored',32)
    with (out/f'cut-{seconds}.csv').open('w',newline='') as f:
        w=csv.writer(f);w.writerow(['phase','channel','source_frame','start_from_restore_s','end_from_restore_s'])
        w.writerows((phase,ch,n,b-restored,e-restored) for phase,ch,n,b,e in entries)
    out_rows=[r for r in entries if r[0]=='restored']
    upper=next((q[4]-restored for p,q in zip(out_rows,out_rows[1:]) if p[1]==q[1]==channel and
                0<(q[2]-p[2])%(1<<20)<(1<<19)),None)
    tail=[r for r in entries if r[0]=='cut' and r[1]==channel and r[4]>=restored-2]
    return {'cut_s':seconds,'observed_s':round(restored-begin,3),'motion_in_final_2s_of_cut':len({r[2] for r in tail})>1,
            'motion_after_restoration_upper_s':upper,'post_window_s':32}
