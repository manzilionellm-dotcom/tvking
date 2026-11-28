"""Aucune forme d'onde stockée. Deux tons de synthèse, une sortie Pulse dédiée."""
import json,math,os,subprocess,threading,time
import numpy as np
RATE=48000
COUNT=4800

def tone(samples):
    signal=np.asarray(samples,dtype='float64')/32768
    signal-=signal.mean()
    rms=float(np.sqrt(np.mean(signal**2)))
    if rms<.0004:return None,None,0
    fft=np.abs(np.fft.rfft(signal*np.hanning(len(signal))))**2
    energy=float(fft.sum());strength=[]
    for f in (440,660):
        i=round(f*len(signal)/RATE);strength.append(float(fft[i-1:i+2].sum()/energy))
    which=int(strength[1]>strength[0]);peak=int(np.argmax(fft))
    hz=peak*RATE/len(signal)
    match=strength[which]>.93 and strength[1-which]<.015 and abs(hz-(440,660)[which])<8
    return (('A','B')[which],hz,round(strength[which],3)) if match else (None,None,0)

def owners():
    query=lambda obj:json.loads(subprocess.check_output(['pactl','-f','json','list',obj],timeout=4))
    sinks=query('sinks');ids={int(s['index']) for s in sinks if s['name']=='zuno'}
    entries=[r for r in query('sink-inputs') if int(r['sink']) in ids]
    # Accepter uniquement les processus du binaire de cet émulateur isolé.
    ok=[]
    for r in entries:
        properties=r.get('properties',{});pid=str(properties.get('application.process.id',''))
        name=properties.get('application.process.binary','')
        exe=os.path.basename(os.path.realpath('/proc/'+pid+'/exe')) if pid.isdigit() else ''
        approved=any(n.startswith(('qemu-system-','emulator64-','emulator-headless')) or n=='emulator' for n in (exe,name))
        ok.append(bool(approved and pid.isdigit()))
    return bool(entries) and all(ok),len(entries)

class PulseProbe:
    def __init__(self):
        self.rows=[];self.errors=[];self.worker=None;self.proc=None
    def start(self):
        self.proc=subprocess.Popen(['parec','--device=zuno.monitor','--raw','--rate=48000','--channels=1','--format=s16le',
            '--latency-msec=20','--process-time-msec=20'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
        def read():
            while True:
                t0=time.monotonic();buf=self.proc.stdout.read(2*COUNT);t1=time.monotonic()
                if len(buf)!=2*COUNT:return
                ch,hz,power=tone(np.frombuffer(buf,dtype='<i2'))
                self.rows.append(dict(read_start=t0,read_end=t1,tone=ch,hz=hz,energy_fraction=power))
        self.worker=threading.Thread(target=read,daemon=True);self.worker.start()
    def stop(self):
        if self.proc:
            self.proc.terminate();self.proc.wait(timeout=4);self.worker.join(timeout=2)
