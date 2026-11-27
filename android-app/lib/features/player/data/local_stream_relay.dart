// =========================================================
//  local_stream_relay.dart — Mini-relais local "1 connexion"
// =========================================================
//  POURQUOI CE FICHIER EXISTE
//  --------------------------
//  Sur un abonnement IPTV qui n'autorise qu'UNE connexion à la fois,
//  on a deux besoins qui se contredisent en apparence :
//    1. ENREGISTRER le flux (écrire les octets dans un fichier) ;
//    2. tout en CONTINUANT à le REGARDER.
//  Si on ouvre une 2e connexion réseau pour enregistrer pendant que le
//  lecteur tire la 1ère, le serveur voit "2 connexions" = MULTI-VIEW →
//  il coupe (et l'enregistrement finit vide). C'est le bug que
//  l'utilisateur a vécu.
//
//  LE SECRET DE TIVIMATE / VLC : ne pas dédoubler la connexion, mais
//  dédoubler les OCTETS. On ouvre UNE seule connexion vers le serveur
//  IPTV (l'"upstream"), et on recopie chaque paquet reçu vers DEUX
//  destinations locales :
//    - le lecteur (mpv lit depuis http://127.0.0.1:<port>/… ) ;
//    - le fichier d'enregistrement (si REC est actif).
//  → 1 seule connexion vue par le serveur, lecture + enregistrement
//    simultanés, fichier JAMAIS vide (puisque ce sont les mêmes octets
//    qui s'affichent à l'écran).
//
//  COMMENT ÇA MARCHE
//  -----------------
//  On lance un petit serveur HTTP sur 127.0.0.1 (la boucle locale, rien
//  ne sort du téléphone). Au lieu de demander à mpv d'ouvrir l'URL IPTV
//  directement, on lui donne une URL locale `…/s?u=<url_encodée>`. Notre
//  serveur ouvre alors l'upstream une seule fois et "fan-out" les octets
//  vers tous les consommateurs (le lecteur, l'enregistreur).
//
//  Une "session" = une chaîne en cours, identifiée par son URL réelle.
//  Tant qu'au moins un consommateur (lecteur OU enregistreur) est
//  branché, l'upstream reste ouvert ; quand le dernier part, on ferme.
//  Si le serveur IPTV coupe la socket (recyclage d'edge fréquent en
//  live), on reconnecte tout seul et on continue d'alimenter les deux.
//
//  LIMITE ASSUMÉE (v1) : ce relais vit dans le process Dart de l'app. Si
//  l'app est tuée (swipe), il s'arrête. L'enregistrement tient tant que
//  l'app reste ouverte (premier plan ou arrière-plan). Le "record même
//  app fermée" via un service natif est un chantier séparé.
//
//  CE RELAIS NE SERT QUE POUR LE LIVE. La VOD / le catch-up (contenu
//  seekable à durée finie) reste joué en direct car il faut gérer les
//  requêtes Range (avance/recul), ce que ce relais live ne fait pas.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/observability/structured_logger.dart';
import 'player_settings.dart';
import 'hls_segment_reader.dart';

/// Nombre d'échecs de reconnexion CONSÉCUTIFS tolérés avant d'abandonner
/// l'upstream. Tant qu'une reconnexion réussit, le compteur repart à 0,
/// donc un flux qui hoquette longtemps continue. On n'abandonne que si le
/// serveur reste injoignable plusieurs essais d'affilée.
const int _kMaxReconnectFailures = 12;
const int _kMaxEmptyStarts = 3;

/// Relais singleton. Une instance pour toute l'app : un seul serveur HTTP
/// local, qui multiplexe N chaînes (sessions) si besoin.
class LocalStreamRelay {
  LocalStreamRelay._();
  static final LocalStreamRelay instance = LocalStreamRelay._();

  Future<void>? _binding;
  int _port = 0;

  /// Sessions actives, indexées par l'URL RÉELLE du flux (la clé est
  /// l'URL upstream, pas l'URL locale). Une session = une chaîne tirée
  /// une seule fois et distribuée à ses consommateurs.
  final Map<String, _RelaySession> _sessions = <String, _RelaySession>{};

  /// `true` si une chaîne donnée est en cours d'enregistrement via le relais.
  bool isRecording(String realUrl) =>
      _sessions[realUrl]?.recordSink != null;

  /// Se termine après fermeture du fichier, y compris lors d'un arrêt amont.
  Future<bool> recordingFinished(String realUrl) async {
    final session = _sessions[realUrl];
    try {
      await session?.recordSink?.done;
      return session?.finishedHls ?? false;
    } on IOException {
      return false;
    }
  }

