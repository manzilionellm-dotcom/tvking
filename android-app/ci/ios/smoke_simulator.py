#!/usr/bin/env python3
"""Vérifie un vrai lancement iOS et conserve une capture non promotionnelle."""
import json
from pathlib import Path
import subprocess
import sys
import time

phone = Path(sys.argv[1]).resolve()
output = phone / 'build'
def call(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)
raw = subprocess.check_output(['xcrun','simctl','list','devices','available','-j'],text=True)
devices = json.loads(raw)['devices']
choices = [(runtime,device) for runtime,items in devices.items() for device in items
           if 'iOS' in runtime and device['name'].startswith('iPhone') and device.get('isAvailable')]
if not choices: raise SystemExit('Aucun simulateur iPhone disponible')
_, device = sorted(choices,key=lambda x:(x[0],x[1]['name']),reverse=True)[0]
udid = device['udid']
try:
    if device['state'] != 'Booted': call('xcrun','simctl','boot',udid)
    call('xcrun','simctl','bootstatus',udid,'-b',timeout=180)
    call('xcrun','simctl','install',udid,str(output/'ios/iphonesimulator/Runner.app'))
    launched=call('xcrun','simctl','launch',udid,'com.manzilionellm.sevenmotion',capture_output=True)
    (output/'iphone-simulator.log').write_text(launched.stdout+launched.stderr)
    # Premier chargement local ; aucun identifiant IPTV injecté dans le test.
    time.sleep(15)
    call('xcrun','simctl','io',udid,'screenshot',str(output/'iphone-simulator.png'))
    running=subprocess.check_output(['xcrun','simctl','spawn',udid,'launchctl','list'],text=True)
    if 'com.manzilionellm.sevenmotion' not in running:
        raise SystemExit('Le processus iPhone ne tourne plus après le lancement')
    print('Lancement iPhone vérifié ; lecture réseau et matériel restent à tester sur appareil.')
finally:
    subprocess.run(['xcrun','simctl','shutdown',udid],check=False,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
