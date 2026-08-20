// =========================================================
//  relay_handover_linger_test.dart — Passation aperçu → plein écran
// =========================================================
//  Terrain 20/08 (« je quitte le cinéma, j'ouvre une chaîne → limite
//  1/1 », modèle IBO demandé par l'exploitant) : quand le dernier lecteur
//  se débranche de la chaîne COURANTE, le relais garde l'amont ouvert
//  quelques secondes — le lecteur suivant de la MÊME chaîne (aperçu promu
//  en plein écran) se rebranche sur la MÊME connexion panel au lieu d'en
//  rouvrir une. Une ligne 1-connexion ne voit donc UNE seule session.
//
//  Et la garantie inverse reste entière : une fermeture VOLONTAIRE
//  (closeOtherPlaybacks — zap, sortie d'écran) rend la connexion TOUT DE
//  SUITE, sans sursis.
// =========================================================

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';
import 'package:tv_king/features/player/data/ts_stream_conditioner.dart';

void main() {
  late HttpServer fakeUpstream;
  late String fakeUrl;
  int upstreamHits = 0;
  final List<Timer> feeds = <Timer>[];

  final Uint8List packet = () {
    final Uint8List out = Uint8List(kTsPacketSize);
    out[0] = kTsSyncByte;
    for (int i = 1; i < kTsPacketSize; i++) {
      out[i] = i & 0x3f;
    }
    return out;
  }();

  setUp(() async {
    upstreamHits = 0;
    fakeUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fakeUrl = 'http://127.0.0.1:${fakeUpstream.port}/USER/PASS/7.ts';
    fakeUpstream.listen((HttpRequest req) {
      upstreamHits++;
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType('video', 'mp2t');
      req.response.bufferOutput = false;
      // Flux « live » continu : des paquets TS toutes les 20 ms.
      feeds.add(Timer.periodic(const Duration(milliseconds: 20), (_) {
        try {
          req.response.add(packet);
        } catch (_) {
          // le client est parti — le timer sera annulé au tearDown.
        }
      }));
    });
  });

  tearDown(() async {
    await LocalStreamRelay.instance.closeOtherPlaybacks('');
    for (final Timer t in feeds) {
      t.cancel();
    }
    feeds.clear();
    await fakeUpstream.close(force: true);
  });

  /// Se branche sur [localUrl], lit quelques octets, puis se débranche.
  Future<void> playBriefly(String localUrl) async {
    final HttpClient client = HttpClient();
    final HttpClientResponse resp =
        await (await client.getUrl(Uri.parse(localUrl))).close();
    final Completer<void> gotBytes = Completer<void>();
    final StreamSubscription<List<int>> sub = resp.listen((List<int> b) {
      if (!gotBytes.isCompleted) gotBytes.complete();
    });
    await gotBytes.future.timeout(const Duration(seconds: 5));
    await sub.cancel();
    client.close(force: true);
  }

  test(
      'PASSATION : se re-brancher sur la même chaîne pendant le sursis '
      'réutilise la MÊME connexion amont (une seule session panel)', () async {
    final LocalStreamRelay relay = LocalStreamRelay.instance;
    final String localUrl = await relay.playUrlFor(fakeUrl);

    await playBriefly(localUrl); // 1er lecteur (l'« aperçu ») part…
    // …le temps de la passation (bien en-dessous du sursis de 5 s)…
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await playBriefly(localUrl); // …le « plein écran » se branche.

    expect(upstreamHits, 1,
        reason: 'le relais doit garder l\'amont ouvert pendant la '
            'passation — pas de 2e connexion panel pour la même chaîne');
  });

  test(
      'FERMETURE VOLONTAIRE : closeOtherPlaybacks rend la connexion tout '
      'de suite, sans attendre le sursis', () async {
    final LocalStreamRelay relay = LocalStreamRelay.instance;
    final String localUrl = await relay.playUrlFor(fakeUrl);
    await playBriefly(localUrl);

    await relay.closeOtherPlaybacks('');
    expect(relay.activeUpstreamCount, 0,
        reason: 'quitter la lecture doit fermer l\'amont immédiatement '
            '(garantie « 0/1 au repos » mesurée le 19/08)');
  });
}
