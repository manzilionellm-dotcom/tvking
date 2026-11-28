"""Lancer le banc dans le namespace réseau privé déjà réduit à lo et sans proxy utilisable."""
import argparse
import os
from pathlib import Path
import socket
import sys
a=argparse.ArgumentParser(description=__doc__)
a.add_argument('command',nargs=argparse.REMAINDER)
args=a.parse_args()
if [line.split(':')[0].strip() for line in Path('/proc/net/dev').read_text().splitlines()[2:]]!=['lo'] or len(Path('/proc/net/route').read_text().splitlines())!=1:
    raise SystemExit('Le banc exige un namespace Linux sans interface de sortie ni route IPv4.')
# Le seul IPv6 accepté est lo local. Les routes de rejet vers :: sont admises.
for row in Path('/proc/net/ipv6_route').read_text().splitlines():
    cols=row.split()
    if cols[-1]!='lo' or (cols[0]=='0'*32 and cols[1]=='00' and not (int(cols[8],16)&0x200)):
        raise SystemExit('Une route IPv6 par défaut demeure.')
env=os.environ.copy()
for k in list(env):
    if 'proxy' in k.lower() and not k.startswith('CODEX_'):
        del env[k]
for key in ('http_proxy','HTTP_PROXY','https_proxy','HTTPS_PROXY','all_proxy','ALL_PROXY'):
    env[key]='http://127.0.0.1:1'
for key in ('no_proxy','NO_PROXY'):
    env[key]='127.0.0.1,localhost,::1'
env.update(FLUTTER_SUPPRESS_ANALYTICS='true',DART_SUPPRESS_ANALYTICS='true',WRANGLER_SEND_METRICS='false',
           npm_config_offline='true',CI='true',DO_NOT_TRACK='1')
os.execvpe(args.command[0],args.command,env)
