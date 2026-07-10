// =========================================================
//  hls_relay_session_test.dart — Session HLS live du téléphone
// =========================================================
//  Vérifie le contrat que le Default Media Receiver (CAF/Shaka)
//  attend du relais (diag SHIELD 2026-07-09) :
//    - playlist LIVE glissante : MEDIA-SEQUENCE croissant, PAS de
//      #EXT-X-ENDLIST, EXTINF honnêtes ;
//    - segments FINIS servis avec leur taille connue ;
//    - reconnexion upstream (les serveurs Xtream coupent la socket
//      périodiquement) annoncée par #EXT-X-DISCONTINUITY ;
//    - upstream mort → erreur fatale propre (pas de boucle infinie) ;
//    - routes HTTP de LocalCastServer : CORS + MIME sur playlist ET
//      segments (sans CORS, Shaka échoue avant toute décodage).
// =========================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/cast/data/dlna_profiles.dart';
import 'package:tv_king/features/cast/data/hls_relay_session.dart';
import 'package:tv_king/features/cast/data/local_cast_server.dart';

import 'ts_hls_segmenter_test.dart' show syntheticStream;

/// Faux serveur IPTV : 1re connexion = 20 s de TS puis coupure
/// (comportement Xtream typique), 2e connexion = 7 s avec une AUTRE
/// horloge PCR, connexions suivantes = 200 vide.
Future<HttpServer> fakeUpstream() async {
  final HttpServer server =
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  int connections = 0;
  server.listen((HttpRequest req) async {
    connections++;
    req.response.headers.set('Content-Type', 'video/mp2t');
    if (connections == 1) {
      req.response.add(syntheticStream(seconds: 20.0, startPcr: 10.0));
    } else if (connections == 2) {
      req.response.add(syntheticStream(seconds: 7.0, startPcr: 500.0));
    }
    await req.response.close();
  });
  return server;
}

