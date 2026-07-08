// =========================================================
//  hls_preflight.dart — Détection HLS + sonde de diagnostic segments
// =========================================================
//  BUG TERRAIN (2026-07-08, après la victoire de la cascade) : la
//  variante `live:m3u8` répondait 200 · application/x-mpegurl partout,
//  MAIS écran noir + relais en boucle « reconnexion » sur du 200.
//  Cause : LocalStreamRelay est un tuyau d'OCTETS TS CONTINUS — une
//  playlist HLS est un DOCUMENT court : le relais la servait comme un
//  flux, voyait l'EOF, « reconnectait », re-servait la playlist… mpv
//  recevait du texte m3u8 concaténé imparsable → 0 frame.
//
//  Décision (Option A de la mission) : le HLS BYPASSE le relais — mpv
//  gère nativement master/media playlists, segments, redirections et
//  tokens, avec le User-Agent déjà configuré. Le relais reste le moteur
//  des flux TS continus (et de l'enregistrement 1-connexion).
//
//  Ce fichier fournit :
//    - [isHlsUrl] : la détection utilisée par le lecteur pour router ;
//    - [run]      : une sonde DIAGNOSTIC fire-and-forget (≤ 4 requêtes,
//      lecture seule, jamais bloquante) qui trace dans StreamDiagnostics
//      ce que mpv va rencontrer : playlist maître (variantes), media
//      playlist (nb de segments) et statut HTTP du 1er segment — token
//      et redirections compris. C'est la visibilité « segments »
//      demandée par la mission, sans se mettre dans le chemin des octets.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/net/doh_resolver.dart';
import 'player_settings.dart';
import 'stream_diagnostics.dart';

class HlsPreflight {
  HlsPreflight._();

  /// Timeout par requête de la sonde (diagnostic best-effort).
  static const Duration kTimeout = Duration(milliseconds: 2500);

  /// `true` si [url] désigne une playlist HLS (`.m3u8`/`.m3u`, query
  /// ignorée) → lecture DIRECTE par mpv, jamais via le relais TS.
  static bool isHlsUrl(String url) {
    final Uri? u = Uri.tryParse(url.trim());
    final String path = (u?.path ?? url).toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.m3u');
  }

  static void _log(String message, {String level = 'info'}) =>
      StreamDiagnostics.instance.recordEvent('hls', message, level: level);

