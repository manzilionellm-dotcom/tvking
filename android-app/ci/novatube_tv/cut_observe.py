"""Observe one independent outage without sending further input to the Android player."""
import json
from pathlib import Path
import sys
import threading
import time

from pilot_observer import frame
from read_display_capture import decode

out = Path(sys.argv[1])
seconds = int(sys.argv[2])
gate = out / 'gate.closed'
adb = ['adb','-s','emulator-5554']
states = {}
samples = []


def motion(a, b):
    if not a or not b or a['channel'] != 'A' or b['channel'] != 'A':
        return False
    # Each numbered 120 second fixture is looped at 25 fps.
    return 0 < (b['frame'] - a['frame']) % 3000 < 1500


def grab():
    t = time.monotonic()
    im, data = frame(adb, out, t)
    ch, n = None, None
    if im is not None:
        im = im.convert('L')
        w,h = im.size
        for top,bottom in ((0,0),(0,24),(0,48),(24,0),(24,24),(48,0),(48,48)):
            vh = min(h-top-bottom, w*9/16)
            vw = vh*16/9
            x, y = (w-vw)/2, top + (h-top-bottom-vh)/2
            cells = [im.getpixel((round(x+vw*(496+32*i)/1920), round(y+vh*650/1080))) for i in range(30)]
            ch,n = decode(cells)
            if ch:
                break
    return {'start':t,'end':time.monotonic(),'channel':ch or None,'frame':n if ch else None}, data


def run_gate():
    start = time.monotonic()
    gate.touch()
    states['closed'] = time.monotonic()
    time.sleep(max(0, states['closed'] + seconds - time.monotonic()))
    gate.unlink()
    states['restored'] = time.monotonic()
    (out/'times.json').write_text(json.dumps({'before_close':start, **states}))


with (out/'screen.jsonl').open('w', buffering=1) as stream:
    def sample():
        row, data = grab()
        print(json.dumps(row), file=stream)
        samples.append(row)
        return row, data

    end = time.monotonic() + 45
    while time.monotonic() < end:
        row, data = sample()
        if len(samples) >= 5 and all(motion(a,b) for a,b in zip(samples[-5:-1],samples[-4:])):
            (out/'before.png').write_bytes(data)
            break
    else:
        raise SystemExit('Mire A en mouvement non confirmée avant la coupure')
    time.sleep(.1)
    controller = threading.Thread(target=run_gate)
    controller.start()
    saved = set()
    first_return = None
    while 'restored' not in states or time.monotonic() < states['restored'] + 120:
        row, data = sample()
        if not data:
            continue
        if 'closed' in states and 'restored' not in states and row['end'] > states['closed'] + seconds*.72 and 'cut' not in saved:
            (out/'during.png').write_bytes(data)
            saved.add('cut')
        if 'restored' in states and row['start'] > states['restored'] and 'restored' not in saved:
            (out/'first-post.png').write_bytes(data)
            saved.add('restored')
        if 'restored' in states and len(samples)>=3 and samples[-3]['start'] >= states['restored']:
            if motion(samples[-3],samples[-2]) and motion(samples[-2],row) and first_return is None:
                first_return = row['end'] - states['restored']
                (out/'two-advances.png').write_bytes(data)
        if first_return is not None and row['end'] >= states['restored']+max(40, first_return+20):
            break
    controller.join()
if data:
    (out/'end-playback.png').write_bytes(data)
closed, restored = states['closed'], states['restored']
cut = [r for r in samples if r['start'] >= closed and r['end'] <= restored]
post = [r for r in samples if r['start'] >= restored]
origin = [json.loads(s) for s in (out/'witness.jsonl').read_text().splitlines() if s]
network = [json.loads(s) for s in (out/'http.jsonl').read_text().splitlines() if s]
wcut = [r for r in origin if closed <= r['start'] <= r['end'] <= restored]
rejected = [r for r in network if closed <= r['time'] <= restored and r['code']==503 and r['role']=='app']
after_ts = [r for r in network if r['time'] >= restored and r['role']=='app' and r['code']==200 and r['path'].startswith('/A/') and r['path'].endswith('.ts') and r['port']==18471]
tail = [r for r in post if r['end'] > post[-1]['end']-10] if post else []
pairs = lambda rows: sum(motion(a,b) for a,b in zip(rows,rows[1:]))
result = {'target_s':seconds, 'route':'10.0.2.2:18471','cut_s':restored-closed,'independent_cut_probes':len(wcut),
          'independent_fully_rejected':sum(r.get('manifest_code')==r.get('segment_code')==503 for r in wcut),
          'independent_origin_valid':sum(r.get('transport_sync',False) for r in wcut),
          'origin_segments':len({r['origin_segment'] for r in wcut if r.get('transport_sync')}),
          'app_503_count':len(rejected),'app_200_media_during_cut':sum(r['role']=='app' and r['port']==18471 and r['code']==200 and r['path'].startswith('/A/') and closed<=r['time']<=restored for r in network),
          'app_first_segment_after_s':min([r['time']-restored for r in after_ts],default=None),
          'cut_screens':len(cut),'cut_motion_pairs':pairs(cut),'restored_observed_s':post[-1]['end']-restored if post else 0,
          'first_two_consecutive_visible_advances_after_s':first_return,
          'post_screens':len(post),'post_target_screens':sum(r['channel']=='A' for r in post),
          'post_tail_motion_pairs':pairs(tail),'post_tail_samples':len(tail)}
(out/'result.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result), flush=True)
if not wcut or not all(r.get('manifest_code')==r.get('segment_code')==503 and r.get('transport_sync') for r in wcut):
    raise SystemExit('Validation du banc de coupure incomplète')
