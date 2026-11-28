"""Caracteriser le flux exemple Apple deja retenu dans les six villes."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urljoin

MASTER = 'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8'


def now():
    return datetime.now(timezone.utc).isoformat()


def fetch(url, dest, role, trial):
    started = now()
    proc = subprocess.run(['curl', '--silent', '--show-error', '--location', '--max-time', '25', '--output', str(dest), '--write-out', '%{http_code} %{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total} %{size_download}', url], capture_output=True, text=True)
    fields = proc.stdout.split()
    row = dict(utc=started, trial=trial, role=role, url=url, curl_code=proc.returncode)
    if len(fields) == 7:
        http, *times, size = fields
        row.update(http=int(http), size_bytes=int(size), **{k:round(1000*float(v),3) for k,v in zip(('dns_ms','tcp_ms','tls_ms','ttfb_ms','total_ms'), times)})
    if dest.exists():
        row['sha256'] = hashlib.sha256(dest.read_bytes()).hexdigest()
    return row


def media_info(path):
    args = ['ffprobe','-v','error','-show_entries','stream=codec_type,codec_name,width,height,avg_frame_rate,sample_rate,channels:format=format_name,duration,bit_rate','-of','json',str(path)]
    return json.loads(subprocess.check_output(args, text=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=True)
    rows, detail, ladder = [], {}, []
    with tempfile.TemporaryDirectory() as temp:
        output = Path(temp)
        for trial in range(1, 6):
            master = output/'master'
            rows.append(fetch(MASTER, master, 'master', trial))
            if rows[-1].get('http') != 200 or not rows[-1].get('size_bytes'):
                continue
            lines = master.read_text().splitlines()
            if not ladder:
                for i,line in enumerate(lines):
                    if not line.startswith('#EXT-X-STREAM-INF:'):
                        continue
                    attrs = {k:v.strip('"') for k,v in re.findall(r'([A-Z-]+)=("[^"]*"|[^,]+)', line)}
                    ladder.append(dict(path=lines[i+1],**attrs))
            audio = next(re.search(r'URI="([^"]+)"', x).group(1) for x in lines if x.startswith('#EXT-X-MEDIA:') and 'TYPE=AUDIO' in x and 'DEFAULT=YES' in x)
            for stream, rel in [('video','v2/prog_index.m3u8'), ('audio',audio)]:
                playlist = urljoin(MASTER, rel)
                dest = output/(stream+'.m3u8')
                rows.append(fetch(playlist, dest, stream+'_manifest', trial))
                if rows[-1].get('http') != 200 or not rows[-1].get('size_bytes'):
                    continue
                playlist_lines = dest.read_text().splitlines()
                i = next(i for i, line in enumerate(playlist_lines) if line.startswith('#EXTINF:'))
                duration = float(playlist_lines[i].split(':',1)[1].split(',')[0])
                first = next(v for v in playlist_lines[i+1:] if v and not v.startswith('#'))
                segment = output/(stream+'.sample'); rows.append(fetch(urljoin(playlist, first),segment,stream+'_segment',trial))
                row = rows[-1]
                if row.get('http') != 200 or not row.get('size_bytes'):
                    continue
                row['duration_advertised_s'] = duration
                row['media_rate_bit_s'] = round(8*row['size_bytes']/duration)
                row['transport_rate_bit_s'] = round(8000*row['size_bytes']/row['total_ms']) if row['total_ms'] else None
                if stream not in detail:
                    detail[stream] = dict(ffprobe=media_info(segment), vod_endlist='#EXT-X-ENDLIST' in playlist_lines)
    cols = list(dict.fromkeys(k for row in rows for k in row))
    with (args.destination/'mesures.csv').open('w',newline='') as fd:
        writer = csv.DictWriter(fd,fieldnames=cols); writer.writeheader(); writer.writerows(rows)
    result = dict(source=MASTER,region=None,scope='HTTPS depuis le poste de qualification via son acces configure. Aucune application Android et aucune source client.',ladder=ladder,segments=detail,requests=len(rows),nonempty_http_200=sum(r.get('http')==200 and bool(r.get('size_bytes')) for r in rows))
    (args.destination/'source.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')


if __name__=='__main__':
    main()
