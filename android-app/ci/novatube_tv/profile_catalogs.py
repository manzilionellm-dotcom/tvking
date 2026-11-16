"""Mesures Android 11 sur le panel de test en boucle locale. Un seul appareil."""
import contextlib
import http.server
import json
from pathlib import Path
import ssl
import statistics
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

SERIAL, PKG, COMPONENT, OUTPUT, FIXTURE, MEDIA, TLS = sys.argv[1:]
out = Path(OUTPUT)
out.mkdir(parents=True, exist_ok=True)
cfg = json.loads(Path(FIXTURE).read_text())
base = cfg['url']
if urllib.parse.urlsplit(base).hostname != '127.0.0.1':
    raise SystemExit('Le panel doit être le serveur local du test.')


def adb(*args):
    return subprocess.check_output(['adb', '-s', SERIAL, *args], text=True, timeout=55)


def requete(method, path, body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(base + path, method=method, headers=headers,
                                 data=None if body is None else json.dumps(body).encode())
    with urllib.request.urlopen(req, timeout=12) as response:
        return json.load(response)


def donnees(taille, https):
    port = 9443 if https else 9080
    origine = f'{"https" if https else "http"}://127.0.0.1:{port}'
    lignes = ['#EXTM3U']
    for i in range(taille):
        lignes.extend([f'#EXTINF:-1 tvg-id="m{i}" tvg-logo="{origine}/logo/{i % 240}.png" '
                       f'group-title="Groupe {i % 40}",Canal {i + 1}',
                       'http://127.0.0.1:8080/live/mire1/index.m3u8'])
    return ('\n'.join(lignes) + '\n').encode()


catalogues = {(tls, n): donnees(n, tls) for tls in (False, True) for n in (5000, 20000)}
requests = {}
logo = (Path(MEDIA) / 'logos' / 'mire1.png').read_bytes()


class Listes(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/logo/'):
            data = logo
            mime = 'image/png'
        else:
            tls = self.server.server_port == 9443
            size = {'/5000.m3u': 5000, '/20000.m3u': 20000}.get(self.path)
            if size is None:
                self.send_error(404)
                return
            data = catalogues[tls, size]
            requests[tls, size] = requests.get((tls, size), 0) + 1
            mime = 'application/x-mpegurl'
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        with contextlib.suppress(BrokenPipeError, ConnectionResetError):
            self.wfile.write(data)

    def log_message(self, *args):
        pass


def frames(label):
    data = adb('shell', 'dumpsys', 'gfxinfo', PKG, 'framestats')
    (out / (label + '-framestats.txt')).write_text(data)
    durations = []
    for block in data.split('---PROFILEDATA---')[1::2]:
        rows = iter(line.split(',') for line in block.strip().splitlines())
        header = next(rows, [])
        if 'FrameCompleted' not in header or 'IntendedVsync' not in header:
            continue
        for row in rows:
            if len(row) < len(header) - 1 or row[0] != '0':
                continue
            ms = (int(row[header.index('FrameCompleted')]) -
                  int(row[header.index('IntendedVsync')])) / 1000000
            if 0 < ms < 2 ** 40:
                durations.append(ms)
    return {'images_hwui': len(durations), 'plus_16_ms': sum(n > 16 for n in durations),
            'plus_700_ms': sum(n > 700 for n in durations),
            'maximum_ms': max(durations, default=None)}


def mk(stat):
    devices = requete('GET', '/api/v1/devices', token=stat)['items']
    if not devices:
        return None
    if len(devices) != 1:
        raise RuntimeError('Plusieurs box sur le panel de la mesure.')
    value = devices[0]['mac']
    return urllib.parse.quote(value, safe='')


def confirme(endpoint, token, rev):
    status = requete('GET', endpoint + '/revisions', token=token)
    return any(item['rev'] == rev and item['state'] == 'acknowledged' for item in status['revisions'])


with contextlib.ExitStack() as stack:
    fixture_dir = Path(TLS)
    cert = fixture_dir / 'server.pem'
    key = fixture_dir / 'server.key'
    for use_tls, port in ((False, 9080), (True, 9443)):
        server = http.server.ThreadingHTTPServer(('127.0.0.1', port), Listes)
        if use_tls:
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ctx.load_cert_chain(cert, key)
            server.socket = ctx.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        stack.callback(server.server_close)
        stack.callback(server.shutdown)
        adb('reverse', f'tcp:{port}', f'tcp:{port}')
    cold = []
    for essai in range(1, 6):
        adb('shell', 'am', 'force-stop', PKG)
        result = adb('shell', 'am', 'start', '-W', '-n', COMPONENT)
        (out / f'demarrage-profil-{essai}.txt').write_text(result)
        tags = dict(line.split(': ', 1) for line in result.splitlines() if ': ' in line)
        if tags.get('Status') != 'ok' or tags.get('LaunchState') != 'COLD':
            raise RuntimeError('Le démarrage à froid Android n’est pas confirmé.')
        cold.append(int(tags['TotalTime']))
        time.sleep(3)
    print('Démarrage profil médian (ms)', statistics.median(cold), flush=True)
    token = requete('POST', '/api/v1/auth/login', {'email': 'admin', 'password': cfg['adminSecret']})['token']
    for _ in range(30):
        mac = mk(token)
        if mac:
            break
        time.sleep(1)
    if not mac:
        raise RuntimeError('Aucune box de test enregistrée.')
    endpoint = '/api/v1/sources/' + mac
    measures = {'demarrage_ms': cold, 'mediane_ms': statistics.median(cold), 'catalogues': {}}
    for rev, (tls, n) in enumerate(catalogues, 1):
        protocol = 'https' if tls else 'http'
        label = f'{protocol}-{n}'
        url = f'{protocol}://127.0.0.1:{9443 if tls else 9080}/{n}.m3u'
        adb('shell', 'dumpsys', 'gfxinfo', PKG, 'reset')
        start = time.monotonic()
        requete('PUT', endpoint, {'sources': [{'type': 'm3u', 'label': label,
                                               'm3u_url': url}]}, token)
        while not confirme(endpoint, token, rev):
            if time.monotonic() - start > 100:
                raise RuntimeError('Pas de confirmation pour ' + label)
            time.sleep(.12)
        if requests.get((tls, n), 0) < 1:
            raise RuntimeError('Aucune requête du profil Android pour ' + label)
        mesure = {'panel_confirmation_ms': round((time.monotonic()-start)*1000),
                  'requetes': requests[tls, n], 'import': frames(label + '-import')}
        # L'accueil après l'import affiche Direct au focus initial. Le parcours
        # média qui précède vérifie visuellement ce même composant.
        adb('shell', 'input', 'keyevent', 'KEYCODE_DPAD_CENTER')
        time.sleep(3)
        with (out / (label + '-direct.png')).open('wb') as screen:
            subprocess.run(['adb', '-s', SERIAL, 'exec-out', 'screencap', '-p'],
                           stdout=screen, check=True)
        subprocess.run(['python3', str(Path(__file__).with_name('screen_label.py')),
                        str(out / (label + '-direct.png')), 'canal|groupe', '0','1'],check=True)
        for colonne, touch in [('chaines',None),('categories','KEYCODE_DPAD_LEFT')]:
            if touch:
                adb('shell', 'input', 'keyevent', touch)
            adb('shell', 'dumpsys', 'gfxinfo', PKG, 'reset')
            adb('shell', 'for i in $(seq 1 35); do input keyevent KEYCODE_DPAD_DOWN; done')
            mesure[colonne] = frames(label + '-' + colonne)
        (out / (label + '-memoire.txt')).write_text(adb('shell','dumpsys','meminfo',PKG))
        adb('shell','input','keyevent','KEYCODE_BACK')
        time.sleep(1)
        # Rétablit le focus de départ sur l'accueil avant la prochaine liste.
        adb('shell','am','force-stop',PKG)
        adb('shell','am','start','-W','-n',COMPONENT)
        time.sleep(4)
        measures['catalogues'][label] = mesure
        (out / 'mesures-profil.json').write_text(json.dumps(measures, indent=2))
        print(label, json.dumps(mesure), flush=True)
