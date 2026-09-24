// =========================================================
//  local_stream_relay_test.dart — Le mini-relais "1 connexion"
// =========================================================
//  On vérifie le cœur du relais : à partir d'UNE seule connexion
//  upstream (simulée par un faux serveur), les octets arrivent bien
//    1. au lecteur (le client HTTP qui lit l'URL locale), ET
//    2. dans le fichier d'enregistrement.
//  C'est exactement la garantie "regarder + enregistrer sans 2e
//  connexion, fichier jamais vide".
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';

void main() {
  // Un faux serveur "IPTV" qui débite des octets en continu, et qui
  // COMPTE le nombre de connexions qu'on lui ouvre (pour prouver qu'il
  // n'y en a qu'UNE, même en enregistrant pendant qu'on regarde).
  late HttpServer fakeUpstream;
  late String fakeUrl;
  int upstreamConnections = 0;
  Timer? feeder;

  setUp(() async {
    upstreamConnections = 0;
    fakeUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fakeUrl = 'http://127.0.0.1:${fakeUpstream.port}/live';
    fakeUpstream.listen((HttpRequest req) {
      upstreamConnections++;
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType('video', 'mp2t');
      req.response.bufferOutput = false;
      // Débit régulier : 188 octets (taille d'un paquet TS) toutes les
      // 20 ms, tant que la socket est ouverte.
      final List<int> packet = List<int>.filled(188, 0x47);
      feeder?.cancel();
      feeder = Timer.periodic(const Duration(milliseconds: 20), (_) {
        try {
          req.response.add(packet);
        } catch (_) {}
      });
    });
  });

  tearDown(() async {
    feeder?.cancel();
    await fakeUpstream.close(force: true);
  });

  test('le lecteur reçoit des octets ET l\'enregistrement n\'est pas vide, '
      'sur UNE seule connexion upstream', () async {
    final LocalStreamRelay relay = LocalStreamRelay.instance;

    // 1) URL locale que "mpv" ouvrirait.
    final String localUrl = await relay.playUrlFor(fakeUrl);
    expect(localUrl, contains('127.0.0.1'));

    // 2) Un client (rôle de mpv) lit l'URL locale.
    final HttpClient client = HttpClient();
    final HttpClientRequest req = await client.getUrl(Uri.parse(localUrl));
    final HttpClientResponse resp = await req.close();
    expect(resp.statusCode, 200);

    int playerBytes = 0;
    final StreamSubscription<List<int>> sub = resp.listen((List<int> c) {
      playerBytes += c.length;
    });

    // Laisse couler un peu : le lecteur doit recevoir des octets.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(playerBytes, greaterThan(0),
        reason: 'le lecteur doit recevoir le flux via le relais');

    // 3) On démarre l'enregistrement (tee) pendant qu'on "regarde".
    final Directory tmp = await Directory.systemTemp.createTemp('relay_test');
    final String recPath = '${tmp.path}/capture.ts';
    final bool ok =
        await relay.startRecording(realUrl: fakeUrl, filePath: recPath);
    expect(ok, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 400));

    final int recordedBytes = await relay.stopRecording(fakeUrl);
    expect(recordedBytes, greaterThan(0),
        reason: 'l\'enregistrement ne doit PAS être vide');

    // Le fichier sur disque contient bien des octets.
    final File f = File(recPath);
    expect(await f.exists(), isTrue);
    expect(await f.length(), greaterThan(0));

    // 4) PREUVE ANTI MULTI-VIEW : malgré lecture + enregistrement
    //    simultanés, on n'a ouvert qu'UNE connexion vers l'upstream.
    expect(upstreamConnections, 1,
        reason: 'regarder + enregistrer doit tenir sur 1 seule connexion');

    await sub.cancel();
    client.close(force: true);
    await tmp.delete(recursive: true);
  });
}
