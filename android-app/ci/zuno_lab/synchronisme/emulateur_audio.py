"""Flux audio SORTANT de l'AVD jetable du banc. Tampons PCM uniquement en mémoire."""
from pathlib import Path
import os,threading,time
import numpy as np
from sonde import RATE,COUNT,tone

def private_endpoint():
    files=list((Path(os.environ['XDG_RUNTIME_DIR'])/'avd'/'running').glob('pid_*_info.ini'))
    if len(files)!=1 or files[0].stat().st_uid!=os.getuid():raise ValueError('AVD de test unique non prouvé')
    settings={}
    for line in files[0].read_text().splitlines():
        k,sep,v=line.partition('=')
        if sep:settings[k.strip()]=v.strip()
    if settings.get('grpc.port')!=os.environ['ZUNO_EMU_GRPC_PORT'] or not settings.get('grpc.token'):raise ValueError('Endpoint de test non identifié')
    return '127.0.0.1:'+settings['grpc.port'],settings['grpc.token']

class EmulatorAudio:
    def __init__(self):
        self.rows=[];self.worker=None;self.errors=[];self.channel=None;self.call=None;self.received=0
    def start(self):
        import sys
        sys.path.insert(0,os.environ['ZUNO_PROTO'])
        import grpc,emulator_controller_pb2 as pb
        addr,credential=private_endpoint();self.channel=grpc.insecure_channel(addr)
        rpc=self.channel.unary_stream('/android.emulation.control.EmulatorController/streamAudio',request_serializer=pb.AudioFormat.SerializeToString,response_deserializer=pb.AudioPacket.FromString)
        fmt=pb.AudioFormat(samplingRate=RATE,channels=pb.AudioFormat.Mono,format=pb.AudioFormat.AUD_FMT_S16)
        self.call=rpc(fmt,metadata=(('authorization','Bearer '+credential),),timeout=180)
        def consume():
            buf=bytearray();begin=time.monotonic()
            try:
                for packet in self.call:
                    self.received+=1
                    if packet.format.samplingRate not in (0,RATE) or packet.format.channels!=pb.AudioFormat.Mono:
                        self.errors.append('format_inattendu');return
                    buf.extend(packet.audio)
                    while len(buf)>=2*COUNT:
                        seg=bytes(buf[:2*COUNT]);del buf[:2*COUNT]
                        ch,hz,f=tone(np.frombuffer(seg,dtype='<i2'));end=time.monotonic()
                        self.rows.append(dict(read_start=begin,read_end=end,tone=ch,hz=hz,energy_fraction=f));begin=end
            except grpc.RpcError as error:self.errors.append(error.code().name)
        self.worker=threading.Thread(target=consume,daemon=True);self.worker.start()
    def stop(self):
        if self.call:self.call.cancel()
        if self.worker:self.worker.join(timeout=3)
        if self.channel:self.channel.close()
