"""Reject packets to the fixture relay on a loopback port. No ADB operation is used."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import threading
import time


class RejectRelay:
    def __init__(self):
        self.tag = 'novatube_fixture_relay_' + str(os.getpid())
        self.rule = ['-o','lo','-d','127.0.0.1/32','-p','tcp','--dport','18472',
                     '-m','comment','--comment',self.tag,'-j','REJECT','--reject-with','tcp-reset']

    def cmd(self, action, check=True):
        commands = {'insert':['-I','OUTPUT','1'], 'remove':['-D','OUTPUT'], 'check':['-C','OUTPUT']}
        return subprocess.run(['sudo','-n','iptables','-w','4'] + commands[action] + self.rule,
                              check=check, capture_output=True, text=True, timeout=9)

    def counters(self):
        s=subprocess.check_output(['sudo','-n','iptables-save','-c','-t','filter'],text=True,timeout=9)
        matches=[line for line in s.splitlines() if self.tag in line.split() or '"'+self.tag+'"' in line.split()]
        if len(matches)!=1:
            raise RuntimeError('Exactly one fixture REJECT rule is required')
        m=re.match(r'^\[(\d+):(\d+)\]\s',matches[0])
        if not m:
            raise RuntimeError('No packet and byte counters on fixture rule')
        return {'rejected_packets':int(m[1]),'rejected_bytes':int(m[2]),'verified_rule':matches[0]}


def schedule(out, firewall, stop, clock=time, offsets=(90,520), hold=180):
    origin=json.loads((out/'observation-start.json').read_text())
    zero=origin['monotonic']
    def wait(target):
        while not stop.is_set():
            left=target-clock.monotonic()
            if left<=0: break
            stop.wait(min(1.,left))
    with (out/'relay-faults.jsonl').open('a',buffering=1) as log:
        def record(phase, **fields):
            t=clock.monotonic()
            log.write(json.dumps({'phase':phase,'host_monotonic':t,'elapsed_s':round(t-zero,3),
                                  'unix':clock.time(),'utc':datetime.fromtimestamp(clock.time(),timezone.utc).isoformat(),
                                  **fields})+'\n')
        record('plan', offsets_s=list(offsets), hold_s=hold, rule=firewall.rule,
               origin_fixture_port=18471, atlas_port=8788)
        for idx,offset in enumerate(offsets,1):
            wait(zero+offset)
            if stop.is_set():break
            pre=firewall.cmd('check',check=False)
            if pre.returncode!=1:
                raise RuntimeError(f'Unexpected pre-existing rule state: {pre.returncode}')
            # Always attempt to restore the exact tagged rule, including after an
            # interrupted or timed-out insert. A previously absent rule has rc 1.
            spans={}
            try:
                started=clock.monotonic()
                firewall.cmd('insert')
                record('inserted',window=idx,**firewall.counters())
                while not stop.is_set() and clock.monotonic()<started+hold:
                    wait(min(started+hold,clock.monotonic()+5))
                    spans=firewall.counters()
                    record('active',window=idx,**spans)
            finally:
                cleanup=firewall.cmd('remove',check=False)
                absent=firewall.cmd('check',check=False)
                record('removed',window=idx,actual_s=round(clock.monotonic()-started,3),
                       remove_rc=cleanup.returncode,check_after_rc=absent.returncode,**spans)
                if cleanup.returncode not in (0,1) or absent.returncode!=1:
                    raise RuntimeError('Fixture rule cleanup could not be verified')
            if not stop.is_set() and not spans.get('rejected_packets'):
                record('no_packets_observed',window=idx)
        record('end',interrupted=stop.is_set())


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('out',type=Path)
    out=p.parse_args().out
    stop=threading.Event()
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    schedule(out,RejectRelay(),stop)


if __name__ == '__main__':
    main()
