// =========================================================
//  hls_normalizer_test.dart — Réparation des playlists de panel
// =========================================================
//  Cause racine terrain : mpv log « Reading plaintext playlist » puis
//  « Failed to recognize file format » alors que les segments sont du
//  TS valide — la playlist du panel n'a pas #EXTM3U en position 0
//  (BOM/CRLF/blancs, voire balise absente).
//
//  1. Tests UNITAIRES du normaliseur pur (BOM, CR, #EXTM3U ajouté,
//     URIs absolues, master réécrite vers la route locale, clés AES
//     laissées en direct).
//  2. Test d'INTÉGRATION sur le vrai chemin : panel mocké servant une
//     playlist SANS #EXTM3U (+ BOM + CRLF) et 2 segments TS valides →
//     la route /hls du relais la répare → un client (rôle de mpv) lit
//     la playlist locale réparée puis télécharge un segment : octets
//     TS (0x47) reçus > 0. NB : les frames elles-mêmes exigent libmpv,
//     indisponible sous test — on prouve ici que mpv reçoit désormais
//     un document HLS VALIDE et des octets TS valides, ce qui était
//     exactement ce qui manquait (« plaintext playlist »).
//  Preuve : extrait du journal imprimé (livrable du rapport).
// =========================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/player/data/hls_playlist_normalizer.dart';
import 'package:tv_king/features/player/data/local_stream_relay.dart';
import 'package:tv_king/features/player/data/stream_diagnostics.dart';

