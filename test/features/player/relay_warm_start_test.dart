// =========================================================
//  relay_warm_start_test.dart — Démarrage à chaud du relais
// =========================================================
//  La promesse : quand un lecteur se (RE)branche sur une session qui a
//  déjà diffusé (re-préparation ExoPlayer après un gel, retry silencieux),
//  le relais lui envoie IMMÉDIATEMENT la mémoire des derniers octets
//  (alignée sur une frontière de paquet TS) — il n'attend pas le fil de
//  l'eau du serveur. C'est ce qui fait revenir l'image en une fraction de
//  seconde au lieu de 1-3 s d'écran noir.
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

  /// 10 paquets TS valides envoyés d'un coup, puis PLUS RIEN : la seule
  /// façon pour un 2e lecteur de recevoir des octets est le burst mémoire.
  final Uint8List tenPackets = () {
    final Uint8List out = Uint8List(10 * kTsPacketSize);
    for (int p = 0; p < 10; p++) {
      out[p * kTsPacketSize] = kTsSyncByte;
      for (int i = 1; i < kTsPacketSize; i++) {
        out[p * kTsPacketSize + i] = (p + i) & 0x3f; // jamais 0x47
      }
    }
    return out;
  }();

  setUp(() async {
    fakeUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fakeUrl = 'http://127.0.0.1:${fakeUpstream.port}/warm';
    fakeUpstream.listen((HttpRequest req) {
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType('video', 'mp2t');
      req.response.bufferOutput = false;
      req.response.add(tenPackets);
      // On ne ferme PAS (flux live "silencieux") : pas d'EOF, pas de
      // reconnexion — et surtout aucune nouvelle donnée fraîche.
    });
  });

  tearDown(() async {
    await fakeUpstream.close(force: true);
  });

  test(
      'un 2e lecteur qui se branche reçoit IMMÉDIATEMENT la mémoire du flux '
      '(burst aligné), sans attendre de nouvelles données du serveur',
      () async {
    final LocalStreamRelay relay = LocalStreamRelay.instance;
    final String localUrl = await relay.playUrlFor(fakeUrl);

    // Lecteur n°1 : amorce la session et reçoit les 10 paquets.
    final HttpClient c1 = HttpClient();
    final HttpClientResponse r1 =
        await (await c1.getUrl(Uri.parse(localUrl))).close();
    final List<int> got1 = <int>[];
    final StreamSubscription<List<int>> s1 =
        r1.listen((List<int> chunk) => got1.addAll(chunk));
    // Attente ACTIVE bornée (pas de durée magique fragile).
    final DateTime deadline1 = DateTime.now().add(const Duration(seconds: 5));
    while (got1.length < tenPackets.length &&
        DateTime.now().isBefore(deadline1)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(got1.length, tenPackets.length,
        reason: 'le 1er lecteur doit recevoir tout le flux');

    // Lecteur n°2 (= ExoPlayer qui re-prépare après un gel) : le serveur
    // n'enverra PLUS RIEN — seuls les octets du burst mémoire peuvent
    // arriver.
    final HttpClient c2 = HttpClient();
    final HttpClientResponse r2 =
        await (await c2.getUrl(Uri.parse(localUrl))).close();
    final List<int> got2 = <int>[];
    final StreamSubscription<List<int>> s2 =
        r2.listen((List<int> chunk) => got2.addAll(chunk));
    final DateTime deadline2 = DateTime.now().add(const Duration(seconds: 3));
    while (got2.length < tenPackets.length &&
        DateTime.now().isBefore(deadline2)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    expect(got2, isNotEmpty,
        reason: 'le burst mémoire doit alimenter le lecteur re-branché');
    // Aligné : ça commence sur un octet de synchronisation TS.
    expect(got2.first, kTsSyncByte);
    // Et c'est bien le contenu du flux (la mémoire, pas du bruit).
    expect(got2, tenPackets);

    await s1.cancel();
    await s2.cancel();
    c1.close(force: true);
    c2.close(force: true);
    relay.closeOtherPlaybacks('__rien__'); // nettoie la session du test
  });
}
