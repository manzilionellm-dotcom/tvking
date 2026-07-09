// =========================================================
//  hls_relay_session.dart — Session HLS LIVE servie par le téléphone
// =========================================================
//  Moitié « réseau / playlist » du vrai relais HLS (la découpe TS est
//  dans ts_hls_segmenter.dart ; les routes HTTP dans
//  local_cast_server.dart).
//
//  Une session = une chaîne relayée vers UN récepteur Google Cast :
//    - le téléphone tire le flux .ts upstream (UA VLC, redirections
//      suivies, reconnexion auto quand le serveur IPTV coupe la
//      socket — comportement périodique NORMAL des serveurs Xtream) ;
//    - le segmenteur découpe en segments finis (~3 s) ;
//    - la session garde une FENÊTRE GLISSANTE de segments en RAM et
//      publie une playlist live conforme (MEDIA-SEQUENCE croissant,
//      DISCONTINUITY sur reconnexion, pas de ENDLIST).
//
//  C'est exactement ce que le Default Media Receiver (CAF/Shaka)
//  attend — contrairement à l'ancien « segment unique infini » qui ne
//  produisait JAMAIS une frame (le récepteur télécharge un segment en
//  entier avant de le décoder) et faisait échouer 100 % des casts
//  SHIELD (diag terrain 2026-07-09).
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ts_hls_segmenter.dart';

/// Segment publié dans la fenêtre live.
class HlsLiveSegment {
  HlsLiveSegment({
    required this.sequence,
    required this.bytes,
    required this.durationSec,
    required this.discontinuity,
  });

  final int sequence;
  final Uint8List bytes;
  final double durationSec;

  /// `true` si ce segment suit une reconnexion upstream : l'horloge
  /// PCR peut avoir sauté, la playlist doit l'annoncer
  /// (#EXT-X-DISCONTINUITY) sinon le récepteur décroche.
  final bool discontinuity;
}

class HlsRelaySession {
  HlsRelaySession({
    required this.upstreamUrl,
    required this.userAgent,
    TsHlsSegmenter Function()? segmenterFactory,
  }) : _segmenterFactory =
            segmenterFactory ?? (() => TsHlsSegmenter());

  final String upstreamUrl;
  final String userAgent;
  final TsHlsSegmenter Function() _segmenterFactory;

  /// Fenêtre annoncée dans la playlist (5 × ~3 s ≈ 15 s de live).
  static const int kPlaylistWindow = 5;

  /// Rétention mémoire : on garde quelques segments de plus que la
  /// playlist — le récepteur peut encore demander un segment qui vient
  /// de sortir de la fenêtre.
  static const int kRetention = 8;

  /// Reconnexions upstream avant abandon (compteur remis à zéro dès
  /// qu'une connexion a produit au moins un segment).
  static const int kMaxConsecutiveReconnects = 6;

  /// Sans AUCUNE requête du récepteur pendant ce délai, la session
  /// s'arrête seule (récepteur mort sans clearRelay → épargne
  /// batterie/data). Large : le récepteur met parfois >30 s à faire
  /// sa première requête (bascule de receiver + LOAD).
  static const Duration kIdleTimeout = Duration(seconds: 120);

  final List<HlsLiveSegment> _segments = <HlsLiveSegment>[];
  int _nextSequence = 0;
  int _discontinuitySequence = 0;
  bool _pendingDiscontinuity = false;

  TsHlsSegmenter _segmenter = TsHlsSegmenter();
  HttpClient? _client;
  bool _stopped = false;
  String? _fatalError;
  DateTime _lastTouch = DateTime.now();
  Timer? _idleTimer;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  /// Codec vidéo vu dans la PMT ('h264', 'hevc', …) — pour les
  /// diagnostics (HEVC = limite connue du Default Media Receiver sur
  /// les vrais Chromecast ; la SHIELD le décode).
  String get videoCodec => _segmenter.videoCodec;

  bool get isStopped => _stopped;
  String? get fatalError => _fatalError;
  int get segmentCount => _segments.length;

  /// Marqueur « première playlist servie déjà journalisée » (posé par
  /// LocalCastServer pour ne logger le codec qu'une fois par session).
  bool readyLogged = false;

