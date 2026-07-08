// =========================================================
//  hls_playback_test.dart — HLS : bypass du relais + sonde segments
// =========================================================
//  Bug terrain (après la victoire de la cascade) : la variante
//  live:m3u8 répondait 200 partout mais ÉCRAN NOIR — le relais TS
//  traitait la playlist HLS comme un flux continu et « reconnectait »
//  en boucle sur chaque EOF, servant à mpv du texte m3u8 concaténé.
//
//  Panel mocké complet, fidèle au terrain (thekung → lbsc…?token=…) :
//    /live/USER/PASS/42.m3u8  → 302 → /hls/master.m3u8?token=abc
//    master (token)           → media playlist relative (chunks.m3u8)
//    media  (token)           → 2 segments relatifs (seg0.ts, seg1.ts)
//    segments                 → octets TS (comptés)
//
//  On vérifie :
//    1. le RELAIS ne boucle plus : playlist servie UNE fois, session
//       fermée proprement, AUCUNE reconnexion sur du 200 ;
//    2. la sonde HLS (code de prod, celle que _openMedia lance au
//       bypass) suit redirection + token + master → media → segment et
//       journalise chaque étape — segments servis > 0 ;
//    3. isHlsUrl route correctement (bypass mpv vs relais TS).
//  Preuve : extrait du journal imprimé (livrable du rapport).
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/hls_preflight.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';

void main() {
  late HttpServer panel;
  late String m3u8Url;
  int playlistHits = 0;
  int segmentHits = 0;

  setUp(() async {
    playlistHits = 0;
    segmentHits = 0;
    panel = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    panel.listen((HttpRequest req) async {
      final String path = req.uri.path;
      final String token = req.uri.queryParameters['token'] ?? '';
      if (path == '/live/USER/PASS/42.m3u8') {
        // Redirection AVEC token — le schéma terrain (thekung → lbsc…).
        req.response.statusCode = 302;
        req.response.headers
            .set(HttpHeaders.locationHeader, '/hls/master.m3u8?token=abc');
        await req.response.close();
        return;
      }
      if (path == '/hls/master.m3u8') {
        playlistHits++;
        if (token != 'abc') {
          req.response.statusCode = 403;
          await req.response.close();
          return;
        }
        req.response.headers.contentType =
            ContentType.parse('application/x-mpegurl');
        req.response.write('#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\n'
            'chunks.m3u8?token=abc\n');
        await req.response.close();
        return;
      }
      if (path == '/hls/chunks.m3u8') {
        if (token != 'abc') {
          req.response.statusCode = 403;
          await req.response.close();
          return;
        }
        req.response.headers.contentType =
            ContentType.parse('application/x-mpegurl');
        req.response.write('#EXTM3U\n'
            '#EXT-X-TARGETDURATION:4\n'
            '#EXTINF:4.0,\nseg0.ts?token=abc\n'
            '#EXTINF:4.0,\nseg1.ts?token=abc\n');
        await req.response.close();
        return;
      }
      if (path == '/hls/seg0.ts' || path == '/hls/seg1.ts') {
        segmentHits++;
        req.response.headers.contentType = ContentType('video', 'mp2t');
        req.response.add(List<int>.filled(188 * 16, 0x47));
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });
    m3u8Url = 'http://127.0.0.1:${panel.port}/live/USER/PASS/42.m3u8';
  });

  tearDown(() async {
    await panel.close(force: true);
  });

  test('isHlsUrl : route HLS → direct mpv, TS → relais', () {
    expect(HlsPreflight.isHlsUrl('http://h/live/U/P/1.m3u8'), isTrue);
    expect(HlsPreflight.isHlsUrl('http://h/U/P/1.M3U8?token=x'), isTrue);
    expect(HlsPreflight.isHlsUrl('http://h/list.m3u'), isTrue);
    expect(HlsPreflight.isHlsUrl('http://h/live/U/P/1.ts'), isFalse);
    expect(HlsPreflight.isHlsUrl('http://h/U/P/9.mp4'), isFalse);
    expect(HlsPreflight.isHlsUrl('/data/local/rec.ts'), isFalse);
  });

  test('le RELAIS ne boucle PLUS sur une playlist HLS en 200 : servie '
      'une fois, session fermée, zéro reconnexion', () async {
    final LocalStreamRelay relay = LocalStreamRelay.instance;
    final String localUrl = await relay.playUrlFor(m3u8Url);
    final HttpClient client = HttpClient();
    final HttpClientResponse resp =
        await (await client.getUrl(Uri.parse(localUrl))).close();
    // Le relais sert le document puis FERME (EOF) — pas de blocage.
    await resp.drain<void>().timeout(const Duration(seconds: 5));

    // Fenêtre où l'ancien comportement re-téléchargeait la playlist en
    // boucle (reconnexion #1, #2… sur du 200) : le compteur du panel ne
    // doit PAS bouger.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(playlistHits, 1,
        reason: 'playlist = document : une seule requête, pas de boucle');
    expect(
      _journal(),
      contains('session fermée SANS reconnexion'),
      reason: 'la fermeture propre doit être tracée dans la boîte noire',
    );
    client.close(force: true);
  });

  test('sonde HLS (code de prod) : redirection + token + master → media '
      '→ segment, tout journalisé, segments servis > 0', () async {
    await HlsPreflight.run(m3u8Url);

    expect(segmentHits, greaterThan(0),
        reason: 'le 1er segment doit être atteint (token conservé)');
    final String journal = _journal();
    expect(journal, contains('HTTP 200'),
        reason: 'les statuts des playlists doivent apparaître');
    expect(journal, contains('redirection'),
        reason: 'la redirection tokenisée doit être visible');
    expect(journal, contains('2 segment(s) annoncé(s)'),
        reason: 'le contenu de la media playlist doit être visible');
    expect(journal, contains('Segment 1'),
        reason: 'le statut du 1er segment doit être visible');
    expect(journal, isNot(contains('USER/PASS')),
        reason: 'identifiants toujours masqués');

    // ----- LIVRABLE : extrait du journal (rapport) -----
    // ignore: avoid_print
    print('===== EXTRAIT JOURNAL (test HLS) =====');
    for (final StreamDiagEvent e
        in StreamDiagnostics.instance.events.toList().reversed) {
      // ignore: avoid_print
      print(e.toString());
    }
    // ignore: avoid_print
    print('===== FIN EXTRAIT =====');
  });
}

String _journal() => StreamDiagnostics.instance.events
    .map((StreamDiagEvent e) => e.message)
    .join('\n');
