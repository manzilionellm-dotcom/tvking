#!/usr/bin/env python3
"""Récepteur DLNA de contrôle : PLAYING exige un vrai décodage du relais.

Le récepteur est explicitement émulé. Il refuse les sources directes afin
de vérifier la reprise par relais, puis lit les octets du serveur HTTP de
l'application par un transfert ADB du port dynamique de l'émulateur.
Aucun appel au service Android ou au canal Flutter n'est effectué ici.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import signal
import subprocess
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, urlunsplit
import xml.etree.ElementTree as ET


AV = 'urn:schemas-upnp-org:service:AVTransport:1'
CM = 'urn:schemas-upnp-org:service:ConnectionManager:1'
UUID = 'uuid:0bbcae01-7ca8-453b-a2ea-202611220001'
NAME = 'NOVATUBE QA Receiver'


class Receiver:
    def __init__(self, out: Path, serial: str):
        self.out, self.serial = out, serial
        self.lock = threading.RLock()
        self.process = None
        self.uri = ''
        self.state = 'STOPPED'
        self.frame = 0
        self.total_frames = 0
        self.seconds = 0.0
        self.generation = 0
        self.events = 0
        self.relay_bytes_sent = 0
        self.write_status()

    def event(self, kind, **data):
        with self.lock:
            self.events += 1
            record = {'utc': datetime.now(timezone.utc).isoformat(),
                      'event': kind, **data}
            with (self.out / 'receiver-events.jsonl').open('a') as handle:
                handle.write(json.dumps(record) + '\n')
            print(json.dumps(record), flush=True)

    def write_status(self):
        with self.lock:
            body = {'state': self.state, 'original_uri': self.uri,
                    'decoded_frames': self.frame, 'total_decoded_frames': self.total_frames,
                    'decoded_seconds': self.seconds, 'decoder_pid': self.process.pid if self.process else None,
                    'generation': self.generation, 'emulated_receiver': True,
                    'relay_upstream_bytes_sent': self.relay_bytes_sent}
            temp = self.out / 'receiver-status.tmp'
            temp.write_text(json.dumps(body, indent=2) + '\n')
            temp.replace(self.out / 'receiver-status.json')
            return body

    def stop(self):
        with self.lock:
            self.generation += 1
            process, self.process = self.process, None
            if process and process.poll() is None:
                process.send_signal(signal.SIGCONT)
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=2)
            self.state = 'STOPPED'
            self.write_status()

    def set_uri(self, uri):
        url = urlsplit(uri)
        # Le refus direct vérifie le mécanisme normal de reprise de l'app.
        if not url.path.startswith('/relay/') or url.hostname not in ('10.0.2.15', '10.0.2.16') or not url.port:
            self.event('direct_uri_rejected', uri=uri)
            return False
        self.stop()
        self.uri = uri
        self.frame = 0
        self.seconds = 0.0
        self.write_status()
        self.event('relay_uri_received', uri=uri)
        return True

    def play(self):
        with self.lock:
            if self.process and self.process.poll() is None:
                self.process.send_signal(signal.SIGCONT)
                self.state = 'PLAYING' if self.frame > 0 else 'TRANSITIONING'
                self.write_status()
                return
            if not self.uri:
                raise RuntimeError('Aucune URI de relais reçue')
            url = urlsplit(self.uri)
            subprocess.run(['adb', '-s', self.serial, 'forward', 'tcp:19001', f'tcp:{url.port}'], check=True)
            forwarded = urlunsplit((url.scheme, '127.0.0.1:19001', url.path, url.query, ''))
            self.generation += 1
            generation = self.generation
            command = ['ffmpeg', '-hide_banner', '-loglevel', 'warning', '-nostdin', '-y',
                       '-readrate', '1', '-analyzeduration', '500000', '-probesize', '128000',
                       '-threads', '2', '-i', forwarded, '-map', '0:v:0', '-an', '-f', 'null', '-',
                       '-map', '0:v:0', '-an', '-vf', 'select=not(mod(n\\,125)),scale=480:-2',
                       '-q:v', '4', '-fps_mode', 'vfr', '-threads', '1', str(self.out / f'receiver-{generation}-%03d.jpg'),
                       '-progress', 'pipe:1', '-stats_period', '0.25']
            errors = (self.out / f'decoder-{generation}.txt').open('w')
            self.process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=errors, text=True, bufsize=1)
            self.state = 'TRANSITIONING'
            self.write_status()
            self.event('decoder_started', original_uri=self.uri, forwarded_uri=forwarded,
                       adb_guest_port=url.port, pid=self.process.pid)
            threading.Thread(target=self.collect_progress,
                             args=(self.process, generation, errors), daemon=True).start()

    def collect_progress(self, process, generation, errors):
        try:
            for line in process.stdout:
                key, _, value = line.strip().partition('=')
                with self.lock:
                    if generation != self.generation:
                        break
                    if key == 'frame':
                        current = int(value.strip())
                        self.total_frames += max(0, current - self.frame)
                        first = self.frame == 0 and current > 0
                        self.frame = current
                        if first:
                            self.state = 'PLAYING'
                            self.event('first_real_frame_decoded', frame=current)
                    elif key == 'out_time_us' and value.lstrip('-').isdigit():
                        self.seconds = int(value) / 1_000_000
                    elif key == 'progress':
                        self.write_status()
            process.wait()
            with self.lock:
                if generation == self.generation:
                    self.state = 'STOPPED'
                    self.write_status()
                    self.event('decoder_ended', returncode=process.returncode, frames=self.frame)
        finally:
            errors.close()

    def pause(self):
        with self.lock:
            if self.process and self.process.poll() is None:
                self.process.send_signal(signal.SIGSTOP)
                self.state = 'PAUSED_PLAYBACK'
                self.write_status()


def envelope(action, content='', service=AV):
    return ('<?xml version="1.0"?>'
            '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
            's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
            f'<u:{action}Response xmlns:u="{service}">{content}</u:{action}Response>'
            '</s:Body></s:Envelope>').encode()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--media', type=Path, required=True)
    parser.add_argument('--serial', default='emulator-5554')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    receiver = Receiver(args.out, args.serial)

    class Handler(SimpleHTTPRequestHandler):
        extensions_map = {**SimpleHTTPRequestHandler.extensions_map,
                          '.ts': 'video/mp2t', '.m3u': 'audio/x-mpegurl'}

        def __init__(self, *items, **kwargs):
            super().__init__(*items, directory=str(args.media), **kwargs)

        def log_message(self, fmt, *items):
            receiver.event('http', request=fmt % items)

        def copyfile(self, source, outputfile):
            if urlsplit(self.path).path != '/pattern.ts':
                return super().copyfile(source, outputfile)
            # Cadencer la mire empêche une courte lecture en fond de n'être
            # que la consommation d'un fichier déjà entièrement tamponné.
            rate = (args.media / 'pattern.ts').stat().st_size / 180
            started, sent, last_report = time.monotonic(), 0, 0
            relay_connection = receiver.process is not None
            receiver.event('media_connection_started', relay=relay_connection)
            try:
                while block := source.read(188 * 128):
                    outputfile.write(block)
                    outputfile.flush()
                    sent += len(block)
                    if relay_connection:
                        with receiver.lock:
                            receiver.relay_bytes_sent += len(block)
                        if sent - last_report >= 250_000:
                            receiver.event('relay_upstream_bytes', connection_bytes=sent,
                                           total_bytes=receiver.relay_bytes_sent)
                            last_report = sent
                    delay = started + sent / rate - time.monotonic()
                    if delay > 0:
                        time.sleep(delay)
            except (BrokenPipeError, ConnectionResetError):
                receiver.event('media_connection_closed', relay=relay_connection, bytes=sent)

        def reply(self, data, code=200, content_type='text/xml; charset=utf-8'):
            self.send_response(code)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == '/device.xml':
                self.reply(('<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0">'
                    '<specVersion><major>1</major><minor>0</minor></specVersion><device>'
                    '<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>'
                    f'<friendlyName>{NAME}</friendlyName><manufacturer>QA fixture</manufacturer>'
                    f'<modelName>FFmpeg receiver (emulated)</modelName><UDN>{UUID}</UDN><serviceList>'
                    f'<service><serviceType>{AV}</serviceType><serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>'
                    '<controlURL>/AVTransport/control</controlURL><eventSubURL>/AVTransport/event</eventSubURL>'
                    '<SCPDURL>/AVTransport.xml</SCPDURL></service>'
                    f'<service><serviceType>{CM}</serviceType><serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>'
                    '<controlURL>/ConnectionManager/control</controlURL><eventSubURL>/ConnectionManager/event</eventSubURL>'
                    '<SCPDURL>/ConnectionManager.xml</SCPDURL></service>'
                    '</serviceList></device></root>').encode())
            elif self.path == '/status.json':
                self.reply(json.dumps(receiver.write_status()).encode(), content_type='application/json')
            else:
                super().do_GET()

        def do_POST(self):
            data = self.rfile.read(int(self.headers.get('Content-Length', '0')))
            action = self.headers.get('SOAPAction', '').strip('"').split('#')[-1]
            receiver.event('soap', action=action)
            try:
                if action == 'GetProtocolInfo':
                    self.reply(envelope(action, '<Source></Source><Sink>http-get:*:video/mp2t:*</Sink>', CM))
                    return
                if action == 'SetAVTransportURI':
                    xml = ET.fromstring(data)
                    uri = next((n.text or '' for n in xml.iter() if n.tag.split('}')[-1] == 'CurrentURI'), '')
                    if not receiver.set_uri(uri):
                        self.reply(b'<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
                            b'<s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>'
                            b'<UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>714</errorCode>'
                            b'<errorDescription>Direct source unavailable; local relay required</errorDescription>'
                            b'</UPnPError></detail></s:Fault></s:Body></s:Envelope>', 500)
                        return
                elif action == 'Play':
                    receiver.play()
                elif action == 'Pause':
                    receiver.pause()
                elif action == 'Stop':
                    receiver.stop()
                elif action == 'GetTransportInfo':
                    self.reply(envelope(action, f'<CurrentTransportState>{receiver.state}</CurrentTransportState>'
                        '<CurrentTransportStatus>OK</CurrentTransportStatus><CurrentSpeed>1</CurrentSpeed>'))
                    return
                elif action == 'GetPositionInfo':
                    seconds = int(receiver.seconds)
                    self.reply(envelope(action, '<Track>1</Track><TrackDuration>00:03:00</TrackDuration>'
                        f'<RelTime>00:{seconds // 60:02d}:{seconds % 60:02d}</RelTime><AbsTime>NOT_IMPLEMENTED</AbsTime>'))
                    return
                self.reply(envelope(action))
            except Exception as error:
                receiver.event('receiver_error', error=str(error))
                self.reply(str(error).encode(), 500, 'text/plain')

    server = ThreadingHTTPServer(('127.0.0.1', 18999), Handler)
    try:
        receiver.event('receiver_ready', name=NAME, transport='DLNA', media='synthetic test pattern only')
        server.serve_forever()
    finally:
        receiver.stop()
        server.server_close()


if __name__ == '__main__':
    main()
