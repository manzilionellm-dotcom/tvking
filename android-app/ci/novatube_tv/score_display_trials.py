"""Mesure les essais à partir de la sortie de read_display_capture.py.

Événements CSV : id,kind,start_s,end_s,channel. 'zap' démarre à l'appui et
'recovery_5', 'recovery_15', 'recovery_60' au rétablissement réseau mesuré.
end_s est l'échéance fixée avant l'essai ; channel est A ou B. 'play' délimite
la séquence continue utilisée pour compter les images source non affichées
et dater la plus longue répétition d’une image reconnue.
Une capture muette, mal cadrée ou sous-échantillonnée doit être rejetée avant
le classement. Comparer uniquement des acquisitions calibrées sur le même banc.
"""
import argparse
from bisect import bisect_left
import csv
import json
import math
import statistics
from pathlib import Path

from regional_live_source import COUNTER_BITS


def measure(events_path, frames_path):
    with frames_path.open() as f:
        frames = list(csv.DictReader(f))
    times = [float(frame['capture_pts_s']) for frame in frames]
    if (len(times) < 2 or not all(math.isfinite(t) for t in times)
            or any(b <= a for a, b in zip(times, times[1:]))):
        raise ValueError('Les PTS doivent être strictement croissants.')
    intervals = [b - a for a, b in zip(times, times[1:])]
    typical_interval = statistics.median(intervals)
    # Un fichier de capture à 20 Hz ne peut pas observer les 25 images/s de la mire.
    if typical_interval > 1 / 25 + 0.0005:
        raise ValueError('Cadence de capture insuffisante pour la mire à 25 Hz.')
    with events_path.open() as f:
        events = list(csv.DictReader(f))
    if len({e['id'] for e in events}) != len(events) or not events:
        raise ValueError('Les essais doivent être identifiés individuellement.')

    outcomes = []
    counter_size = 1 << COUNTER_BITS
    for event in events:
        channel, kind = event['channel'], event['kind']
        if kind not in ('zap', 'recovery_5', 'recovery_15', 'recovery_60', 'play') or channel not in ('A', 'B'):
            raise ValueError(f"Événement inconnu : {event['id']}")
        begin, end = float(event['start_s']), float(event['end_s'])
        if not (times[0] <= begin < end <= times[-1] + typical_interval + 1e-6):
            raise ValueError('La capture doit couvrir toute la fenêtre annoncée.')
        start, stop = bisect_left(times, begin), bisect_left(times, end)
        if stop <= start:
            raise ValueError('Fenêtre sans image acquise.')
        unknown = 0
        missing = 0
        previous = None
        first_moving = None
        coverage_gaps = 0
        same_frame_since = None
        longest_hold = None
        for i in range(start, stop):
            f = frames[i]
            if i > start and times[i] - times[i-1] > typical_interval * 1.5 + 0.001:
                coverage_gaps += 1
                previous = None
            if f['status'] != 'ok' or f['channel'] != channel:
                unknown += 1
                previous = None
                continue
            now = int(f['source_frame'])
            if kind == 'play':
                # Une lacune, une image illisible ou un changement de chaîne rompt
                # la série. Un intervalle entre deux numéros égaux ne compte que
                # si toutes les captures intermédiaires ont reconnu ce numéro.
                if previous != now:
                    same_frame_since = times[i]
                else:
                    duration = times[i] - same_frame_since
                    if longest_hold is None or duration > longest_hold['duration_s']:
                        longest_hold = {
                            'source_frame': now,
                            'start_capture_pts_s': same_frame_since,
                            'end_capture_pts_s': times[i],
                            'duration_s': duration,
                        }
            if previous is not None and previous != now:
                jump = (now - previous) % counter_size
                # Une source qui revient en arrière sans boucler est une rupture :
                # ses trames ne constituent pas une perte mesurable.
                if jump > counter_size // 2:
                    unknown += 1
                    previous = None
                    continue
                if first_moving is None:
                    first_moving = times[i] - begin
                missing += jump - 1
            previous = now
        result = {'id': event['id'], 'kind': kind, 'channel': channel, 'window_s': end - begin,
                  'unidentified_or_other_channel_frames': unknown, 'capture_gaps': coverage_gaps}
        if kind == 'play':
            result['missing_source_frames_in_contiguous_valid_intervals'] = missing
            result['complete_visual_coverage'] = not unknown and not coverage_gaps
            # Borne basse : l'écran a pu se figer avant la première observation
            # ou rester figé après la dernière, notamment en fin d'acquisition.
            result['longest_observed_frame_hold'] = longest_hold
        else:
            result['motion_confirmed_s'] = first_moving
            result['outcome'] = 'timeout' if first_moving is None else 'ok'
        outcomes.append(result)
    stats = {}
    for kind in sorted({r['kind'] for r in outcomes} - {'play'}):
        batch = [r for r in outcomes if r['kind'] == kind]
        successful = sorted(r['motion_confirmed_s'] for r in batch if r['outcome'] == 'ok')
        rank = math.ceil(.95 * len(batch))
        admissible = all(row['capture_gaps'] == 0 for row in batch)
        stats[kind] = {'attempts': len(batch), 'failures': len(batch) - len(successful),
                       'capture_continuous': admissible,
                       'p95_over_all_attempts_s': (
                           successful[rank - 1] if admissible and rank <= len(successful) else None
                       )}
    return {'observed': outcomes, 'summary': stats}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('events', type=Path)
    parser.add_argument('frames', type=Path)
    args = parser.parse_args()
    print(json.dumps(measure(args.events, args.frames), indent=2, allow_nan=False))
