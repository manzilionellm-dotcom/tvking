#!/usr/bin/env python3
# =========================================================
#  deploy_download_worker.py — Met en ligne le Worker novatube-downloads
# =========================================================
#  Lancé par .github/workflows/novatube-tv-domaine.yml (jamais à la main
#  avec un jeton copié). Variables : CF_TOKEN (secret CLOUDFLARE_API_TOKEN),
#  CF_ACCOUNT (secret CLOUDFLARE_ACCOUNT_ID, facultatif), EXPECTED_SHA256
#  (empreinte de l'APK NovaTube TV publié dans la pré-version fixe).
#
#  Ordre, et garde-fous :
#    1. relire et SAUVEGARDER le script actuel (fichier ancien-worker.mjs) ;
#    2. noter le comportement actuel de /novatube.apk (pour /mobile.apk) ;
#    3. envoyer le nouveau script (mêmes date et options de compatibilité,
#       liaisons existantes conservées) ;
#    4. vérifier EN LIGNE : /novatube.apk → 302 vers l'APK TV, téléchargement
#       complet et SHA-256 identique ; /mobile.apk → même résultat qu'avant ;
#    5. si une vérification échoue : RETOUR ARRIÈRE automatique sur l'ancien
#       script, puis échec du job.
#  Rien n'est affiché du jeton. Aucun autre Worker n'est touché.
# =========================================================
from __future__ import annotations

import email.parser
import email.policy
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API = 'https://api.cloudflare.com/client/v4'
SCRIPT = 'novatube-downloads'
DOMAIN = 'https://novatube.zuno8k.com'
HERE = Path(__file__).resolve().parent
TV_APK_URL = ('https://github.com/manzilionellm-dotcom/tvking/releases/download/'
              'novatube-tv-download/NovaTube-TV.apk')
TOKEN = os.environ.get('CF_TOKEN', '')


def die(message: str) -> None:
    print(f'::error::{message}')
    sys.exit(1)


def cf(method: str, path: str, data: bytes | None = None,
       content_type: str | None = None) -> tuple[int, bytes, str]:
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header('Authorization', f'Bearer {TOKEN}')
    if content_type:
        req.add_header('Content-Type', content_type)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read(), r.headers.get('Content-Type', '')
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers.get('Content-Type', '')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):  # noqa: D401 - on lit la 302
        return None


def probe(path: str) -> tuple[int, str]:
    """Code HTTP et Location de l'adresse publique, SANS suivre la redirection."""
    opener = urllib.request.build_opener(NoRedirect)
    req = urllib.request.Request(DOMAIN + path, method='GET',
                                 headers={'User-Agent': 'novatube-deploy-check'})
    try:
        with opener.open(req, timeout=20) as r:
            return r.status, r.headers.get('Location', '')
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get('Location', '')
    except Exception:
        return 0, ''


def download_sha(path: str) -> str:
    req = urllib.request.Request(DOMAIN + path, headers={'User-Agent': 'novatube-deploy-check'})
    digest = hashlib.sha256()
    with urllib.request.urlopen(req, timeout=180) as r:
        while chunk := r.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def account_id() -> str:
    given = os.environ.get('CF_ACCOUNT', '').strip()
    if given:
        return given
    status, body, _ = cf('GET', '/accounts?per_page=50')
    if status != 200:
        die(f'liste des comptes Cloudflare refusée (HTTP {status})')
    for acc in json.loads(body).get('result', []):
        s, _, _ = cf('GET', f"/accounts/{acc['id']}/workers/scripts/{SCRIPT}/settings")
        if s == 200:
            return acc['id']
    die(f'Worker {SCRIPT} introuvable avec ce jeton')
    return ''


def current_module(acc: str) -> bytes:
    status, body, ctype = cf('GET', f'/accounts/{acc}/workers/scripts/{SCRIPT}')
    if status != 200:
        die(f'lecture du script actuel refusée (HTTP {status})')
    if 'multipart' not in ctype:
        return body
    msg = email.parser.BytesParser(policy=email.policy.default).parsebytes(
        b'Content-Type: ' + ctype.encode() + b'\r\n\r\n' + body)
    for part in msg.iter_parts():
        if part.get_param('name', header='content-disposition') == 'worker.mjs':
            return part.get_payload(decode=True)
    die('module worker.mjs introuvable dans le script actuel')
    return b''


