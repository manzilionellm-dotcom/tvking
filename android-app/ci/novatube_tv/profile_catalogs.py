"""Mesures Android 11 sur le panel de test en boucle locale. Un seul appareil."""
import contextlib
import http.server
import json
from pathlib import Path
import re
import ssl
import sqlite3
import tempfile
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


def preparer_demarrage(launcher_package):
    # L'arrêt de l'activité au premier plan peut lancer le HOME pendant que
    # am start -W attend NovaTube et faire attribuer le délai au lanceur.
    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
    limit = time.monotonic() + 40
    while time.monotonic() < limit:
        windows = adb('shell', 'dumpsys', 'window')
        if any('mCurrentFocus=' in line and launcher_package + '/' in line for line in windows.splitlines()):
            activities = adb('shell', 'dumpsys', 'activity', 'activities')
            if any('mResumedActivity' in line and launcher_package + '/' in line
                   for line in activities.splitlines()):
                break
        time.sleep(.5)
    else:
        raise RuntimeError('Le lanceur Android ne détient pas le focus avant la mesure.')
    adb('shell', 'am', 'force-stop', PKG)
    # pidof renvoie 1 lorsqu'il ne trouve pas le processus.
    limit = time.monotonic() + 10
    while adb('shell', f'pidof {PKG} || test $? -eq 1').strip():
        if time.monotonic() >= limit:
            raise RuntimeError('Le processus NovaTube existe encore avant la mesure.')
        time.sleep(.25)


def attendre_demarrage_stable():
    # Un force-stop avant le signal de stabilité compte comme un crash. Trois
    # de suite désactivent volontairement l'import Atlas pour ce processus.
    limit = time.monotonic() + 45
    while time.monotonic() < limit:
        pid = adb('shell', 'pidof', PKG).strip()
        if pid.isdigit():
            log = adb('logcat', '-d', '--pid', pid, '-s', 'flutter:I')
            if '[BootGuard] app stable' in log:
                if 'MODE SANS ÉCHEC' in log:
                    raise RuntimeError('Démarrage en mode sans échec avant le banc Atlas')
                return
        time.sleep(.5)
    raise RuntimeError('NovaTube ne signale pas un démarrage stable en 45 secondes')


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
                       f'{origine}/live/mire1/index.m3u8?lot={taille}&chaine={i}'])
    return ('\n'.join(lignes) + '\n').encode()


catalogues = {(tls, n): donnees(n, tls) for tls in (False, True) for n in (5000, 20000)}
requests = {}
logo = (Path(MEDIA) / 'logos' / 'mire1.png').read_bytes()