  /// Démarre le serveur local si besoin et renvoie l'URL LOCALE que le
  /// lecteur doit ouvrir à la place de l'URL IPTV réelle. L'URL réelle
  /// est passée percent-encodée dans le paramètre `u` (Dart la décode
  /// automatiquement côté serveur via `queryParameters`).
  Future<String> playUrlFor(String realUrl) async {
    await _ensureServer();
    final String token = Uri.encodeComponent(realUrl);
    return 'http://127.0.0.1:$_port/s?u=$token';
  }

  /// Le relais du direct enregistre des octets média continus. Un manifeste
  /// demande une résolution de ses segments avant écriture.
  static bool isHlsPlaylist(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.m3u8') || path.endsWith('.m3u');
  }

  /// Démarre l'écriture du flux EN COURS vers `filePath`, en se branchant
  /// sur la connexion DÉJÀ ouverte pour la lecture (aucune 2e connexion).
  /// Si aucune session n'existe encore pour cette URL (cas limite), on
  /// l'ouvre. Retourne `false` si l'ouverture du fichier échoue.
  Future<bool> startRecording({
    required String realUrl,
    required String filePath,
  }) {
    final session = _ensureSession(realUrl);
    if (session.recordSink != null) return Future.value(true);
    return session.openingRecording ??= _openRecording(session, filePath)
        .whenComplete(() {
      session.openingRecording = null;
      _maybeCloseSession(session);
    });
  }