  /// Résout la chaîne de redirections d'une playlist (panel → CDN
  /// tokenisé) et renvoie l'URL FINALE — celle qu'il faut donner à mpv
  /// pour que les URIs RELATIVES des segments se résolvent contre la
  /// bonne base (et que le token soit dans l'URL de travail). Renvoie
  /// `null` en cas d'échec (l'appelant garde l'URL d'origine).
  static Future<String?> resolveFinalPlaylistUrl(String url) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = kTimeout
      ..userAgent = PlayerSettings.instance.userAgent
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);
    installDohResolution(client); // DNS FAI bloqué → DoH
    try {
      final HttpClientRequest req =
          await client.getUrl(Uri.parse(url)).timeout(kTimeout);
      req.followRedirects = true;
      req.maxRedirects = 8;
      final HttpClientResponse resp = await req.close().timeout(kTimeout);
      await resp.listen(null, cancelOnError: true).cancel();
      if (resp.statusCode >= 400) return null;
      if (resp.redirects.isEmpty) return url;
      return Uri.parse(url)
          .resolveUri(resp.redirects.last.location)
          .toString();
    } catch (e) {
      _log('Résolution de redirection impossible : $e', level: 'warn');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Sonde de DIAGNOSTIC (fire-and-forget) : suit la chaîne
  /// playlist → (master ?) → media playlist → 1er segment, en suivant
  /// les redirections et en préservant les query/tokens, et journalise
  /// chaque étape. N'influence JAMAIS la lecture (mpv fait la sienne en
  /// parallèle) ; toute erreur est journalisée puis avalée.
  static Future<void> run(String url) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = kTimeout
      ..userAgent = PlayerSettings.instance.userAgent
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);
    installDohResolution(client); // DNS FAI bloqué → DoH
    try {
      // ----- 1. Playlist telle que le lecteur l'ouvre -----
      final _Fetched? first = await _fetchText(client, url);
      if (first == null) return; // déjà journalisé
      if (!first.body.trimLeft().startsWith('#EXTM3U')) {
        _log(
          'La réponse n\'est PAS une playlist HLS (#EXTM3U absent) — '
              'mime ${first.mime ?? '?'}',
          level: 'warn',
        );
        return;
      }

      // ----- 2. Master → media playlist (URI résolue, token conservé) --
      _Fetched media = first;
      final String? variantUri = _firstUriAfter(first.body, '#EXT-X-STREAM-INF');
      if (variantUri != null) {
        final String mediaUrl =
            first.finalUri.resolve(variantUri).toString();
        _log('Playlist MAÎTRE (${'variante(s) : '
            '${RegExp('#EXT-X-STREAM-INF').allMatches(first.body).length}'}) '
            '→ media playlist '
            '${StreamDiagnostics.maskCredentials(mediaUrl)}');
        final _Fetched? m = await _fetchText(client, mediaUrl);
        if (m == null) return;
        media = m;
      }

      // ----- 3. Segments -----
      final List<String> segments = media.body
          .split('\n')
          .map((String l) => l.trim())
          .where((String l) => l.isNotEmpty && !l.startsWith('#'))
          .toList(growable: false);
      _log('Media playlist : ${segments.length} segment(s) annoncé(s)'
          '${segments.isEmpty ? ' — PLAYLIST VIDE (cause classique '
              'd\'écran noir)' : ''}');
      if (segments.isEmpty) return;

      // SIGNATURE BINAIRE du 1er segment, téléchargé avec LES MÊMES
      // en-têtes que mpv (même User-Agent — ffmpeg propage `user-agent`
      // aux sous-requêtes HLS). Un TS valide commence par 0x47 ; un
      // fMP4 par « ....ftyp » ; « <htm » = page d'erreur DÉGUISÉE en
      // 200 (le serveur filtre les segments) — indétectable autrement.
      final String segUrl =
          media.finalUri.resolve(segments.first).toString();
      final HttpClientRequest req =
          await client.getUrl(Uri.parse(segUrl)).timeout(kTimeout);
      req.followRedirects = true;
      req.headers.add(HttpHeaders.rangeHeader, 'bytes=0-4095');
      final HttpClientResponse resp = await req.close().timeout(kTimeout);
      final int status = resp.statusCode;
      final List<int> head = <int>[];
      final Completer<void> firstChunk = Completer<void>();
      final StreamSubscription<List<int>> sub = resp.listen(
        (List<int> c) {
          head.addAll(c);
          if (!firstChunk.isCompleted) firstChunk.complete();
        },
        onDone: () {
          if (!firstChunk.isCompleted) firstChunk.complete();
        },
        onError: (Object _) {
          if (!firstChunk.isCompleted) firstChunk.complete();
        },
        cancelOnError: true,
      );
      await firstChunk.future.timeout(kTimeout, onTimeout: () {});
      await sub.cancel();
      final String hex = head
          .take(4)
          .map((int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      final String ascii = String.fromCharCodes(
          head.take(16).where((int b) => b >= 0x20 && b < 0x7F));
      final String verdict;
      if (head.isEmpty) {
        verdict = 'AUCUN OCTET reçu';
      } else if (head.first == 0x47) {
        verdict = 'TS VALIDE (sync 0x47)';
      } else if (head.length >= 8 &&
          String.fromCharCodes(head.sublist(4, 8)) == 'ftyp') {
        verdict = 'fMP4 VALIDE (ftyp)';
      } else if (ascii.toLowerCase().contains('<htm') ||
          ascii.trimLeft().startsWith('{')) {
        verdict = 'PAGE D\'ERREUR DÉGUISÉE EN $status '
            '(« $ascii » — le serveur filtre les segments : '
            'signature/UA/token ?)';
      } else {
        verdict = 'signature inconnue (« $ascii »)';
      }
      final bool healthy = status < 400 &&
          head.isNotEmpty &&
          (head.first == 0x47 || verdict.startsWith('fMP4'));
      _log(
        'Segment 1 (${StreamDiagnostics.maskCredentials(segUrl)}) → '
            'HTTP $status · ${head.length} octet(s) · '
            '4 premiers octets: ${hex.isEmpty ? '—' : hex} → $verdict '
            '(UA "${PlayerSettings.instance.userAgent}")',
        level: healthy ? 'info' : 'error',
      );
    } catch (e) {
      _log('Sonde HLS interrompue : $e', level: 'warn');
      if (kDebugMode) debugPrint('[HlsPreflight] $e');
    } finally {
      client.close(force: true);
    }
  }

  /// Première URI (ligne non-commentaire) qui suit une ligne commençant
  /// par [directive], ou `null`.
  static String? _firstUriAfter(String playlist, String directive) {
    final List<String> lines = playlist.split('\n');
    for (int i = 0; i < lines.length - 1; i++) {
      if (lines[i].trim().startsWith(directive)) {
        for (int j = i + 1; j < lines.length; j++) {
          final String l = lines[j].trim();
          if (l.isNotEmpty && !l.startsWith('#')) return l;
        }
      }
    }
    return null;
  }

  static Future<_Fetched?> _fetchText(HttpClient client, String url) async {
    try {
      final HttpClientRequest req =
          await client.getUrl(Uri.parse(url)).timeout(kTimeout);
      req.followRedirects = true;
      req.maxRedirects = 8;
      final HttpClientResponse resp = await req.close().timeout(kTimeout);
      // `location` peut être RELATIVE : on la résout contre l'URL de
      // départ (c'est contre la finale que les URIs de segments se
      // résolvent ensuite — token conservé).
      final Uri finalUri = resp.redirects.isEmpty
          ? Uri.parse(url)
          : Uri.parse(url).resolveUri(resp.redirects.last.location);
      final String body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(kTimeout);
      _log(
        'Playlist ${StreamDiagnostics.maskCredentials(url)} → '
            'HTTP ${resp.statusCode}'
            '${resp.redirects.isEmpty ? '' : ' (via ${resp.redirects.length} redirection(s) → ${StreamDiagnostics.maskCredentials(finalUri.toString())})'}',
        level: resp.statusCode < 400 ? 'info' : 'error',
      );
      if (resp.statusCode >= 400) return null;
      return _Fetched(
        body: body,
        finalUri: finalUri,
        mime: resp.headers.contentType?.mimeType,
      );
    } catch (e) {
      _log('Playlist ${StreamDiagnostics.maskCredentials(url)} → $e',
          level: 'error');
      return null;
    }
  }
}

class _Fetched {
  const _Fetched({required this.body, required this.finalUri, this.mime});
  final String body;
  final Uri finalUri;
  final String? mime;
}
