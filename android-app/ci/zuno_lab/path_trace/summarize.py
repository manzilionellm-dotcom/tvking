"""Associe chaque commande aux octets de sa destination et à ses premiers pixels."""
import argparse
import csv
import json
from pathlib import Path


def summarize(out):
    folder=out/'optical'
    if not (folder/'trials.json').exists(): return
    trials=json.loads((folder/'trials.json').read_text())
    with (folder/'samples.csv').open() as f: samples=list(csv.DictReader(f))
    request_file=out/'source'/'http.jsonl'
    requests=[json.loads(l) for l in request_file.read_text().splitlines() if l.strip()]
    media=[r for r in requests if r['role']=='client_or_setup' and r['status']==200]
    rows=[]
    for i,t in enumerate(trials):
        start=t['dispatch_s'];channel=t['target']
        limit=trials[i+1]['dispatch_s'] if i+1<len(trials) else start+12
        slot=[r for r in media if start<=r['start_s']<limit and r['resource'].startswith('/'+channel+'/')]
        manifest=next((r for r in slot if r['resource'].endswith('.m3u8')),None)
        segment=next((r for r in slot if r['resource'].endswith('.ts')),None)
        observed=[s for s in samples if s['trial']==str(t['number']) and s['channel']==channel]
        first=float(observed[0]['host_after_s']) if observed else None
        def ms(seconds): return round(seconds*1000,3)
        rows.append(dict(trial=t['number'],phase=t['phase'],target=channel,source_requests_in_slot=len(slot),
            key_to_manifest_request_ms=ms(manifest['start_s']-start) if manifest else None,
            manifest_headers_server_ms=ms(manifest['headers_sent_s']-manifest['start_s']) if manifest else None,
            key_to_first_segment_request_ms=ms(segment['start_s']-start) if segment else None,
            first_segment_server_send_ms=ms(segment['end_s']-segment['start_s']) if segment else None,
            segment_bytes_declared=segment['content_length'] if segment else None,
            first_segment_server_finished_to_first_sample_ms=ms(first-segment['end_s']) if segment and first else None,
            key_to_first_target_upper_ms=ms(first-start) if first else None,
            key_to_movement_upper_ms=t.get('movement_upper_ms')))
    if rows:
        with (out/'source'/'phases.csv').open('w',newline='') as f:
            w=csv.DictWriter(f,fieldnames=rows[0]);w.writeheader();w.writerows(rows)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('out',type=Path);summarize(p.parse_args().out)