  Future<bool> _openRecording(_RelaySession session, String filePath) async {
    IOSink? opening;
    try {
      final File file = File(filePath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      opening = sink;
      // openWrite ouvre le fichier de manière asynchrone. Attendre son
      // ouverture avant de confirmer REC et avant de tirer le flux.
      unawaited(sink.done.then<void>((_) {}, onError: (Object _, StackTrace __) {
        if (identical(session.recordSink, sink)) {
          session.recordSink = null;
          _maybeCloseSession(session);
        }
      }));
      await sink.addStream(const Stream<List<int>>.empty());
      if (session.closed) {
        await sink.close();
        return false;
      }
      session.recordSink = sink;
      session.recordPath = filePath;
      session.recordBytes = 0;
      _ensureUpstream(session);
    } catch (e) {
      try { await opening?.close(); } catch (_) {}
      if (kDebugMode) debugPrint('[Relay] fichier indisponible (${e.runtimeType})');
      return false;
    }
    StructuredLogger.instance.info(
      domain: 'rec',
      event: 'relay.record_start',
      ctx: <String, Object?>{'filePath': filePath},
    );
    return true;
  }

  /// Arrête l'enregistrement de cette chaîne et renvoie le nombre
  /// d'octets écrits. La lecture, elle, continue (la session reste
  /// vivante tant que le lecteur est branché).
  Future<int> stopRecording(String realUrl) async {
    final _RelaySession? session = _sessions[realUrl];
    if (session == null) return 0;
    await session.openingRecording;
    if (session.recordSink == null) return 0;
    final IOSink sink = session.recordSink!;
    final int bytes = session.recordBytes;
    session.recordSink = null;
    final String? path = session.recordPath;
    session.recordPath = null;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {}
    StructuredLogger.instance.info(
      domain: 'rec',
      event: 'relay.record_stop',
      ctx: <String, Object?>{'filePath': path, 'bytes': bytes},
    );
    _maybeCloseSession(session);
    return bytes;
  }

  /// Octets déjà écrits pour la chaîne en cours d'enregistrement (0 si
  /// pas d'enregistrement). Utile pour afficher la taille en temps réel.
  int recordedBytes(String realUrl) => _sessions[realUrl]?.recordBytes ?? 0;

  // ---------------------------------------------------------------
  //  Serveur HTTP local
  // ---------------------------------------------------------------

  Future<void> _ensureServer() {
    return _binding ??= _bindServer().catchError((Object error) {
      _binding = null; // Le prochain démarrage peut retenter le bind.
      throw error;
    });
  }

  Future<void> _bindServer() async {
    // Port 0 = l'OS choisit un port libre. On le mémorise pour fabriquer
    // les URLs locales. Bind sur loopback uniquement (jamais exposé).
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = server.port;
    if (kDebugMode) debugPrint('[Relay] serveur local prêt sur 127.0.0.1:$_port');
    server.listen(_handleRequest, onError: (Object e) {
      if (kDebugMode) debugPrint('[Relay] erreur serveur: $e');
    });
  }

  Future<void> _handleRequest(HttpRequest req) async {
    // On n'accepte que /s?u=<token>. Tout le reste → 404.
    // `queryParameters` percent-décode déjà la valeur → on récupère
    // directement l'URL IPTV réelle.
    final String? realUrl = req.uri.queryParameters['u'];
    if (req.uri.path != '/s' || realUrl == null || realUrl.isEmpty) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    final _RelaySession session = _ensureSession(realUrl);
    _ensureUpstream(session);

    final HttpResponse res = req.response;
    // En-têtes "live" : pas de longueur connue, pas de cache. On désactive
    // le buffering de sortie pour une latence minimale vers mpv.
    res.statusCode = HttpStatus.ok;
    res.headers.contentType = ContentType('video', 'mp2t');
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-store');
    res.bufferOutput = false;

    final _PlayerConsumer consumer = _PlayerConsumer(res);
    session.players.add(consumer);
    final segment = session.lastHlsSegment;
    if (segment != null) res.add(segment);

    // Quand mpv ferme la connexion (pause prolongée, zap, dispose), la
    // future `res.done` se résout (ou casse) → on détache le consommateur.
    res.done.then((_) => consumer.markClosed()).catchError(
        (Object _) => consumer.markClosed());

    if (kDebugMode) {
      debugPrint('[Relay] lecteur branché (${session.players.length}) '
          'sur ${_short(realUrl)}');
    }

    // On garde la requête ouverte tant que le client est là. Au départ
    // du client, on nettoie et on ferme éventuellement la session.
    try {
      await consumer.closed.future;
    } finally {
      session.players.remove(consumer);
      if (kDebugMode) {
        debugPrint('[Relay] lecteur parti (${session.players.length} restants)');
      }
      _maybeCloseSession(session);
    }
  }

  // ---------------------------------------------------------------
  //  Sessions & upstream
  // ---------------------------------------------------------------

  _RelaySession _ensureSession(String realUrl) {
    return _sessions.putIfAbsent(
        realUrl, () => _RelaySession(realUrl: realUrl));
  }

  /// Ouvre la connexion upstream de la session si elle n'est pas déjà
  /// active. Idempotent : appelé à la fois par la lecture et par REC.
  void _ensureUpstream(_RelaySession session) {
    if (session.upstreamActive) return;
    session.upstreamActive = true;
    _connectUpstream(session);
  }

  Future<void> _connectUpstream(_RelaySession session) async {
    final HttpClientResponse? resp =
        await _openUpstream(session, session.realUrl);
    if (session.closed) return;
    if (resp == null) {
      session.emptyStarts = 0;
      // Échec d'ouverture → on tente de reconnecter (avec back-off) tant
      // qu'il reste des consommateurs.
      _scheduleReconnect(session);
      return;
    }
    _attachUpstreamListener(session, resp);
  }

  /// Ouvre (ou rouvre) la connexion HTTP vers le flux réel. Mêmes
  /// précautions que pour un téléchargement IPTV robuste : suivre les
  /// redirects Xtream, ne PAS décompresser (sinon octets cassés),
  /// User-Agent permissif.
  Future<HttpClientResponse?> _openUpstream(
    _RelaySession session,
    String url,
  ) async {
    try {
      try {
        session.client?.close(force: true);
      } catch (_) {}
      session.client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..idleTimeout = const Duration(minutes: 10)
        ..autoUncompress = false
        // User-Agent configurable : certains serveurs IPTV n'autorisent le
        // vrai flux QU'AUX signatures de lecteurs connus (sinon ils servent
        // une pub/placeholder). Modifiable dans Réglages → Lecteur.
        ..userAgent = PlayerSettings.instance.userAgent;

      final HttpClientRequest cReq =
          await session.client!.getUrl(Uri.parse(url));
      cReq.followRedirects = true;
      cReq.maxRedirects = 8;
      cReq.headers.set(HttpHeaders.acceptHeader, '*/*');

      // connectionTimeout couvre la connexion TCP, pas un serveur qui accepte
      // la socket et ne renvoie jamais ses en-têtes.
      final HttpClientResponse cResp =
          await cReq.close().timeout(const Duration(seconds: 30));
      if (cResp.statusCode != 200 && cResp.statusCode != 206) {
        if (kDebugMode) {
          debugPrint('[Relay] HTTP ${cResp.statusCode} sur ${_short(url)}');
        }
        try {
          session.client?.close(force: true);
        } catch (_) {}
        return null;
      }
      return cResp;
    } catch (e) {
      session.client?.close(force: true);
      if (kDebugMode) debugPrint('[Relay] ouverture refusée (${e.runtimeType})');
      return null;
    }
  }

  void _attachUpstreamListener(
    _RelaySession session,
    HttpClientResponse resp,
  ) {
    // Certains fournisseurs redirigent une URL opaque vers un manifeste
    // .m3u8 servi en texte ordinaire. L’indice peut être sur l’une ou
    // l’autre adresse. La même réponse alimente ensuite le lecteur HLS.
    final redirectedTo = resp.redirects.isEmpty
        ? null
        : HlsSegmentReader.effectiveUri(Uri.parse(session.realUrl), resp);
    final hls = isHlsPlaylist(session.realUrl) ||
        (redirectedTo != null && isHlsPlaylist(redirectedTo.toString())) ||
        resp.headers[HttpHeaders.contentTypeHeader]?.any(
          (v) => v.split(';').first.trim().toLowerCase().endsWith('mpegurl'),
        ) == true;
    if (hls) {
      final reader = session.hls ??= HlsSegmentReader();
      session.sub = reader.read(session.client!, Uri.parse(session.realUrl), resp)
          .asyncMap<List<int>>((segment) async {
          // Une ouverture native tardive peut encore lire le segment courant.
          session.lastHlsSegment = segment;
          _fanout(session, segment);
          final sink = session.recordSink;
          if (sink != null) {
            try {
              await sink.flush();
            } on IOException {
              if (identical(session.recordSink, sink)) session.recordSink = null;
              _maybeCloseSession(session);
            }
          }
          return segment;
        }).listen(
        null,
        onError: (Object error, StackTrace stack) {
          session.sub = null;
          if (error is FormatException) {
            _closeSession(session);
          } else {
            unawaited(_scheduleReconnect(session));
          }
        },
        onDone: () {
          session.finishedHls = session.receivedData;
          _closeSession(session);
        },
        cancelOnError: true,
      );
      return;
    }
    // idleTimeout de HttpClient concerne les connexions inactives du pool.
    // Borner aussi le silence du corps d'une réponse déjà ouverte.
    session.sub = resp.timeout(const Duration(seconds: 30)).listen(
      (List<int> chunk) => _fanout(session, chunk),
      onError: (Object e, StackTrace s) {
        session.emptyStarts = 0;
        if (kDebugMode) debugPrint('[Relay] lecture interrompue (${e.runtimeType})');
        _scheduleReconnect(session);
      },
      onDone: () {
        if (!session.receivedData && ++session.emptyStarts >= _kMaxEmptyStarts) {
          StructuredLogger.instance.warn(
            domain: 'rec',
            event: 'relay.empty_source',
            ctx: <String, Object?>{'attempts': session.emptyStarts},
          );
          _closeSession(session);
          return;
        }
        if (kDebugMode) {
          debugPrint('[Relay] upstream fermé par le serveur, reconnexion');
        }
        _scheduleReconnect(session);
      },
      cancelOnError: true,
    );
  }

  /// Recopie un paquet vers TOUS les consommateurs : le(s) lecteur(s) et
  /// le fichier d'enregistrement s'il est actif.
  void _fanout(_RelaySession session, List<int> chunk) {
    if (chunk.isEmpty || session.closed) return;
    // Un 200 vide ne prouve aucune reprise. Seuls les octets reçus
    // réinitialisent le budget de cette session.
    session.receivedData = true;
    session.reconnectFailures = 0;
    // Lecteurs : on écrit, on retire ceux dont la socket est morte.
    final List<_PlayerConsumer> dead = <_PlayerConsumer>[];
    for (final _PlayerConsumer c in session.players) {
      if (c.isClosed) {
        dead.add(c);
        continue;
      }
      try {
        c.res.add(chunk);
      } catch (_) {
        c.markClosed();
        dead.add(c);
      }
    }
    for (final _PlayerConsumer c in dead) {
      session.players.remove(c);
    }

    // Enregistrement : mêmes octets, écrits dans le fichier.
    final IOSink? sink = session.recordSink;
    if (sink != null) {
      try {
        sink.add(chunk);
        session.recordBytes += chunk.length;
      } catch (e) {
        // Erreur disque (plein, carte éjectée) → on coupe l'enregistrement
        // mais on NE casse PAS la lecture.
        if (kDebugMode) debugPrint('[Relay] écriture disque KO: $e');
        session.recordSink = null;
        try {
          unawaited(sink.close().then<void>((_) {}, onError: (Object _, StackTrace __) {}));
        } catch (_) {}
      }
    }
  }

  /// Reconnexion upstream avec back-off, tant qu'il reste des
  /// consommateurs et qu'on n'a pas trop échoué d'affilée.
  Future<void> _scheduleReconnect(_RelaySession session) async {
    if (session.closed || session.retryTimer != null) return;
    // Plus personne n'écoute → inutile de reconnecter.
    if (!session.hasConsumers) {
      _maybeCloseSession(session);
      return;
    }
    session.client?.close(force: true);
    try {
      await session.sub?.cancel();
    } catch (_) {}
    session.sub = null;
    if (session.closed) return;

    session.reconnectFailures++;
    if (session.reconnectFailures > _kMaxReconnectFailures) {
      if (kDebugMode) {
        debugPrint('[Relay] serveur injoignable, abandon ${_short(session.realUrl)}');
      }
      StructuredLogger.instance.warn(
        domain: 'rec',
        event: 'relay.upstream_dead',
        ctx: <String, Object?>{'failures': session.reconnectFailures},
      );
      _closeSession(session);
      return;
    }

    final int wait = (2 * session.reconnectFailures).clamp(2, 16);
    session.retryTimer = Timer(Duration(seconds: wait), () {
      session.retryTimer = null;
      if (!session.closed) unawaited(_connectUpstream(session));
    });
  }

  /// Ferme la session si plus aucun consommateur (ni lecteur ni REC).
  void _maybeCloseSession(_RelaySession session) {
    if (session.hasConsumers) return;
    _closeSession(session);
  }

  void _closeSession(_RelaySession session) {
    // Une ancienne réponse locale peut se terminer après le démarrage
    // d'une nouvelle session sur la même URL.
    if (session.closed) return;
    session.closed = true;
    session.hls?.close();
    session.lastHlsSegment = null;
    session.retryTimer?.cancel();
    session.retryTimer = null;
    try {
      session.sub?.cancel();
    } catch (_) {}
    session.sub = null;
    try {
      session.client?.close(force: true);
    } catch (_) {}
    session.client = null;
    // On ferme les réponses des lecteurs encore branchés : mpv reçoit
    // une fin de flux (EOF) et peut afficher une erreur au lieu de
    // rester figé indéfiniment sur une session morte.
    for (final _PlayerConsumer c in List<_PlayerConsumer>.from(session.players)) {
      try {
        unawaited(c.res.close().then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      } catch (_) {}
      c.markClosed();
    }
    session.players.clear();
    // Si un enregistrement traînait encore, on le ferme proprement.
    final IOSink? sink = session.recordSink;
    session.recordSink = null;
    if (sink != null) {
      try {
        unawaited(sink.close().then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      } catch (_) {}
    }
    session.upstreamActive = false;
    _sessions.remove(session.realUrl);
    if (kDebugMode) {
      debugPrint('[Relay] session fermée ${_short(session.realUrl)} '
          '(${_sessions.length} restantes)');
    }
  }

  String _short(String url) => Uri.tryParse(url)?.host ?? '?';
}

/// Un lecteur branché sur une session (la réponse HTTP locale vers mpv).
class _PlayerConsumer {
  _PlayerConsumer(this.res);
  final HttpResponse res;
  final Completer<void> closed = Completer<void>();
  bool isClosed = false;

  void markClosed() {
    if (isClosed) return;
    isClosed = true;
    if (!closed.isCompleted) closed.complete();
  }
}

/// État d'une chaîne tirée une seule fois et distribuée.
class _RelaySession {
  _RelaySession({required this.realUrl});
  final String realUrl;

  HttpClient? client;
  StreamSubscription<List<int>>? sub;
  bool upstreamActive = false;
  bool closed = false;
  Timer? retryTimer;
  Future<bool>? openingRecording;
  int reconnectFailures = 0;
  int emptyStarts = 0;
  bool receivedData = false;
  HlsSegmentReader? hls;
  List<int>? lastHlsSegment;
  bool finishedHls = false;

  /// Lecteurs branchés (mpv). En pratique 0 ou 1, mais on supporte
  /// plusieurs (mpv ouvre parfois une connexion de sonde + une de
  /// lecture). Tous reçoivent les mêmes octets.
  final List<_PlayerConsumer> players = <_PlayerConsumer>[];

  /// Destination d'enregistrement (null = pas d'enregistrement en cours).
  IOSink? recordSink;
  String? recordPath;
  int recordBytes = 0;

  /// Vrai tant qu'au moins un consommateur (lecteur ou enregistrement)
  /// a besoin de l'upstream.
  bool get hasConsumers =>
      players.isNotEmpty || recordSink != null || openingRecording != null;
}
