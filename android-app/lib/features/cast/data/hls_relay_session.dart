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
import 'dart:math' as math;

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
  }) : _segmenterFactory = segmenterFactory ??
            // Rampe de démarrage (fluidité 2026-07-10) : les 2 premiers
            // segments visent ~1,8 s au lieu de 3 s → la playlist devient
            // servable presque deux fois plus vite au zapping. Une
            // reconnexion upstream repasse par la rampe (segmenteur
            // neuf) : sans conséquence, 2 segments courts au raccord
            // aident même le récepteur à se recaler.
            (() => TsHlsSegmenter(startupSegments: 2));

  final String upstreamUrl;
  final String userAgent;
  final TsHlsSegmenter Function() _segmenterFactory;

  /// Fenêtre annoncée dans la playlist (6 × ~3 s ≈ 18 s de live) —
  /// élargie après le diag fluidité 2026-07-09 : plus de marge de
  /// buffer côté récepteur = moins de saccades sur WiFi chargé.
  static const int kPlaylistWindow = 6;

  /// Rétention mémoire : on garde plusieurs segments de plus que la
  /// playlist — le récepteur peut encore demander un segment qui vient
  /// de sortir de la fenêtre. Élargi (10 → 14 ≈ 42 s) : sur un WiFi
  /// chargé (le téléphone télécharge l'upstream ET téléverse vers la TV
  /// sur la même radio), le récepteur prend parfois du retard et
  /// redemande un segment déjà sorti de la fenêtre → 404 → rebuffering.
  /// Plus de marge = moins de 404, au prix de quelques Mo de RAM.
  static const int kRetention = 14;

  /// Reconnexions upstream d'affilée tolérées AVANT de considérer un
  /// abandon — et ENCORE, on n'abandonne pas si la TV regarde toujours
  /// (cf. _fetchLoop). Compteur remis à zéro dès qu'une connexion a
  /// produit au moins un segment.
  static const int kMaxConsecutiveReconnects = 6;

  /// Recul visé du point de lecture derrière le bord live (anti-
  /// découpage 2026-07-10). La RFC 8216bis (HOLD-BACK) impose ≥ 3 ×
  /// TARGETDURATION : un lecteur collé au bord re-bufferise à CHAQUE
  /// à-coup (WiFi chargé, reconnexion upstream). Publié via
  /// #EXT-X-START:TIME-OFFSET, honoré par ExoPlayer (SHIELD) et Shaka.
  static const double kJoinHoldBackSec = 10.0;

  /// Sans AUCUNE requête du récepteur pendant ce délai, la session
  /// s'arrête seule (récepteur mort sans clearRelay → épargne
  /// batterie/data). Large : le récepteur met parfois >30 s à faire
  /// sa première requête (bascule de receiver + LOAD).
  static const Duration kIdleTimeout = Duration(seconds: 120);

  final List<HlsLiveSegment> _segments = <HlsLiveSegment>[];
  int _nextSequence = 0;
  int _discontinuitySequence = 0;

  TsHlsSegmenter _segmenter = TsHlsSegmenter();
  bool _reconnected = false;
  double? _prevConnectionLastPcr;
  HttpClient? _client;
  bool _stopped = false;
  String? _fatalError;
  DateTime _lastTouch = DateTime.now();
  Timer? _idleTimer;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  /// Codec vidéo vu dans la PMT ('h264', 'hevc', …) — pour les
  /// diagnostics (HEVC = limite connue du Default Media Receiver sur
  /// les vrais Chromecast ; la SHIELD le décode). PERSISTÉ au niveau
  /// session : le segmenteur est remplacé à chaque reconnexion (et une
  /// connexion vide ne voit jamais la PMT).
  String get videoCodec => _videoCodec;
  String _videoCodec = 'unknown';

  /// Codec audio vu dans la PMT — persisté comme le codec vidéo.
  /// Sert aux diagnostics « son dégradé » (mp2 mono côté fournisseur ≠
  /// bug de l'app).
  String get audioCodec => _audioCodec;
  String _audioCodec = 'unknown';

  bool get isStopped => _stopped;
  String? get fatalError => _fatalError;
  int get segmentCount => _segments.length;

  /// Secondes de flux actuellement retenues (somme des EXTINF). C'est
  /// le coussin maximal que le récepteur peut se constituer au join.
  double get bufferedSeconds {
    double total = 0;
    for (final HlsLiveSegment s in _segments) {
      total += s.durationSec;
    }
    return total;
  }

  /// Marqueur « première playlist servie déjà journalisée » (posé par
  /// LocalCastServer pour ne logger le codec qu'une fois par session).
  bool readyLogged = false;

  /// Compteurs de requêtes du RÉCEPTEUR (posés par LocalCastServer).
  /// Précieux dans les messages d'erreur : « format non supporté » avec
  /// 0 segment servi = la TV n'a jamais rien téléchargé (réseau), avec
  /// N segments servis = elle a téléchargé mais pas décodé (codec).
  int playlistServed = 0;
  int segmentsServed = 0;

  /// Nombre total de segments produits depuis le début de la session.
  int get totalSegmentsProduced => _nextSequence;

  /// Nombre de fois où l'upstream a épuisé son budget de reconnexion
  /// ALORS QUE la TV regardait encore — donc où l'on a REFUSÉ de tuer la
  /// session (avant, elle serait morte ici). Diagnostic « pourquoi le
  /// cast a tenu longtemps ».
  int reconnectsWhileWatched = 0;

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

  /// Attend que [seconds] de flux soient retenues (ou erreur fatale /
  /// stop / timeout). Contrairement à [waitForSegments], la condition
  /// est en SECONDES : c'est le coussin anti-découpage du récepteur.
  /// Renvoie `true` si le coussin visé est atteint — `false` n'est PAS
  /// bloquant pour l'appelant (on sert ce qu'on a).
  Future<bool> waitForBufferedSeconds(
      double seconds, Duration timeout) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (bufferedSeconds < seconds && !_stopped && _fatalError == null) {
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
    return bufferedSeconds >= seconds;
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
    double windowDur = 0;
    for (final HlsLiveSegment s in window) {
      if (s.durationSec > maxDur) maxDur = s.durationSec;
      windowDur += s.durationSec;
    }
    final StringBuffer b = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3')
      ..writeln('#EXT-X-TARGETDURATION:${maxDur.ceil()}')
      ..writeln(
          '#EXT-X-MEDIA-SEQUENCE:${window.isEmpty ? 0 : window.first.sequence}')
      ..writeln('#EXT-X-DISCONTINUITY-SEQUENCE:$discoSeq');
    // ANTI-DÉCOUPAGE (2026-07-10) : sans EXT-X-START, le récepteur se
    // place à ~3 durées de segment du bord — avec des segments de
    // démarrage COURTS (rampe 1,8 s) ça ne faisait que ~4-5 s de
    // coussin, et chaque à-coup WiFi / reconnexion upstream devenait
    // une coupure visible. On épingle le join aussi loin du bord que
    // la fenêtre le permet (cible kJoinHoldBackSec). Les refresh
    // suivants n'y touchent plus (le tag ne compte qu'au join).
    final double joinOffset = startTimeOffsetFor(windowDur);
    if (joinOffset > 0) {
      b.writeln(
          '#EXT-X-START:TIME-OFFSET=-${joinOffset.toStringAsFixed(1)}');
    }
    for (final HlsLiveSegment s in window) {
      if (s.discontinuity) b.writeln('#EXT-X-DISCONTINUITY');
      b
        ..writeln('#EXTINF:${s.durationSec.toStringAsFixed(3)},')
        ..writeln('$segmentUriPrefix${s.sequence}.ts');
    }
    return b.toString();
  }

  /// Recul de join (module de [playlist]) : viser [kJoinHoldBackSec]
  /// derrière le bord, sans jamais demander plus que ce que la fenêtre
  /// contient (on garde ~2 s de marge pour que le point de départ
  /// tombe sur un segment réellement listé). ≤ 0 = pas de tag.
  @visibleForTesting
  static double startTimeOffsetFor(double windowDurationSec) {
    if (windowDurationSec <= 3.0) return 0;
    return math.min(kJoinHoldBackSec, windowDurationSec - 2.0);
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
        // CŒUR DU « CAST QUI DOIT DURER ». Un live Xtream ferme sa socket
        // toutes les 1-2 min (rotation de jeton, normal) ; sur un compte
        // « 1 connexion » le slot n'est pas libéré tout de suite, ou le
        // .ts redirige un instant vers un flux mort → plusieurs échecs
        // d'affilée. AVANT : au 7e échec la session se tuait DÉFINITIVEMENT
        // (aucun watchdog Chromecast) → coupure à ~2 min. MAINTENANT : on
        // ne se tue QUE dans deux cas francs — jamais tant que la TV
        // regarde encore.
        //
        // touch() est rafraîchi à CHAQUE requête du récepteur (playlist ou
        // segment), MÊME quand on répond 503 (flux pas prêt) : c'est donc
        // le signal fiable « la TV redemande toujours le flux ».
        final bool receiverActive =
            DateTime.now().difference(_lastTouch) < kIdleTimeout;
        if (!everConnected) {
          // Jamais réussi à se connecter : URL morte / réseau absent →
          // inutile de tourner à vide, on remonte une vraie erreur.
          _fatalError = 'Flux upstream injoignable depuis le téléphone.';
          _completeWaiters();
          stop();
          break;
        }
        if (!receiverActive) {
          // On a déjà diffusé, mais la TV ne demande plus rien depuis
          // longtemps ET l'upstream ne revient pas → le récepteur est
          // parti, on libère proprement (batterie / data).
          _fatalError = 'Flux upstream interrompu (récepteur inactif).';
          _completeWaiters();
          stop();
          break;
        }
        // La TV VEUT toujours le flux → on NE se suicide PAS : on continue
        // à réessayer (backoff plafonné) et on reprend la diffusion dès que
        // l'upstream répond. C'est ce qui rend le cast « increvable ».
        reconnectsWhileWatched++;
      }
      // Nouvelle connexion = segmenteur neuf. La discontinuité n'est
      // décidée qu'à la publication du 1er segment suivant : si la PCR
      // CONTINUE (même encodeur, simple coupure de socket Xtream), la
      // transition est invisible — pas de EXT-X-DISCONTINUITY, pas de
      // réinitialisation du décodeur TV (à-coup évité toutes les 1-2
      // min). Si l'horloge saute, on l'annonce.
      _prevConnectionLastPcr =
          _segmenter.lastPcrSeen ?? _prevConnectionLastPcr;
      _segmenter = _segmenterFactory();
      _reconnected = true;
      // Backoff PLAFONNÉ à 2,5 s : il croît avec les échecs (on ne martèle
      // pas un serveur en peine) mais reste court pour reprendre vite dès
      // que le flux revient. Sans plafond, une longue série d'échecs
      // rallongerait l'attente à l'infini.
      final int steps = math.min(consecutiveFailures + 1, 6);
      await Future<void>.delayed(
          Duration(milliseconds: math.min(400 * steps, 2500)));
    }
  }

  void _publish(TsSegment seg) {
    if (_segmenter.videoCodec != 'unknown') {
      _videoCodec = _segmenter.videoCodec;
    }
    if (_segmenter.audioCodec != 'unknown') {
      _audioCodec = _segmenter.audioCodec;
    }
    bool discontinuity = false;
    if (_reconnected) {
      _reconnected = false;
      final double? first = _segmenter.firstPcrSeen;
      final double? prev = _prevConnectionLastPcr;
      // Continuité : la nouvelle connexion reprend l'horloge là où la
      // précédente s'était arrêtée (tolérance -1 s / +15 s).
      final bool seamless = first != null &&
          prev != null &&
          first >= prev - 1.0 &&
          first - prev <= 15.0;
      discontinuity = !seamless;
    }
    // Discontinuité INTRA-connexion détectée par le segmenteur (saut
    // PCR : coupure pub, splice, ré-ancrage encodeur). Sans ce tag, le
    // récepteur voyait ses timestamps sauter en silence → désynchro
    // audio/vidéo et son haché (le « pas stable » du terrain).
    discontinuity = discontinuity || seg.discontinuity;
    _segments.add(HlsLiveSegment(
      sequence: _nextSequence++,
      bytes: seg.bytes,
      durationSec: seg.durationSec,
      discontinuity: discontinuity,
    ));
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