void main() {
  group('HlsRelaySession', () {
    test('playlist live glissante + discontinuité à la reconnexion',
        () async {
      final HttpServer upstream = await fakeUpstream();
      final HlsRelaySession session = HlsRelaySession(
        upstreamUrl: 'http://127.0.0.1:${upstream.port}/live/x/y/1.ts',
        userAgent: 'test',
      );
      session.start();
      try {
        // Burst 1 (20 s → ~7 segments) + burst 2 (7 s → ~2-3) : on
        // attend d'avoir vu les deux connexions. NB : la rétention
        // plafonne _segments à kRetention (8) — on attend donc 8, pas
        // le total publié.
        final bool ready = await session.waitForSegments(
            HlsRelaySession.kRetention, const Duration(seconds: 20));
        expect(ready, isTrue,
            reason: 'les 2 connexions upstream doivent produire assez de '
                'segments (erreur: ${session.fatalError})');
        expect(session.videoCodec, 'h264');

        final String playlist = session.playlist(segmentUriPrefix: 'tok/');
        expect(playlist, contains('#EXTM3U'));
        expect(playlist, isNot(contains('#EXT-X-ENDLIST')),
            reason: 'playlist LIVE : jamais de ENDLIST');
        // Anti-découpage : join épinglé ~8 s derrière le bord live
        // (RFC 8216bis HOLD-BACK) — la fenêtre pleine (~17 s) permet la
        // cible entière.
        expect(playlist, contains('#EXT-X-START:TIME-OFFSET=-10.0'),
            reason: 'sans recul de join, chaque à-coup WiFi = coupure');
        expect(await session.waitForBufferedSeconds(8.0, Duration.zero),
            isTrue,
            reason: 'le coussin est déjà là → réponse immédiate');
        expect(playlist, contains('#EXT-X-DISCONTINUITY\n'),
            reason: 'saut de PCR à la reconnexion → doit être annoncé '
                '(le tag inline, pas seulement DISCONTINUITY-SEQUENCE)');
        // Fenêtre glissante : le 1er segment listé n'est plus le 0.
        final RegExp seqRe = RegExp(r'#EXT-X-MEDIA-SEQUENCE:(\d+)');
        final int mediaSeq =
            int.parse(seqRe.firstMatch(playlist)!.group(1)!);
        expect(mediaSeq, greaterThan(0));
        // Les URIs pointent vers les segments retenus, et chaque
        // segment listé est réellement servable.
        final RegExp uriRe = RegExp(r'^tok/(\d+)\.ts$', multiLine: true);
        final List<RegExpMatch> uris = uriRe.allMatches(playlist).toList();
        expect(uris.length, inInclusiveRange(1, HlsRelaySession.kPlaylistWindow));
        for (final RegExpMatch m in uris) {
          final HlsLiveSegment? s = session.segment(int.parse(m.group(1)!));
          expect(s, isNotNull);
          expect(s!.bytes.length % 188, 0);
        }
      } finally {
        session.stop();
        await upstream.close(force: true);
      }
    });

    test('reconnexion avec PCR CONTINUE → transition sans discontinuité',
        () async {
      // Burst 1 : PCR 10→30 ; burst 2 : PCR reprend à 30.5 (même
      // encodeur, simple coupure de socket Xtream) → AUCUN
      // EXT-X-DISCONTINUITY ne doit apparaître (à-coup TV évité).
      final HttpServer upstream =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int connections = 0;
      upstream.listen((HttpRequest req) async {
        connections++;
        req.response.headers.set('Content-Type', 'video/mp2t');
        if (connections == 1) {
          req.response.add(syntheticStream(seconds: 20.0, startPcr: 10.0));
        } else if (connections == 2) {
          req.response.add(syntheticStream(seconds: 7.0, startPcr: 30.5));
        }
        await req.response.close();
      });
      final HlsRelaySession session = HlsRelaySession(
        upstreamUrl: 'http://127.0.0.1:${upstream.port}/live/x/y/1.ts',
        userAgent: 'test',
      );
      session.start();
      try {
        final bool ready = await session.waitForSegments(
            9, const Duration(seconds: 20));
        expect(ready, isTrue,
            reason: 'erreur: ${session.fatalError}');
        final String playlist = session.playlist(segmentUriPrefix: 'tok/');
        expect(playlist, isNot(contains('#EXT-X-DISCONTINUITY\n')),
            reason: 'PCR continue → pas de réinitialisation décodeur');
        expect(playlist, contains('#EXT-X-DISCONTINUITY-SEQUENCE:0'));
      } finally {
        session.stop();
        await upstream.close(force: true);
      }
    });

    test('upstream injoignable → erreur fatale propre', () async {
      // Port fermé : connexion refusée à chaque tentative.
      final ServerSocket probe =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final int deadPort = probe.port;
      await probe.close();
      final HlsRelaySession session = HlsRelaySession(
        upstreamUrl: 'http://127.0.0.1:$deadPort/live/x/y/1.ts',
        userAgent: 'test',
      );
      session.start();
      try {
        final bool ready = await session.waitForSegments(
            1, const Duration(seconds: 25));
        expect(ready, isFalse);
        expect(session.fatalError, isNotNull);
        expect(session.isStopped, isTrue);
      } finally {
        session.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 40)));
  });

  group('HlsRelaySession — coussin anti-découpage (startTimeOffsetFor)', () {
    test('cible 8 s, bornée par la matière disponible', () {
      // Fenêtre pleine (18 s) → recul cible entier.
      expect(HlsRelaySession.startTimeOffsetFor(18.0), 10.0);
      // Join précoce (9,5 s de matière) → tout ce que la fenêtre permet.
      expect(HlsRelaySession.startTimeOffsetFor(9.5), 7.5);
      expect(HlsRelaySession.startTimeOffsetFor(5.0), 3.0);
      // Trop peu de matière → pas de tag (le récepteur décide seul).
      expect(HlsRelaySession.startTimeOffsetFor(3.0), 0);
      expect(HlsRelaySession.startTimeOffsetFor(0.0), 0);
    });
  });

  group('CastManager.relayUpstreamUrlFor — tokens Xtream par-connexion', () {
    test('préfère l\'URL portail d\'origine, nettoyée des ? orphelins', () {
      expect(
        CastManager.relayUpstreamUrlFor(
          originalUrl: 'http://portail.example/user/pass/123.ts?',
          finalUrl: 'http://1.2.3.4/live/user/pass/123?token=perime',
        ),
        'http://portail.example/user/pass/123.ts',
      );
    });

    test('retombe sur finalUrl si l\'origine est vide ou invalide', () {
      expect(
        CastManager.relayUpstreamUrlFor(
          originalUrl: '  ',
          finalUrl: 'http://1.2.3.4/live/u/p/1',
        ),
        'http://1.2.3.4/live/u/p/1',
      );
    });
  });

  group('LocalCastServer — HEAD relais (sonde DLNA des TVs)', () {
    test('répond 200 + headers DLNA SANS contacter l\'upstream', () async {
      // Upstream qui compte les connexions : le HEAD de la TV ne doit
      // PAS lui coûter un token par-connexion (diag LG 2026-07-09).
      int upstreamHits = 0;
      final HttpServer upstream =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((HttpRequest req) async {
        upstreamHits++;
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      });
      final LocalCastServer server = LocalCastServer.instance;
      final String? url = await server.registerRelay(
        upstreamUrl: 'http://127.0.0.1:${upstream.port}/live/x/y/1.ts',
        profile: DlnaProfiles.select(url: 'http://x/1.ts', finalMime: null),
        receiverHost: '127.0.0.1',
      );
      if (url == null) {
        markTestSkipped('aucune IP LAN — environnement sans réseau');
        await upstream.close(force: true);
        return;
      }
      try {
        final Uri headUri = Uri.parse(url).replace(host: '127.0.0.1');
        final HttpClient client = HttpClient();
        final HttpClientRequest req = await client.openUrl('HEAD', headUri);
        final HttpClientResponse resp = await req.close();
        expect(resp.statusCode, 200);
        expect(resp.headers.value('contentFeatures.dlna.org'), isNotNull);
        expect(resp.headers.value('transferMode.dlna.org'), isNotNull);
        await resp.drain<void>();
        client.close(force: true);
        expect(upstreamHits, 0,
            reason: 'le HEAD ne doit consommer AUCUNE connexion upstream');
        server.clearRelay(url);
      } finally {
        await upstream.close(force: true);
        await server.stop();
      }
    });
  });

  group('LocalCastServer — routes /hls', () {
    test('playlist et segments servis avec CORS + bon MIME', () async {
      final HttpServer upstream = await fakeUpstream();
      final LocalCastServer server = LocalCastServer.instance;
      final String? url = await server.registerRelay(
        upstreamUrl: 'http://127.0.0.1:${upstream.port}/live/x/y/1.ts',
        profile: DlnaProfiles.select(url: 'http://x/1.ts', finalMime: null),
        receiverHost: '127.0.0.1',
        wrapInHls: true,
      );
      if (url == null) {
        // Pas d'interface IPv4 non-loopback sur cette machine de test.
        markTestSkipped('aucune IP LAN — environnement sans réseau');
        await upstream.close(force: true);
        return;
      }
      try {
        expect(url, endsWith('.m3u8'));
        // Le serveur bind 0.0.0.0 → joignable en loopback quel que
        // soit l'hôte annoncé dans l'URL.
        final Uri advertised = Uri.parse(url);
        final Uri playlistUri = advertised.replace(host: '127.0.0.1');
        final HttpClient client = HttpClient();
        final HttpClientRequest req = await client.getUrl(playlistUri);
        final HttpClientResponse resp = await req.close();
        expect(resp.statusCode, 200);
        expect(resp.headers.value('access-control-allow-origin'), '*',
            reason: 'sans CORS, Shaka rejette la playlist');
        expect(resp.headers.contentType.toString(),
            contains('mpegurl'));
        final String playlist = await resp.transform(utf8.decoder).join();
        expect(playlist, contains('#EXT-X-MEDIA-SEQUENCE'));
        expect(playlist, isNot(contains('#EXT-X-ENDLIST')));

        // Premier segment listé : URI relative <token>/<seq>.ts
        final RegExp uriRe = RegExp(r'^(\S+/\d+\.ts)$', multiLine: true);
        final String segPath = uriRe.firstMatch(playlist)!.group(1)!;
        final Uri segUri = playlistUri.resolve(segPath);
        final HttpClientResponse segResp =
            await (await client.getUrl(segUri)).close();
        expect(segResp.statusCode, 200);
        expect(segResp.headers.value('access-control-allow-origin'), '*',
            reason: 'sans CORS sur les SEGMENTS, échec « format non supporté »');
        expect(segResp.headers.contentType.toString(),
            contains('video/mp2t'));
        expect(segResp.headers.contentLength, greaterThan(0));
        final List<List<int>> chunks = await segResp.toList();
        final int total =
            chunks.fold<int>(0, (int a, List<int> c) => a + c.length);
        expect(total % 188, 0, reason: 'segment TS aligné');
        client.close(force: true);

        // Le debug info (utilisé dans les messages d'erreur du cast)
        // reflète le codec et ce que la « TV » a téléchargé.
        final String? info = server.hlsSessionDebugInfo(url);
        expect(info, isNotNull);
        expect(info, contains('codec=h264'));
        expect(info, contains('playlists servies=1'));
        expect(info, contains('segments servis=1'));

        // clearRelay arrête la session (plus de fetch upstream).
        server.clearRelay(url);
        expect(server.hlsSessionDebugInfo(url), isNull);
      } finally {
        await upstream.close(force: true);
        await server.stop();
      }
    });
  });
}
