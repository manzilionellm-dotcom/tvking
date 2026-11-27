"""Lancer la campagne NovaTube de zapping et de lecture depuis le poste ADB de la box de test."""
import argparse
from contextlib import ExitStack
import hashlib
import ipaddress
import json
import os
from pathlib import Path
from urllib.parse import urlsplit
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
# Seuls les APK complets effectivement mesurés sur le banc portent ces empreintes.
REVISIONS_BY_SHA = {
    'aa93b4b959bb93d0e863d338be98445254f3412100302870a6c58a4d52662b34': 'fe134dd4c580c4f7c007ca2b9026fb6a17c2e081',
    '7936acfa8e1064b8d2c58314c59d1ae5f4a2ebed4c5c56beefdcb0b1c6f629ad': 'caf2209bd772ad54e085e8574d1c0cd8be1783b6',
}
PACKAGE = 'com.sevenmotion.novatube.tv'
ATLAS = 'tcp:8788'
LAN = [ipaddress.ip_network(cidr) for cidr in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')]


def adb(serial, *args, timeout=20):
    run = subprocess.run(['adb', '-s', serial, *args], capture_output=True, text=True, timeout=timeout)
    if run.returncode:
        raise ValueError('ADB : ' + (run.stderr.strip() or run.stdout.strip()))
    return run.stdout.strip()


def sha256(path):
    with path.open('rb') as source:
        digest = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(serial):
    if serial.startswith('emulator-') or adb(serial, 'get-state') != 'device':
        raise ValueError('Une box physique autorisée est nécessaire.')
    props = dict(re.findall(r'^\[([^]]+)\]: \[([^\n]*)\]\r?$', adb(serial, 'shell', 'getprop'), re.M))
    keys = ('product.manufacturer', 'product.model', 'hardware', 'build.fingerprint',
            'build.version.release', 'product.cpu.abi')
    device = {key: props.get('ro.' + key, '') for key in keys}
    if not all(device.values()):
        raise ValueError('Identité matérielle Android incomplète.')
    if (any(props.get(p) == '1' for p in ('ro.kernel.qemu', 'ro.boot.qemu'))
            or re.search(r'emulator|goldfish|ranchu|cuttlefish|sdk_gphone|generic_x86',
                         ' '.join(device.values()), re.I)):
        raise ValueError('Appareil virtuel détecté.')
    features = set(adb(serial, 'shell', 'pm', 'list', 'features').splitlines())
    if not features & {'feature:android.software.leanback', 'feature:android.hardware.type.television'}:
        raise ValueError('Fonction Android TV introuvable.')
    ram = re.search(r'^MemTotal:\s+([1-9]\d*) kB', adb(serial, 'shell', 'cat', '/proc/meminfo'), re.M)
    if not ram:
        raise ValueError('RAM indisponible.')
    device['MemTotal_kib'] = int(ram[1])
    device['wm_size'] = adb(serial, 'shell', 'wm', 'size')
    device['wm_density'] = adb(serial, 'shell', 'wm', 'density')
    return device


def package_state(serial, reuse, expected_sha):
    raw = adb(serial, 'shell', 'pm', 'list', 'users')
    users = re.findall(r'UserInfo\{(\d+):', raw)
    active = adb(serial, 'shell', 'am', 'get-current-user')
    if active not in users or len(users) != raw.count('UserInfo{'):
        raise ValueError('Inventaire des utilisateurs Android incomplet.')
    present = []
    for user in users:
        packages = adb(serial, 'shell', 'pm', 'list', 'packages', '-u', '--user', user).splitlines()
        if not packages or any(not row.startswith('package:') for row in packages):
            raise ValueError('Lecture des paquets incomplète pour un utilisateur.')
        if 'package:' + PACKAGE in packages:
            present.append(user)
    if present:
        if not reuse or active not in present:
            raise ValueError('Paquet NovaTube connu sur la box. Installation refusée.')
        verify_installed(serial, active, expected_sha)
    elif reuse:
        raise ValueError('Réutilisation demandée mais le paquet est absent.')
    return active


def verify_installed(serial, active, expected_sha):
    # L'artefact QA est un APK universel monobloc. Tout split est inattendu.
    listing = adb(serial, 'shell', 'pm', 'path', '--user', active, PACKAGE)
    match = re.fullmatch(r'package:(/[^\s]+/base\.apk)', listing)
    if not match:
        raise ValueError('Paquet installé illisible ou fractionné.')
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / 'base.apk'
        adb(serial, 'pull', match[1], str(copy), timeout=240)
        if sha256(copy) != expected_sha:
            raise ValueError('Le binaire déjà installé est différent du candidat QA.')


def atlas_route(serial):
    listing = adb(serial, 'reverse', '--list')
    rows = [line.split() for line in listing.splitlines() if line.strip()]
    if any(len(row) != 3 for row in rows):
        raise ValueError('Table de redirection ADB illisible.')
    return next((row[2] for row in rows if row[1] == ATLAS), None)


def remove_own_route(serial, owned):
    if atlas_route(serial) == owned:
        adb(serial, 'reverse', '--remove', ATLAS)


def start_service(stack, args, log, ready, env=None):
    stream = stack.enter_context(log.open('w'))
    proc = subprocess.Popen(args, stdout=stream, stderr=subprocess.STDOUT, env=env)

    def stop():
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=12)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    stack.callback(stop)
    until = time.monotonic() + 90
    while proc.poll() is None and time.monotonic() < until:
        if ready():
            return proc
        time.sleep(.3)
    raise ValueError('Service local indisponible. Consulter ' + str(log))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True, help='Série explicite indiquée par adb devices')
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--check', action='store_true', help='Précontrôle de la box et du fichier')
    parser.add_argument('--reuse-exact', action='store_true', help='Utiliser une installation QA identique')
    parser.add_argument('--media-ip', type=ipaddress.IPv4Address, help='Adresse LAN du poste qui sert les mires')
    parser.add_argument('--atlas-dir', type=Path, help='Dossier cloudflare du checkout Atlas de test')
    parser.add_argument('--output', type=Path, help='Nouveau dossier pour les mesures')
    args = parser.parse_args()
    apk_sha = sha256(args.apk)
    revision = REVISIONS_BY_SHA.get(apk_sha)
    if revision is None:
        raise ValueError('SHA-256 absent des APK QA mesurés.')
    device = inventory(args.serial)
    user = package_state(args.serial, args.reuse_exact, apk_sha)
    if atlas_route(args.serial) is not None:
        raise ValueError('Le port Atlas 8788 est déjà redirigé sur cette box.')
    if not args.reuse_exact and '-R:' not in adb(args.serial, 'shell', 'pm', 'help'):
        raise ValueError('Android ne confirme pas la prise en charge de l’installation sans remplacement.')
    device.update(source_revision=revision, apk_sha256=apk_sha)
    print(json.dumps(device, ensure_ascii=False, indent=2), flush=True)
    if args.check:
        return
    if not args.media_ip or not any(args.media_ip in net for net in LAN):
        parser.error('--media-ip doit être une IPv4 privée du poste de test.')
    if not args.atlas_dir or not (args.atlas_dir / 'novatube4k-entry.js').is_file() or not args.output:
        parser.error('--atlas-dir et --output sont requis pour la campagne.')
    for program in ('node', 'ffmpeg'):
        if shutil.which(program) is None:
            raise ValueError(f'Outil absent : {program}')
    import PIL  # Dépendance de lecture du marqueur, vérifiée avant l'installation.
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    url = f'http://{args.media_ip}:18471/channels.m3u'
    evidence = dict(device, playlist=url, atlas_transport='adb reverse', media_transport='LAN HTTP direct')
    (out / 'device.json').write_text(json.dumps(evidence, indent=2))
    with ExitStack() as stack:
        secret_dir = Path(stack.enter_context(tempfile.TemporaryDirectory()))
        info = secret_dir / 'atlas.json'
        start_service(stack, ['node', str(HERE / 'atlas_local_server.mjs'), str(args.atlas_dir), str(info)],
                      out / 'atlas.log', info.is_file, env={**os.environ, 'ATLAS_PORT': '0'})
        endpoint = urlsplit(json.loads(info.read_text())['url'])
        if endpoint.hostname not in ('localhost', '127.0.0.1') or not endpoint.port:
            raise ValueError('Adresse Atlas locale inattendue.')
        media_log = out / 'media.log'
        start_service(stack, [sys.executable, str(HERE / 'regional_live_source.py'), '--bind',
                              str(args.media_ip), '--port', '18471'], media_log,
                      lambda: url in media_log.read_text())
        owned = f'tcp:{endpoint.port}'
        adb(args.serial, 'reverse', '--no-rebind', ATLAS, owned)
        stack.callback(remove_own_route, args.serial, owned)
        if atlas_route(args.serial) != owned:
            raise ValueError('Redirection privée Atlas absente.')
        if user != adb(args.serial, 'shell', 'am', 'get-current-user'):
            raise ValueError('Utilisateur Android modifié pendant la préparation.')
        route = adb(args.serial, 'shell', 'ip', '-4', 'route', 'get', str(args.media_ip))
        client = re.search(r'\bsrc (\d+\.\d+\.\d+\.\d+)\b', route)
        if not client:
            raise ValueError('Adresse de la box sur la route du média indéterminée.')
        if not args.reuse_exact:
            package_state(args.serial, False, apk_sha)
            installed = adb(args.serial, 'install', '-R', '--user', user, str(args.apk.resolve()), timeout=240)
            if 'Success' not in installed:
                raise ValueError('Installation non confirmée : ' + installed)
        verify_installed(args.serial, user, apk_sha)
        evidence['installed_apk_sha256'] = apk_sha
        (out / 'device.json').write_text(json.dumps(evidence, indent=2))
        launch = adb(args.serial, 'shell', 'am', 'start', '--user', user, '-W', '-n',
                     f'{PACKAGE}/com.example.tv_king.MainActivity')
        if 'Status: ok' not in launch:
            raise ValueError('Lancement non confirmé : ' + launch)
        print(f'Box de test : importer {url} puis ouvrir Mire A en plein écran.', flush=True)
        input('Lorsque Mire A bouge, appuyer sur Entrée sur ce poste : ')
        segment = rf'^{re.escape(client[1])} - - .*"GET /A/[^ ]+\.ts HTTP/[^"]+" 200'
        if not re.search(segment, media_log.read_text(), re.M):
            raise ValueError('Aucun segment de la mire A servi par cette origine LAN.')
        subprocess.run([sys.executable, str(HERE / 'benchmark.py'), str(out),
                        '--physical-serial', args.serial], check=True,
                       env={**os.environ, 'BENCH_PACKAGE': PACKAGE})
        print(f'Mesures brutes et résultats : {out}', flush=True)


if __name__ == '__main__':
    # Un arrêt normal du poste doit libérer nos deux services et notre redirection.
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(128 + signum))
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError, EOFError) as err:
        sys.exit(str(err))
