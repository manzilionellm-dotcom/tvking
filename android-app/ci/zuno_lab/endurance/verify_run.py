"""Évite de déclarer verte une capture incomplète ou sans vidéo saine."""
import json
import sys
from pathlib import Path

def validate(out,route,scenario,duration):
    def rows(name):
        return [json.loads(s) for s in (out/name).read_text().splitlines()]
    reports=rows('observations.jsonl'); http=rows('http.jsonl'); canaries=rows('canary.jsonl')
    facts=json.loads((out/'summary.json').read_text())
    timed=[r for r in reports if r['relative_s'] is not None]
    target_host='direct' if route=='direct' else 'loopback'
    segments=[r for r in http if r['role']=='media' and r['path'].endswith('.ts')]
    distinct={s['name'] for r in canaries for s in r.get('segments',[])}
    good=[r for r in timed if r['ch']=='A']
    checks={
        'observed_duration':facts['timed'] and facts['wall_observed_after_motion_s']>=duration,
        'started_on_confirmed_movement':bool(timed),
        'media_over_selected_route':len(segments)>1 and all(r['host_role']==target_host for r in segments),
        'fresh_canary':len(distinct)>=max(2,duration//18) and all(r.get('segments') for r in canaries),
        'known_channel_at_least_98_percent':bool(timed) and len(good)/len(timed)>=.98,
        'no_capture_gap_over_2_5s':facts['gaps_over_2_5_s']==0,
        'no_recorded_freeze_or_interruption':facts['first_incident'] is None,
        'fault_injected_only_when_requested':any(r['http']==503 for r in segments)==(scenario=='degraded'),
    }
    (out/'criteria.json').write_text(json.dumps(checks,indent=2))
    return all(checks.values())
if __name__=='__main__':
    if not validate(Path(sys.argv[1]),sys.argv[2],sys.argv[3],int(sys.argv[4])): sys.exit(1)