  /// Démarre la boucle de fetch upstream (non bloquant).
  void start() {
    _segmenter = _segmenterFactory();
    _idleTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (DateTime.now().difference(_lastTouch) > kIdleTimeout) {
        if (kDebugMode) {
          debugPrint('[HlsRelay] inactif ${kIdleTimeout.inSeconds}s → stop');
        }
        stop();
      }
    });
    unawaited(_fetchLoop());
  }

  void stop() {
    _stopped = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    _client?.close(force: true);
    _client = null;
    _completeWaiters();
  }

  /// À appeler sur chaque requête HTTP du récepteur (garde la session
  /// en vie face au GC d'inactivité).
  void touch() => _lastTouch = DateTime.now();

  /// Attend que [count] segments soient disponibles (ou erreur fatale
  /// / stop / timeout). Renvoie `true` si la playlist est servable.
  Future<bool> waitForSegments(int count, Duration timeout) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (_segments.length < count && !_stopped && _fatalError == null) {
      final Duration left = deadline.difference(DateTime.now());
      if (left.isNegative) break;
      final Completer<void> c = Completer<void>();
      _waiters.add(c);
      try {
        await c.future.timeout(left);
      } on TimeoutException {
        _waiters.remove(c);
        break;
      }
    }
    return _segments.length >= count;
  }

  HlsLiveSegment? segment(int sequence) {
    for (final HlsLiveSegment s in _segments) {
      if (s.sequence == sequence) return s;
    }
    return null;
  }

  /// Playlist live conforme RFC 8216 (fenêtre glissante, pas de
  /// ENDLIST). [segmentUriPrefix] = préfixe des URIs de segments,
  /// p.ex. `<token>/` → `<token>/12.ts` (résolu relativement à
  /// l'URL de la playlist).
  String playlist({required String segmentUriPrefix}) {
    final int windowStart = _segments.length <= kPlaylistWindow
        ? 0
        : _segments.length - kPlaylistWindow;
    final List<HlsLiveSegment> window = _segments.sublist(windowStart);
    // DISCONTINUITY-SEQUENCE compte les discontinuités sorties DE LA
    // PLAYLIST (RFC 8216 §4.3.3.3) — celles évincées de la rétention
    // (_discontinuitySequence) PLUS celles encore retenues mais en
    // amont de la fenêtre publiée.
    int discoSeq = _discontinuitySequence;
    for (int i = 0; i < windowStart; i++) {
      if (_segments[i].discontinuity) discoSeq++;
    }
    double maxDur = 4.0;
    for (final HlsLiveSegment s in window) {
      if (s.durationSec > maxDur) maxDur = s.durationSec;
    }
    final StringBuffer b = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3')
      ..writeln('#EXT-X-TARGETDURATION:${maxDur.ceil()}')
      ..writeln(
          '#EXT-X-MEDIA-SEQUENCE:${window.isEmpty ? 0 : window.first.sequence}')
      ..writeln('#EXT-X-DISCONTINUITY-SEQUENCE:$discoSeq');
    for (final HlsLiveSegment s in window) {
      if (s.discontinuity) b.writeln('#EXT-X-DISCONTINUITY');
      b
        ..writeln('#EXTINF:${s.durationSec.toStringAsFixed(3)},')
        ..writeln('$segmentUriPrefix${s.sequence}.ts');
    }
    return b.toString();
  }

  // ------------------------------------------------------------
  //  Boucle upstream
  // ------------------------------------------------------------

  Future<void> _fetchLoop() async {
    int consecutiveFailures = 0;
    bool everConnected = false;
    while (!_stopped) {
      bool producedSegment = false;
      try {
        final HttpClient client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8)
          ..idleTimeout = const Duration(minutes: 10)
          ..userAgent = userAgent
          ..autoUncompress = false;
        _client = client;
        final HttpClientRequest req =
            await client.getUrl(Uri.parse(upstreamUrl));
        req.followRedirects = true;
        req.maxRedirects = 5;
        final HttpClientResponse resp = await req.close();
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          await resp.drain<void>();
          throw HttpException('upstream HTTP ${resp.statusCode}');
        }
        everConnected = true;
        await for (final List<int> chunk in resp) {
          if (_stopped) break;
          for (final TsSegment seg in _segmenter.ingest(chunk)) {
            producedSegment = true;
            _publish(seg);
          }
        }
        // Fin « propre » de la socket : publie le reliquat s'il est
        // exploitable, puis reconnecte (comportement normal Xtream).
        final TsSegment? tail = _segmenter.flush();
        if (tail != null) {
          producedSegment = true;
          _publish(tail);
        }
      } on Object catch (e) {
        if (kDebugMode) debugPrint('[HlsRelay] upstream: $e');
      } finally {
        _client?.close(force: true);
        _client = null;
      }
      if (_stopped) break;

      consecutiveFailures = producedSegment ? 0 : consecutiveFailures + 1;
      if (consecutiveFailures > kMaxConsecutiveReconnects) {
        _fatalError = everConnected
            ? 'Flux upstream interrompu (reconnexions épuisées).'
            : 'Flux upstream injoignable depuis le téléphone.';
        _completeWaiters();
        stop();
        break;
      }
      // Nouvelle connexion = nouvelle horloge PCR potentielle →
      // segmenteur neuf + discontinuité annoncée dans la playlist.
      _segmenter = _segmenterFactory();
      _pendingDiscontinuity = true;
      await Future<void>.delayed(
          Duration(milliseconds: 400 * (consecutiveFailures + 1)));
    }
  }

  void _publish(TsSegment seg) {
    _segments.add(HlsLiveSegment(
      sequence: _nextSequence++,
      bytes: seg.bytes,
      durationSec: seg.durationSec,
      discontinuity: _pendingDiscontinuity,
    ));
    _pendingDiscontinuity = false;
    while (_segments.length > kRetention) {
      final HlsLiveSegment evicted = _segments.removeAt(0);
      // Un marqueur DISCONTINUITY qui sort de la fenêtre doit être
      // compté dans DISCONTINUITY-SEQUENCE (RFC 8216 §4.3.3.3).
      if (evicted.discontinuity) _discontinuitySequence++;
    }
    _completeWaiters();
  }

  void _completeWaiters() {
    for (final Completer<void> c in _waiters) {
      if (!c.isCompleted) c.complete();
    }
    _waiters.clear();
  }
}
