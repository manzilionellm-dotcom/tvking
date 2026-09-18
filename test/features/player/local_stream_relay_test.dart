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
import 'package:tv_king/features/cast/data/stream_probe.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';
import 'package:tv_king/features/player/data/xtream_url_variants.dart';

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

  // =================================================================
  //  Bug terrain 2026-07-08 : 404 réessayé 13× au lieu de laisser la
  //  cascade basculer de format + sessions zombies après zapping.
  // =================================================================
  group('fail-fast 4xx & fermeture au zap', () {
    /// Journal boîte noire aplati (pour vérifier ce qui a été tracé).
    String journal() => StreamDiagnostics.instance.events
        .map((StreamDiagEvent e) => e.message)
        .join('\n');

    test('HTTP 404 dès la 1re réponse → UNE seule requête upstream '
        '(aucun retry), session fermée', () async {
      int hits = 0;
      final HttpServer dead =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      dead.listen((HttpRequest req) async {
        hits++;
        req.response.statusCode = 404;
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html>not found</html>');
        await req.response.close();
      });
      final String deadUrl = 'http://127.0.0.1:${dead.port}/U/P/42.ts';

      final LocalStreamRelay relay = LocalStreamRelay.instance;
      final String localUrl = await relay.playUrlFor(deadUrl);
      final HttpClient client = HttpClient();
      final HttpClientResponse resp =
          await (await client.getUrl(Uri.parse(localUrl))).close();
      // Le relais doit FERMER la session (fail-fast) → notre connexion
      // locale se termine vite, sans pendre indéfiniment.
      await resp.drain<void>().timeout(const Duration(seconds: 5));

      // Fenêtre où le back-off (2 s) aurait relancé si le fail-fast
      // était cassé : le compteur ne doit PAS bouger.
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(hits, 1,
          reason: '404 définitif = zéro retry (la cascade prend la main)');
      expect(journal(), contains('définitif'),
          reason: 'le fail-fast doit être tracé dans la boîte noire');

      client.close(force: true);
      await dead.close(force: true);
    });

    test('erreur réseau TRANSITOIRE → le retry reste justifié '
        '(reconnexion puis lecture)', () async {
      int hits = 0;
      Timer? feed;
      final HttpServer flaky =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      flaky.listen((HttpRequest req) async {
        hits++;
        if (hits == 1) {
          // 1re connexion : coupée net SANS réponse HTTP (panne réseau
          // simulée) → le relais doit reconnecter, pas abandonner.
          final Socket s = await req.response.detachSocket();
          s.destroy();
          return;
        }
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType('video', 'mp2t');
        req.response.bufferOutput = false;
        final List<int> packet = List<int>.filled(188, 0x47);
        feed = Timer.periodic(const Duration(milliseconds: 20), (_) {
          try {
            req.response.add(packet);
          } catch (_) {}
        });
      });
      final String flakyUrl = 'http://127.0.0.1:${flaky.port}/U/P/7.ts';

      final LocalStreamRelay relay = LocalStreamRelay.instance;
      final String localUrl = await relay.playUrlFor(flakyUrl);
      final HttpClient client = HttpClient();
      final HttpClientResponse resp =
          await (await client.getUrl(Uri.parse(localUrl))).close();
      int bytes = 0;
      final StreamSubscription<List<int>> sub =
          resp.listen((List<int> c) => bytes += c.length);

      // Back-off du 1er retry = 2 s → on laisse 4 s au relais.
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(hits, greaterThanOrEqualTo(2),
          reason: 'panne transitoire = reconnexion');
      expect(bytes, greaterThan(0),
          reason: 'après reconnexion, le flux doit couler');

      await sub.cancel();
      client.close(force: true);
      feed?.cancel();
      await flaky.close(force: true);
    });

    test('zap → la session relais précédente est FERMÉE (plus de zombie)',
        () async {
      Timer? feedA;
      Timer? feedB;
      final HttpServer srv =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((HttpRequest req) {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType('video', 'mp2t');
        req.response.bufferOutput = false;
        final List<int> packet = List<int>.filled(188, 0x47);
        final Timer t = Timer.periodic(const Duration(milliseconds: 20), (_) {
          try {
            req.response.add(packet);
          } catch (_) {}
        });
        if (req.uri.path.contains('france2')) {
          feedA = t;
        } else {
          feedB = t;
        }
      });
      final String urlA = 'http://127.0.0.1:${srv.port}/U/P/france2.ts';
      final String urlB = 'http://127.0.0.1:${srv.port}/U/P/france3.ts';

      final LocalStreamRelay relay = LocalStreamRelay.instance;
      // « France 2 » joue…
      final String localA = await relay.playUrlFor(urlA);
      final HttpClient client = HttpClient();
      final HttpClientResponse respA =
          await (await client.getUrl(Uri.parse(localA))).close();
      int bytesA = 0;
      final Completer<void> aClosed = Completer<void>();
      respA.listen((List<int> c) => bytesA += c.length,
          onDone: aClosed.complete, onError: (_) => aClosed.complete());
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(bytesA, greaterThan(0));

      // …zap vers « France 3 » : playUrlFor doit FERMER la session A.
      await relay.playUrlFor(urlB);
      await aClosed.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail(
            'la connexion de l\'ancienne chaîne doit être coupée au zap'),
      );
      expect(journal(), contains('session précédente fermée'));

      client.close(force: true);
      feedA?.cancel();
      feedB?.cancel();
      await srv.close(force: true);
    });

    test('REPRO terrain : 404 sur .ts mais 200 sur /live/….m3u8 → la '
        'lecture réussit via la cascade', () async {
      final List<Timer> feeds = <Timer>[];
      final HttpServer srv =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((HttpRequest req) async {
        if (req.uri.path == '/live/U/P/42.m3u8') {
          // La SEULE forme que ce panel accepte.
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType('video', 'mp2t');
          req.response.bufferOutput = false;
          final List<int> packet = List<int>.filled(188, 0x47);
          feeds.add(Timer.periodic(const Duration(milliseconds: 20), (_) {
            try {
              req.response.add(packet);
            } catch (_) {}
          }));
          return;
        }
        // Toutes les autres formes : 404 + page HTML (cas France 2).
        req.response.statusCode = 404;
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html>not found</html>');
        await req.response.close();
      });
      final String tsUrl = 'http://127.0.0.1:${srv.port}/U/P/42.ts';

      // 1) La cascade (même logique que _declareChannelBlocked) sonde
      //    les variantes dans l'ordre et trouve la gagnante.
      String? winner;
      for (final XtreamUrlCandidate c
          in XtreamUrlVariants.cascadeFor(tsUrl, XtreamContentType.live)) {
        final StreamProbeResult r = await StreamProbe.instance.probe(
          c.url,
          timeout: const Duration(seconds: 3),
          dnsRetries: 0,
        );
        if (r.success) {
          winner = c.url;
          break;
        }
      }
      expect(winner, isNotNull, reason: 'une variante doit répondre');
      expect(winner, endsWith('/live/U/P/42.m3u8'));

      // 2) Lecture RÉELLE via le relais sur la variante gagnante.
      final LocalStreamRelay relay = LocalStreamRelay.instance;
      final String localUrl = await relay.playUrlFor(winner!);
      final HttpClient client = HttpClient();
      final HttpClientResponse resp =
          await (await client.getUrl(Uri.parse(localUrl))).close();
      int bytes = 0;
      final StreamSubscription<List<int>> sub =
          resp.listen((List<int> c) => bytes += c.length);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(bytes, greaterThan(0),
          reason: 'la lecture doit réussir via la variante de la cascade');

      await sub.cancel();
      client.close(force: true);
      for (final Timer t in feeds) {
        t.cancel();
      }
      await srv.close(force: true);
    });
  });
}
