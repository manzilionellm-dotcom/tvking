"""Contrat réel du Worker du dépôt, D1 locale. La partie Android se trouve dans le test Dart séparé."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
from urllib.request import Request,urlopen


def run(source,dependencies,out):
    secret=secrets.token_urlsafe(40)
    appsecret=secrets.token_urlsafe(40)
    mac='MK:'+':'.join(f'{n:02X}' for n in range(42,47))
    token=None
    def fetch(method,path,body=None,panel=False,box=False):
        headers={'Content-Type':'application/json'}
        if panel: headers['Authorization']='Bearer '+token
        if box: headers['X-Device-Secret']=appsecret
        req=Request('http://127.0.0.1:18787'+path,data=json.dumps(body).encode() if body is not None else None,
                    method=method,headers=headers)
        with urlopen(req,timeout=8) as r: return json.load(r)
    with tempfile.TemporaryDirectory() as tmp:
        ready=Path(tmp)/'ready.json'
        node=subprocess.Popen(['node',str(Path(__file__).with_name('local-worker.mjs')),str(source),str(dependencies),str(ready)],
                              env={**os.environ,'ZUNO_QA_PASS':secret})
        results=[]
        try:
            for _ in range(160):
                if ready.exists():break
                if node.poll() is not None:raise RuntimeError('Worker arrêté.')
                time.sleep(.1)
            token=fetch('POST','/api/v1/auth/login',{'email':'admin','password':secret})['token']
            fetch('GET','/api/status/'+mac)
            fetch('POST','/api/v1/activate',{'mac':mac,'plan':'lifetime'},panel=True)
            fetch('POST','/api/device-proof',{'mac':mac,'androidId':'','secret':appsecret})
            cursor=0
            for size in (5000,20000):
                m3u=f'http://127.0.0.1:18471/channels.m3u?n={size}'
                response=fetch('PUT','/api/v1/sources/'+mac,{'sources':[{'type':'m3u','m3u_url':m3u,'label':f'LAB {size}'}]},panel=True)
                delivered=fetch('GET','/api/device-source/'+mac,box=True)
                assert delivered['sources'][0]['m3u_url']==m3u and 'source_rev' in delivered
                def pending():
                    return fetch('GET',f'/api/box/wait/{mac}?after={cursor}&timeout=200',box=True)['box']
                order=[o for o in pending() if o['kind']=='source'][-1]
                replay=[o for o in pending() if o['kind']=='source'][-1]
                assert replay['id']==order['id']
                structured=fetch('POST','/api/box/ack/'+mac,{'orders':[{'order_id':str(order['id']),'state':'applied','config_rev':delivered['source_rev']}]},box=True)
                remains=any(o['id']==order['id'] for o in pending())
                ack=fetch('POST','/api/box/ack/'+mac,{'box':[order['id']],'fleet':[]},box=True)
                repeat=fetch('POST','/api/box/ack/'+mac,{'box':[order['id']],'fleet':[]},box=True)
                assert remains and structured.get('applied_at') is None and ack['applied_at']==repeat['applied_at'] and repeat['already']
                results.append(dict(size=size,resources_in_payload=response.get('count'),revision=delivered['source_rev'],configRev_aliases_present=[k for k in ('rev','updated_at') if k in delivered],
                               signal_id=order['id'],signal_fields=sorted(order),same_after_replay=True,structured_http_200=structured,
                               remained_pending_after_structured=remains,numeric_first=ack,numeric_duplicate=repeat))
                cursor=order['id']
            proof={'scope':'Worker de la révision 119 sous workerd et D1 locale. Client HTTP du banc, aucun APK, aucun écran.',
                   'worker':json.loads(ready.read_text()),'campaign':results}
            with out.open('x') as f:json.dump(proof,f,indent=2)
        finally:node.terminate();node.wait(timeout=10)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('cloudflare_source',type=Path);p.add_argument('cloudflare_with_node_modules',type=Path);p.add_argument('out',type=Path)
    a=p.parse_args();run(a.cloudflare_source,a.cloudflare_with_node_modules,a.out)