def settings(acc: str) -> dict:
    status, body, _ = cf('GET', f'/accounts/{acc}/workers/scripts/{SCRIPT}/settings')
    if status != 200:
        die(f'réglages du script refusés (HTTP {status})')
    return json.loads(body).get('result', {})


def upload(acc: str, module: bytes, conf: dict) -> None:
    metadata: dict = {'main_module': 'worker.mjs'}
    if conf.get('compatibility_date'):
        metadata['compatibility_date'] = conf['compatibility_date']
    if conf.get('compatibility_flags'):
        metadata['compatibility_flags'] = conf['compatibility_flags']
    kinds = sorted({b.get('type') for b in conf.get('bindings', []) if b.get('type')})
    if kinds:
        metadata['keep_bindings'] = kinds  # liaisons existantes conservées
    boundary = uuid.uuid4().hex
    parts = [
        (f'--{boundary}\r\nContent-Disposition: form-data; name="metadata"\r\n'
         'Content-Type: application/json\r\n\r\n').encode() + json.dumps(metadata).encode() + b'\r\n',
        (f'--{boundary}\r\nContent-Disposition: form-data; name="worker.mjs"; filename="worker.mjs"\r\n'
         'Content-Type: application/javascript+module\r\n\r\n').encode() + module + b'\r\n',
        f'--{boundary}--\r\n'.encode(),
    ]
    status, body, _ = cf('PUT', f'/accounts/{acc}/workers/scripts/{SCRIPT}', b''.join(parts),
                         f'multipart/form-data; boundary={boundary}')
    ok = status == 200 and json.loads(body or b'{}').get('success') is True
    if not ok:
        errors = json.loads(body or b'{}').get('errors', [])
        die(f'envoi du script refusé (HTTP {status}) : {[e.get("message") for e in errors]}')


def wait_for(check, seconds: int = 120) -> bool:
    end = time.time() + seconds
    while time.time() < end:
        if check():
            return True
        time.sleep(5)
    return False


def main() -> int:
    if not TOKEN:
        die('secret CLOUDFLARE_API_TOKEN absent')
    expected = os.environ.get('EXPECTED_SHA256', '').strip()
    if len(expected) != 64:
        die('EXPECTED_SHA256 absent')
    acc = account_id()
    conf = settings(acc)
    old = current_module(acc)
    Path('ancien-worker.mjs').write_bytes(old)
    before = probe('/novatube.apk')
    print(f'avant : /novatube.apk → HTTP {before[0]} {before[1]}')

    new = (HERE / 'download-worker.mjs').read_bytes()
    upload(acc, new, conf)
    print('nouveau script envoyé ; vérification en ligne…')

    tv_ok = wait_for(lambda: probe('/novatube.apk') == (302, TV_APK_URL))
    sha_ok = False
    if tv_ok:
        got = download_sha('/novatube.apk')
        sha_ok = got == expected
        print(f'téléchargement par le domaine : SHA-256 {got} ({"identique" if sha_ok else "DIFFÉRENT"})')
    mobile = probe('/mobile.apk')
    mobile_ok = mobile == before
    print(f'après : /mobile.apk → HTTP {mobile[0]} {mobile[1]} (attendu : comme /novatube.apk avant)')

    if tv_ok and sha_ok and mobile_ok:
        print('✓ novatube.zuno8k.com/novatube.apk sert NovaTube TV ; mobile conservé sur /mobile.apk')
        return 0

    print('::warning::vérification en échec → retour arrière sur l\'ancien script')
    upload(acc, old, conf)
    restored = wait_for(lambda: probe('/novatube.apk') == before)
    die('déploiement annulé ; ancien script ' + ('rétabli et vérifié' if restored else 'renvoyé (vérification non concluante)'))
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