class Listes(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if path.startswith('/live/mire1/'):
            # Un seul jeu de mires, avec une adresse propre à chaque chaîne.
            # Les segments HLS restent servis pendant toute la navigation.
            nom = path.removeprefix('/live/mire1/')
            if nom != 'index.m3u8' and not (nom.startswith('seg') and nom[3:-3].isdigit() and nom.endswith('.ts')):
                self.send_error(404)
                return
            fichier = Path(MEDIA) / 'live' / 'mire1' / nom
            if not fichier.is_file():
                self.send_error(404)
                return
            data = fichier.read_bytes()
            mime = 'application/vnd.apple.mpegurl' if nom.endswith('m3u8') else 'video/mp2t'
        elif path.startswith('/logo/'):
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


def catalogue_enregistre(url, taille):
    # La phase utilise une box jetable et adb root. Lire une copie locale
    # permet de vérifier les données indépendamment du reçu du panel.
    rel = f'/data/user/0/{PKG}/app_flutter/tv_king.db'
    with tempfile.TemporaryDirectory() as tmp:
        fichier = Path(tmp) / 'tv_king.db'
        for suffixe in ('', '-wal'):
            if suffixe and adb('shell', f'if [ -f {rel}{suffixe} ]; then echo oui; fi').strip() != 'oui':
                continue
            with Path(str(fichier) + suffixe).open('wb') as copie:
                subprocess.run(['adb', '-s', SERIAL, 'exec-out', 'cat', rel + suffixe],
                               stdout=copie, check=True, timeout=40)
        with contextlib.closing(sqlite3.connect(fichier)) as db:
            origine = url.rsplit('/', 1)[0]
            motif = f'{origine}/live/mire1/index.m3u8?lot={taille}&chaine=%'
            resultat = db.execute('SELECT COUNT(*), COUNT(DISTINCT category), COUNT(DISTINCT stream_url) '
                                  'FROM channels WHERE stream_url LIKE ?', (motif,)).fetchone()
    if resultat != (taille, 40, taille):
        raise RuntimeError(f'Catalogue attendu {taille}, trouvé {resultat}')
    return dict(zip(('chaines', 'categories', 'adresses_distinctes'), resultat))


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
    home = adb('shell', 'cmd', 'package', 'resolve-activity', '--brief',
               '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME')
    launcher = home.strip().splitlines()[-1].split('/')[0]
    if not re.fullmatch(r'[a-zA-Z][\w.]+', launcher) or launcher == PKG or '/' not in home:
        raise RuntimeError('Le paquet du lanceur Android est introuvable.')
    rejected = []
    for essai in range(1, 11):
        if len(cold) == 5:
            break
        preparer_demarrage(launcher)
        result = adb('shell', 'am', 'start', '-W', '-n', COMPONENT)
        (out / f'demarrage-profil-{essai}.txt').write_text(result)
        tags = dict(line.split(': ', 1) for line in result.splitlines() if ': ' in line)
        if tags.get('Status') != 'ok' or tags.get('LaunchState') != 'COLD' or tags.get('Activity') != COMPONENT:
            rejected.append({'essai': essai, 'status': tags.get('Status'), 'activity': tags.get('Activity')})
            (out / 'lancements-ecartes.json').write_text(json.dumps(rejected))
            time.sleep(21)  # Une activité différente a reçu le focus.
            continue
        cold.append(int(tags['TotalTime']))
        attendre_demarrage_stable()
    if len(cold) != 5:
        raise RuntimeError('Cinq mesures Android à froid valides sont nécessaires')
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
    for tls, n in catalogues:
        protocol = 'https' if tls else 'http'
        label = f'{protocol}-{n}'
        url = f'{protocol}://127.0.0.1:{9443 if tls else 9080}/{n}.m3u'
        adb('shell', 'dumpsys', 'gfxinfo', PKG, 'reset')
        start = time.monotonic()
        published = requete('PUT', endpoint, {'sources': [{'type': 'm3u', 'label': label,
                                               'm3u_url': url}]}, token)
        rev = published['rev']
        if type(rev) is not int or rev <= 0:
            raise RuntimeError('Révision Atlas absente de la publication')
        trace = {'rev': rev, 'order_id': published.get('order_id'), 'catalogue': label}
        journal = out / (label + '-revision.json')
        journal.write_text(json.dumps(trace))
        while not confirme(endpoint, token, rev):
            if time.monotonic() - start > 100:
                trace['gets'] = requests.get((tls,n), 0)
                journal.write_text(json.dumps(trace))
                raise RuntimeError(f'Révision {rev} sans confirmation pour {label}')
            time.sleep(.12)
        if requests.get((tls, n), 0) < 1:
            raise RuntimeError('Aucune requête du profil Android pour ' + label)
        mesure = {'panel_confirmation_ms': round((time.monotonic()-start)*1000),
                  'requetes': requests[tls, n], 'import': frames(label + '-import'),
                  'catalogue_verifie': catalogue_enregistre(url, n)}
        trace.update({'etat_atlas': 'acknowledged', 'gets': mesure['requetes'],
                      'delai_ms': mesure['panel_confirmation_ms'], 'sqlite': mesure['catalogue_verifie']})
        journal.write_text(json.dumps(trace, indent=2))
        # La première tuile peut être une recommandation. Ouvrir le Direct
        # sur le libellé visible, puis confirmer le contenu de la liste.
        def ecran(fichier):
            with fichier.open('wb') as image:
                subprocess.run(['adb', '-s', SERIAL, 'exec-out', 'screencap', '-p'],
                               stdout=image, check=True)
        from screen_label import chercher
        accueil = out / (label + '-accueil.png')
        direct = out / (label + '-direct.png')
        ecran(accueil)
        # Le changement de révision peut afficher l'avis de retrait de
        # l'ancienne liste, y compris après la première pression sur Direct.
        # Le bouton Live derrière cet avis reste reconnaissable par OCR.
        prochain_essai = 0.0
        dialogue_ferme = False
        for _ in range(16):
            ecran(direct)
            image = str(direct)
            continuer = chercher(image, 'continue|continuer', 0, 1)
            if continuer and chercher(image, 'removed|retiree|supprimee', 0, 1):
                adb('shell', 'input', 'tap', *map(str, continuer))
                dialogue_ferme = True
                prochain_essai = time.monotonic() + .75
            elif chercher(image, 'canal|groupe', 0, 1):
                break
            elif time.monotonic() >= prochain_essai:
                # Le libellé peut être peint pendant la transition depuis
                # Bienvenue avant que la tuile accepte la pression. Réessayer
                # uniquement si les commandes de l'accueil sont encore visibles.
                sur_accueil = chercher(image, 'settings|reglages|favorites|favoris', 0, 1)
                bouton = chercher(image, 'live|direct', 0, 1) if sur_accueil else None
                if bouton:
                    adb('shell', 'input', 'tap', *map(str, bouton))
                    prochain_essai = time.monotonic() + 3
            time.sleep(.5)
        else:
            raise RuntimeError(f'Catalogue {label} enregistré mais Direct inaccessible')
        trace['avis_retrait_ferme'] = dialogue_ferme
        journal.write_text(json.dumps(trace, indent=2))
        for colonne, touch in [('chaines',None),('categories','KEYCODE_DPAD_LEFT')]:
            if touch:
                adb('shell', 'input', 'keyevent', touch)
            adb('shell', 'dumpsys', 'gfxinfo', PKG, 'reset')
            adb('shell', 'for i in $(seq 1 35); do input keyevent KEYCODE_DPAD_DOWN; done')
            mesure[colonne] = frames(label + '-' + colonne)
        (out / (label + '-memoire.txt')).write_text(adb('shell','dumpsys','meminfo',PKG))
        measures['catalogues'][label] = mesure
        (out / 'mesures-profil.json').write_text(json.dumps(measures, indent=2))
        print(label, json.dumps(mesure), flush=True)
        adb('shell','input','keyevent','KEYCODE_BACK')
        time.sleep(1)
        # Rétablit le focus de départ sur l'accueil avant la prochaine liste.
        preparer_demarrage(launcher)
        # Lecture indépendante avec le processus arrêté, avant tout redémarrage
        # et avant une éventuelle nouvelle requête du client.
        trace['processus_arrete'] = catalogue_enregistre(url, n)
        journal.write_text(json.dumps(trace, indent=2))
        adb('shell','am','start','-W','-n',COMPONENT)
        attendre_demarrage_stable()
        trace['apres_redemarrage'] = {
            'sqlite': catalogue_enregistre(url, n),
            'meme_revision_confirmee': confirme(endpoint, token, rev),
            'gets': requests.get((tls, n), 0),
        }
        journal.write_text(json.dumps(trace, indent=2))
        if not trace['apres_redemarrage']['meme_revision_confirmee']:
            raise RuntimeError(f'Révision {rev} introuvable après redémarrage')
