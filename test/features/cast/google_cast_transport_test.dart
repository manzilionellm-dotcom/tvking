// =========================================================
//  google_cast_transport_test.dart — Bugs A & B
// =========================================================
//  Vérifie les décisions PURES du transport Chromecast :
//    - isHlsOrDash : ne wrappe pas un flux déjà adaptatif ;
//    - isExoPlayerReceiver : SHIELD lit le .ts direct ;
//    - sameSubnet : la TV doit joindre le serveur HLS local.
// =========================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/google_cast_transport.dart';
import 'package:tv_king/features/cast/domain/cast_device.dart';

CastDevice _dev({String name = 'TV', String? model, String? manuf}) =>
    CastDevice(
      id: 'x',
      name: name,
      kind: CastDeviceKind.chromecast,
      host: '192.168.1.20',
      port: 8009,
      controlUrl: '',
      manufacturer: manuf,
      model: model,
    );

void main() {
  group('isHlsOrDash (BUG A)', () {
    test('HLS / DASH → adaptatif (pas de wrap)', () {
      expect(GoogleCastTransport.isHlsOrDash('http://x/live.m3u8'), isTrue);
      expect(GoogleCastTransport.isHlsOrDash('http://x/v.mpd'), isTrue);
    });
    test('MPEG-TS / sans extension → non adaptatif (wrap)', () {
      expect(GoogleCastTransport.isHlsOrDash('http://x/live/u/p/12.ts'), isFalse);
      expect(GoogleCastTransport.isHlsOrDash('http://x/live/u/p/12'), isFalse);
    });
  });

  group('isExoPlayerReceiver (BUG A)', () {
    test('SHIELD → ExoPlayer (direct OK)', () {
      expect(GoogleCastTransport.isExoPlayerReceiver(_dev(model: 'SHIELD')), isTrue);
      expect(
          GoogleCastTransport.isExoPlayerReceiver(_dev(manuf: 'NVIDIA')), isTrue);
    });
    test('Chromecast pur → wrap par défaut', () {
      expect(
          GoogleCastTransport.isExoPlayerReceiver(_dev(name: 'Chambre')), isFalse);
    });
  });

  group('receiverAppIdForCastPath (CAST_HANDOFF §6.2)', () {
    test('relais HLS téléphone (HTTP) → Default Media Receiver', () {
      // La page receiver custom est HTTPS : mpegts.js ne peut pas fetch un
      // relais HTTP (mixed content) → le repli passe par le Default Receiver
      // qui lit le HLS nativement.
      expect(
        GoogleCastTransport.receiverAppIdForCastPath('local_hls_relay'),
        kCastDefaultReceiverAppId,
      );
    });
    test('TV-direct (flux fournisseur HTTP) → Default Media Receiver', () {
      // Le chemin direct_tv (fluidité 2026-07-10) donne le flux HTTP du
      // fournisseur au player NATIF de la TV — même contrainte mixed
      // content que le relais : jamais la page receiver custom HTTPS.
      expect(
        GoogleCastTransport.receiverAppIdForCastPath('direct_tv'),
        kCastDefaultReceiverAppId,
      );
    });
    test('cast_proxy / direct → receiver custom (prioritaire)', () {
      expect(
        GoogleCastTransport.receiverAppIdForCastPath('cast_proxy'),
        kCastCustomReceiverAppId,
      );
      expect(
        GoogleCastTransport.receiverAppIdForCastPath('direct'),
        kCastCustomReceiverAppId,
      );
    });
    test('IDs alignés avec CastOptionsProviderImpl.kt', () {
      expect(kCastCustomReceiverAppId, '5BDFD969');
      expect(kCastDefaultReceiverAppId, 'CC1AD845');
    });
  });

  group('directTvCandidate (chemin TV-direct, fluidité 2026-07-10)', () {
    test('panel qui sert le m3u8 → variante HLS Xtream préférée', () async {
      final HttpServer panel =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      panel.listen((HttpRequest req) async {
        req.response.statusCode =
            req.uri.path.endsWith('.m3u8') ? 200 : 404;
        await req.response.close();
      });
      try {
        final GoogleCastTransport t = GoogleCastTransport(_dev());
        final String out = await t.directTvCandidate(
            'http://127.0.0.1:${panel.port}/live/u/p/42.ts');
        expect(out, 'http://127.0.0.1:${panel.port}/live/u/p/42.m3u8',
            reason: 'HLS = format live le plus robuste pour la TV');
      } finally {
        await panel.close(force: true);
      }
    });

    test('panel sans m3u8 (404) → .ts brut inchangé', () async {
      final HttpServer panel =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      panel.listen((HttpRequest req) async {
        req.response.statusCode = 404;
        await req.response.close();
      });
      try {
        final GoogleCastTransport t = GoogleCastTransport(_dev());
        final String url = 'http://127.0.0.1:${panel.port}/live/u/p/42.ts';
        expect(await t.directTvCandidate(url), url,
            reason: 'allowed_output_formats sans m3u8 → on ne casse rien');
      } finally {
        await panel.close(force: true);
      }
    });

    test('VOD (movie/series) → JAMAIS réécrit, aucune requête réseau',
        () async {
      // Port fermé : toute requête échouerait — le test prouve qu'aucune
      // n'est émise pour un préfixe VOD (règle xtream_url_variants).
      final ServerSocket probe =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final int deadPort = probe.port;
      await probe.close();
      final GoogleCastTransport t = GoogleCastTransport(_dev());
      final String vod = 'http://127.0.0.1:$deadPort/movie/u/p/9.mp4';
      expect(await t.directTvCandidate(vod), vod);
    });

    test('URL non-Xtream → telle quelle', () async {
      final GoogleCastTransport t = GoogleCastTransport(_dev());
      const String odd = 'http://cdn.example/stream/abc.ts';
      expect(await t.directTvCandidate(odd), odd,
          reason: 'schéma inconnu : ne jamais réécrire (règle variants)');
    });
  });

  group('sameSubnet (BUG B)', () {
    test('même /24 → joignable', () {
      expect(
        GoogleCastTransport.sameSubnet('http://192.168.1.5:8080/x.m3u8',
            '192.168.1.20'),
        isTrue,
      );
    });
    test('sous-réseaux différents → injoignable', () {
      expect(
        GoogleCastTransport.sameSubnet('http://192.168.1.5/x', '10.0.0.5'),
        isFalse,
      );
    });
    test('host non-IPv4 → on ne bloque pas (true)', () {
      expect(
        GoogleCastTransport.sameSubnet('http://monpc.local/x', 'tv.local'),
        isTrue,
      );
    });
  });
}