void main() {
  group('HlsPlaylistNormalizer (pur)', () {
    final Uri base = Uri.parse('http://cdn.tv/hls/chunks.m3u8?token=abc');
    String noRewrite(String abs) => abs;

    test('BOM + CRLF + #EXTM3U absent → réparée, preuves lisibles', () {
      const String raw =
          '﻿\r\n#EXT-X-TARGETDURATION:4\r\n#EXTINF:4.0,\r\nseg0.ts\r\n';
      final NormalizedPlaylist n = HlsPlaylistNormalizer.normalize(
        raw,
        base,
        rewriteSubPlaylist: noRewrite,
      );
      expect(n.text, startsWith('#EXTM3U\n'),
          reason: '#EXTM3U doit être garanti en position 0');
      expect(n.hadExtM3uAtStart, isFalse);
      expect(n.repairs.join(' ; '), contains('#EXTM3U AJOUTÉ'));
      expect(n.repairs.join(' ; '), contains('BOM'));
      expect(n.rawHead, contains('⟨BOM⟩'));
      expect(n.rawHead, contains('⟨CR⟩'));
      expect(n.text, contains('http://cdn.tv/hls/seg0.ts'),
          reason: 'les segments doivent être ABSOLUS (direct CDN)');
    });

    test('playlist saine → aucune réparation, segments absolutisés', () {
      const String raw = '#EXTM3U\n#EXTINF:4.0,\nseg0.ts?token=abc\n';
      final NormalizedPlaylist n = HlsPlaylistNormalizer.normalize(
        raw,
        base,
        rewriteSubPlaylist: noRewrite,
      );
      expect(n.hadExtM3uAtStart, isTrue);
      expect(n.repairs, isEmpty);
      expect(n.text, contains('http://cdn.tv/hls/seg0.ts?token=abc'));
    });

    test('master : sous-playlists → route locale ; #EXT-X-MEDIA aussi ; '
        '#EXT-X-KEY reste en direct', () {
      const String raw = '#EXTM3U\n'
          '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",URI="audio.m3u8"\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2000000\n'
          'chunks.m3u8?token=abc\n';
      final NormalizedPlaylist n = HlsPlaylistNormalizer.normalize(
        raw,
        Uri.parse('http://cdn.tv/hls/master.m3u8?token=abc'),
        rewriteSubPlaylist: (String abs) =>
            'http://127.0.0.1:9/hls?u=${Uri.encodeComponent(abs)}',
      );
      expect(n.isMaster, isTrue);
      expect(n.text, contains('http://127.0.0.1:9/hls?u='),
          reason: 'la media playlist doit repasser par la normalisation');
      expect(
          n.text,
          contains(Uri.encodeComponent(
              'http://cdn.tv/hls/chunks.m3u8?token=abc')));
      expect(n.text, contains('URI="http://127.0.0.1:9/hls?u='),
          reason: 'les pistes #EXT-X-MEDIA aussi');
      expect(n.text, contains('URI="http://cdn.tv/hls/key.bin"'),
          reason: 'les clés AES restent en DIRECT (absolutisées)');
    });
  });

  test(
      'INTÉGRATION : playlist de panel SANS #EXTM3U + segments TS valides '
      '→ la route /hls répare → « mpv » lit la playlist réparée et reçoit '
      'des octets TS', () async {
    int upstreamPlaylistHits = 0;
    final HttpServer panel =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    panel.listen((HttpRequest req) async {
      if (req.uri.path == '/hls/chunks.m3u8') {
        upstreamPlaylistHits++;
        req.response.headers.contentType =
            ContentType.parse('application/x-mpegurl');
        // LE document du terrain : BOM + CRLF + PAS de #EXTM3U.
        // (add + utf8.encode : write() encoderait en Latin-1 qui ne
        // sait pas représenter le BOM U+FEFF.)
        req.response.add(utf8.encode(
            '﻿\r\n#EXT-X-TARGETDURATION:4\r\n#EXTINF:4.0,\r\n'
            'seg0.ts?token=abc\r\n#EXTINF:4.0,\r\nseg1.ts?token=abc\r\n'));
        await req.response.close();
        return;
      }
      if (req.uri.path.endsWith('.ts')) {
        req.response.headers.contentType = ContentType('video', 'mp2t');
        req.response.add(List<int>.filled(188 * 16, 0x47));
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });
    final String upstream =
        'http://127.0.0.1:${panel.port}/hls/chunks.m3u8?token=abc';

    // ----- La route de normalisation (celle que _openMedia donne à mpv).
    final LocalStreamRelay relay = LocalStreamRelay.instance;
    final String localUrl = await relay.hlsPlaylistUrlFor(upstream);

    // ----- « mpv » télécharge la playlist locale réparée.
    final HttpClient client = HttpClient();
    HttpClientResponse resp =
        await (await client.getUrl(Uri.parse(localUrl))).close();
    expect(resp.headers.contentType?.mimeType,
        'application/vnd.apple.mpegurl');
    final String served = await resp.transform(utf8.decoder).join();
    expect(served, startsWith('#EXTM3U\n'),
        reason: 'mpv doit recevoir #EXTM3U en position 0 — fini le '
            '« plaintext playlist »');
    expect(served, isNot(contains('\r')));
    expect(served, isNot(contains('﻿')));

    // ----- « mpv » télécharge le 1er segment (URI ABSOLUE, direct CDN).
    final String segUrl = served
        .split('\n')
        .firstWhere((String l) => l.isNotEmpty && !l.startsWith('#'));
    expect(segUrl, startsWith('http://127.0.0.1:${panel.port}/hls/seg0.ts'),
        reason: 'les segments doivent être absolus vers le CDN');
    resp = await (await client.getUrl(Uri.parse(segUrl))).close();
    int bytes = 0;
    int? firstByte;
    await for (final List<int> c in resp) {
      firstByte ??= c.isEmpty ? null : c.first;
      bytes += c.length;
    }
    expect(bytes, greaterThan(0),
        reason: 'des octets vidéo doivent couler (frames côté mpv)');
    expect(firstByte, 0x47, reason: 'sync TS 0x47 = contenu décodable');

    // ----- Rafraîchissement LIVE : chaque poll de mpv re-télécharge
    //       la playlist amont fraîche.
    await (await client.getUrl(Uri.parse(localUrl))).close().then(
        (HttpClientResponse r) => r.drain<void>());
    expect(upstreamPlaylistHits, 2,
        reason: 'chaque poll mpv = playlist amont re-téléchargée');

    // ----- Preuves journal (mission) -----
    final String journal = StreamDiagnostics.instance.events
        .map((StreamDiagEvent e) => e.message)
        .join('\n');
    expect(journal, contains('3 premières lignes BRUTES'),
        reason: 'la preuve brute doit être journalisée');
    expect(journal, contains('#EXTM3U AJOUTÉ'),
        reason: 'la réparation doit être explicite');

    // ----- LIVRABLE : extrait du journal (rapport) -----
    // ignore: avoid_print
    print('===== EXTRAIT JOURNAL (test normalisation HLS) =====');
    for (final StreamDiagEvent e
        in StreamDiagnostics.instance.events.toList().reversed) {
      // ignore: avoid_print
      print(e.toString());
    }
    // ignore: avoid_print
    print('===== FIN EXTRAIT =====');

    client.close(force: true);
    await panel.close(force: true);
  });
}
