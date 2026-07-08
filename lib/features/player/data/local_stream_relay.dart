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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/observability/structured_logger.dart';
import 'hls_playlist_normalizer.dart';
import 'player_settings.dart';
import 'stream_diagnostics.dart';

/// Nombre d'échecs de reconnexion CONSÉCUTIFS tolérés avant d'abandonner
/// l'upstream, pour une session qui a DÉJÀ diffusé des octets (coupure en
/// cours de lecture : on s'accroche). Tant qu'une reconnexion réussit, le
/// compteur repart à 0, donc un flux qui hoquette longtemps continue.
const int _kMaxReconnectFailures = 12;

/// Même budget mais pour une session qui n'a JAMAIS encore reçu un octet
/// (échec dès l'ouverture). Boucler 13× sur une URL morte retardait la
/// cascade de variantes côté lecteur (bug terrain du 2026-07-08 : 404 sur
/// `.ts` réessayé en boucle au lieu de basculer sur `/live/….m3u8`).
/// On ne retente que les échecs TRANSITOIRES (DNS/socket/5xx) — un 4xx
/// définitif ferme la session immédiatement, sans aucun retry.
const int _kMaxInitialFailures = 3;

/// Relais singleton. Une instance pour toute l'app : un seul serveur HTTP
/// local, qui multiplexe N chaînes (sessions) si besoin.
class LocalStreamRelay {
  LocalStreamRelay._();
  static final LocalStreamRelay instance = LocalStreamRelay._();

  HttpServer? _server;
  int _port = 0;

  /// ÉCHECS DÉFINITIFS (4xx dès la 1re réponse, session jamais diffusée) :
  /// le relais l'annonce EXPLICITEMENT ici, avec l'URL RÉELLE concernée.
  /// C'est le lecteur (VideoPlayerScreen) qui s'y abonne pour déclencher
  /// IMMÉDIATEMENT sa sonde + cascade de variantes — bug terrain du
  /// 2026-07-08 11:37 : on comptait sur la réaction de mpv à un flux
  /// vide (EOF), qui n'arrive pas de façon fiable → la cascade ne
  /// s'exécutait jamais sur le chemin de lecture réel.
  final StreamController<String> _definitiveFailures =
      StreamController<String>.broadcast();

  /// URL réelles dont la session vient d'échouer DÉFINITIVEMENT.
  Stream<String> get definitiveFailures => _definitiveFailures.stream;

  /// Sessions actives, indexées par l'URL RÉELLE du flux (la clé est
  /// l'URL upstream, pas l'URL locale). Une session = une chaîne tirée
  /// une seule fois et distribuée à ses consommateurs.
  final Map<String, _RelaySession> _sessions = <String, _RelaySession>{};

  /// `true` si une chaîne donnée est en cours d'enregistrement via le relais.
  bool isRecording(String realUrl) =>
      _sessions[realUrl]?.recordSink != null;

  /// Démarre le serveur local si besoin et renvoie l'URL LOCALE que le
  /// lecteur doit ouvrir à la place de l'URL IPTV réelle. L'URL réelle
  /// est passée percent-encodée dans le paramètre `u` (Dart la décode
  /// automatiquement côté serveur via `queryParameters`).
  Future<String> playUrlFor(String realUrl) async {
    await _ensureServer();
    // ZAP / bascule de variante : une seule lecture à la fois. On ferme
    // toute session d'une AUTRE URL (sauf enregistrement en cours) —
    // sinon les relais des chaînes quittées continuaient leurs
    // reconnexions en boucle en parallèle (sessions zombies, bug terrain
    // du 2026-07-08 : France 2 → 3 → 4 = 3 boucles simultanées).
    closeOtherPlaybacks(realUrl);
    final String token = Uri.encodeComponent(realUrl);
    return 'http://127.0.0.1:$_port/s?u=$token';
  }

  /// Ferme toutes les sessions de lecture SAUF celle de [keepRealUrl].
  /// Les sessions qui enregistrent sont préservées (l'enregistrement
  /// d'une chaîne survit au zapping vers une autre).
  void closeOtherPlaybacks(String keepRealUrl) {
    for (final _RelaySession s
        in List<_RelaySession>.from(_sessions.values)) {
      if (s.realUrl == keepRealUrl) continue;
      if (s.recordSink != null) continue;
      if (kDebugMode) {
        debugPrint('[Relay] zap → fermeture session ${_short(s.realUrl)}');
      }
      StreamDiagnostics.instance.recordEvent(
        'relay',
        'Changement de chaîne → session précédente fermée '
            '(${StreamDiagnostics.maskCredentials(s.realUrl)})',
      );
      _closeSession(s);
    }
  }

  /// URLs de playlists dont la preuve brute a déjà été journalisée (mpv
  /// re-télécharge la playlist toutes les ~TARGETDURATION secondes en
  /// live : on ne journalise la preuve + les réparations qu'UNE fois
  /// par URL pour ne pas noyer la boîte noire).
  final Set<String> _hlsProvenUrls = <String>{};

  /// URL locale de la PLAYLIST HLS NORMALISÉE pour [realUrl].
  ///
  /// Cause racine terrain (2026-07-08) : mpv lisait la playlist du
  /// panel en « plaintext » (« Failed to recognize file format ») —
  /// `#EXTM3U` absent/décalé (BOM, blancs, \r\n). La route `/hls`
  /// re-télécharge la playlist AMONT à CHAQUE requête de mpv (c'est le
  /// rafraîchissement live : mpv poll selon #EXT-X-TARGETDURATION), la
  /// NORMALISE (HlsPlaylistNormalizer) et la sert avec le bon
  /// Content-Type. Les SEGMENTS restent en DIRECT vers le CDN (URIs
  /// absolues) — seul le petit document texte transite ici.
  Future<String> hlsPlaylistUrlFor(String realUrl) async {
    await _ensureServer();
    // Une seule lecture à la fois : ferme les sessions TS restantes.
    closeOtherPlaybacks(realUrl);
    final String token = Uri.encodeComponent(realUrl);
    return 'http://127.0.0.1:$_port/hls?u=$token';
  }

  /// Sert la playlist normalisée (route `/hls?u=…`).
  Future<void> _serveNormalizedPlaylist(
    HttpRequest req,
    String realUrl,
  ) async {
    final bool firstServe = _hlsProvenUrls.add(realUrl);
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = PlayerSettings.instance.userAgent
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);
    try {
      final HttpClientRequest up =
          await client.getUrl(Uri.parse(realUrl));
      up.followRedirects = true;
      up.maxRedirects = 8;
      final HttpClientResponse resp = await up.close();
      final Uri finalUri = resp.redirects.isEmpty
          ? Uri.parse(realUrl)
          : Uri.parse(realUrl).resolveUri(resp.redirects.last.location);
      final String raw = await resp
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      if (resp.statusCode >= 400) {
        StreamDiagnostics.instance.recordEvent(
          'hls',
          'Playlist amont HTTP ${resp.statusCode} '
              '(${StreamDiagnostics.maskCredentials(realUrl)}) — 502 à mpv',
          level: 'error',
        );
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
        return;
      }
      final NormalizedPlaylist normalized = HlsPlaylistNormalizer.normalize(
        raw,
        finalUri,
        rewriteSubPlaylist: (String abs) =>
            'http://127.0.0.1:$_port/hls?u=${Uri.encodeComponent(abs)}',
      );
      if (firstServe) {
        // PREUVE demandée : les 3 premières lignes BRUTES, octets
        // invisibles rendus visibles + les réparations appliquées.
        StreamDiagnostics.instance.recordEvent(
          'hls',
          '3 premières lignes BRUTES de la playlist amont : '
              '${normalized.rawHead}',
          level: normalized.hadExtM3uAtStart ? 'info' : 'error',
        );
        StreamDiagnostics.instance.recordEvent(
          'hls',
          normalized.repairs.isEmpty
              ? 'Playlist saine (#EXTM3U en position 0) — servie '
                  'normalisée par précaution'
              : 'Playlist RÉPARÉE : ${normalized.repairs.join(' ; ')} — '
                  'servie à mpv en local, segments en direct CDN',
          level: normalized.repairs.isEmpty ? 'info' : 'warn',
        );
      }
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentType =
          ContentType.parse('application/vnd.apple.mpegurl');
      req.response.headers
          .set(HttpHeaders.cacheControlHeader, 'no-cache, no-store');
      req.response.write(normalized.text);
      await req.response.close();
    } catch (e) {
      StreamDiagnostics.instance.recordEvent(
        'hls',
        'Normalisation playlist impossible '
            '(${StreamDiagnostics.maskCredentials(realUrl)}) : $e',
        level: 'error',
      );
      try {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
      } catch (_) {}
    } finally {
      client.close(force: true);
    }
  }

  /// Démarre l'écriture du flux EN COURS vers `filePath`, en se branchant
  /// sur la connexion DÉJÀ ouverte pour la lecture (aucune 2e connexion).
  /// Si aucune session n'existe encore pour cette URL (cas limite), on
  /// l'ouvre. Retourne `false` si l'ouverture du fichier échoue.
  Future<bool> startRecording({
    required String realUrl,
    required String filePath,
  }) async {
    final _RelaySession session = _ensureSession(realUrl);
    _ensureUpstream(session);
    if (session.recordSink != null) {
      // Déjà en train d'enregistrer cette chaîne → on ignore le double-start.
      return true;
    }
    try {
      final File file = File(filePath);
      await file.parent.create(recursive: true);
      session.recordSink = file.openWrite();
      session.recordPath = filePath;
      session.recordBytes = 0;
    } catch (e) {
      if (kDebugMode) debugPrint('[Relay] ouverture fichier KO: $e');
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
    if (session == null || session.recordSink == null) return 0;
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

  Future<void> _ensureServer() async {
    if (_server != null) return;
    // Port 0 = l'OS choisit un port libre. On le mémorise pour fabriquer
    // les URLs locales. Bind sur loopback uniquement (jamais exposé).
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    if (kDebugMode) debugPrint('[Relay] serveur local prêt sur 127.0.0.1:$_port');
    _server!.listen(_handleRequest, onError: (Object e) {
      if (kDebugMode) debugPrint('[Relay] erreur serveur: $e');
    });
  }

  Future<void> _handleRequest(HttpRequest req) async {
    // Deux routes : /s?u=<token> (relais d'octets TS) et /hls?u=<token>
    // (playlist HLS NORMALISÉE — document servi puis connexion fermée,
    // segments en direct CDN). Tout le reste → 404.
    final String? realUrl = req.uri.queryParameters['u'];
    if (req.uri.path == '/hls' && realUrl != null && realUrl.isNotEmpty) {
      await _serveNormalizedPlaylist(req, realUrl);
      return;
    }
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
    if (resp == null) {
      // ÉCHEC DÉFINITIF vs TRANSITOIRE — le cœur du correctif terrain :
      //   - 4xx (404/403/401/410…) dès la 1re réponse, session jamais
      //     diffusée = le serveur a RÉPONDU et refuse CETTE URL. Boucler
      //     ne changera rien : on ferme tout de suite → mpv voit la fin
      //     de flux → le lecteur lance sa sonde + CASCADE DE VARIANTES
      //     (`/live/….m3u8`…) sans attendre 13 retries.
      //   - erreur réseau (DNS/socket/timeout) ou 5xx = transitoire →
      //     le retry avec back-off reste justifié.
      // Un 4xx sur une session qui a DÉJÀ joué garde le comportement
      // reconnexion (token/edge recyclé en cours de live).
      final int? st = session.lastUpstreamStatus;
      final bool definitive = st != null &&
          st >= 400 &&
          st < 500 &&
          st != 408 && // Request Timeout : transitoire
          st != 429; //  Too Many Requests : transitoire
      if (definitive && !session.everStreamed) {
        StreamDiagnostics.instance.recordEvent(
          'relay',
          'HTTP $st définitif dès la 1re réponse → session fermée sans '
              'retry (la cascade de variantes prend la main)',
          level: 'error',
        );
        final String failedUrl = session.realUrl;
        _closeSession(session);
        // APRÈS la fermeture : on prévient explicitement le lecteur
        // (URL réelle, brute) pour qu'il lance sa cascade TOUT DE SUITE
        // — sans attendre que mpv réagisse au flux vide.
        _definitiveFailures.add(failedUrl);
        return;
      }
      _scheduleReconnect(session);
      return;
    }
    session.reconnectFailures = 0;
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
    session.lastUpstreamStatus = null; // nouvelle tentative
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
        ..userAgent = PlayerSettings.instance.userAgent
        // Serveurs IPTV https à certificat auto-signé/expiré : les lecteurs
        // du marché (IBO, VLC…) les acceptent — sans ça, écran noir sur ces
        // sources alors que le flux est bon (cf. iptv_http.dart).
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);

      final HttpClientRequest cReq =
          await session.client!.getUrl(Uri.parse(url));
      cReq.followRedirects = true;
      cReq.maxRedirects = 8;
      cReq.headers.set(HttpHeaders.acceptHeader, '*/*');

      final HttpClientResponse cResp = await cReq.close();
      session.lastUpstreamStatus = cResp.statusCode;
      final String upstreamMime =
          cResp.headers.contentType?.mimeType.toLowerCase() ?? '';
      session.upstreamIsPlaylist = upstreamMime.contains('mpegurl') ||
          Uri.tryParse(url)?.path.toLowerCase().endsWith('.m3u8') == true;
      // Boîte noire : le statut HTTP RÉEL vu par la connexion de lecture
      // (+ URL finale si le serveur a redirigé, + MIME). C'est LA donnée
      // qui manquait pour diagnostiquer un écran noir : l'écran debug
      // caché la montre telle quelle.
      final String finalUrl = cResp.redirects.isEmpty
          ? url
          : cResp.redirects.last.location.toString();
      StreamDiagnostics.instance.recordHttp(
        status: cResp.statusCode,
        finalUrl: finalUrl,
        mime: cResp.headers.contentType?.mimeType,
        source: 'relay',
      );
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
      if (kDebugMode) debugPrint('[Relay] _openUpstream KO: $e');
      StreamDiagnostics.instance.recordHttp(
        error: 'connexion upstream impossible : $e',
        source: 'relay',
      );
      return null;
    }
  }

  void _attachUpstreamListener(
    _RelaySession session,
    HttpClientResponse resp,
  ) {
    session.sub = resp.listen(
      (List<int> chunk) => _fanout(session, chunk),
      onError: (Object e, StackTrace s) {
        if (kDebugMode) debugPrint('[Relay] upstream onError: $e');
        _scheduleReconnect(session);
      },
      onDone: () {
        if (session.upstreamIsPlaylist) {
          // Une playlist HLS est un DOCUMENT : l'EOF est sa fin normale.
          // Reconnecter re-servirait la playlist en boucle à mpv (texte
          // m3u8 concaténé = 0 frame, bug terrain 2026-07-08). On ferme
          // proprement — le HLS se lit en direct, pas via le relais.
          if (kDebugMode) {
            debugPrint('[Relay] playlist HLS servie → fermeture propre');
          }
          StreamDiagnostics.instance.recordEvent(
            'relay',
            'Upstream = playlist HLS (document servi en entier) → session '
                'fermée SANS reconnexion. Le HLS doit être lu en direct '
                'par le lecteur, pas via le relais TS.',
            level: 'warn',
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
    // Premier octet reçu = la session a réellement diffusé : les
    // coupures ULTÉRIEURES redeviennent des reconnexions légitimes
    // (même sur un 4xx — token/edge recyclé en cours de live).
    session.everStreamed = true;
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
          sink.close();
        } catch (_) {}
      }
    }
  }

  /// Reconnexion upstream avec back-off, tant qu'il reste des
  /// consommateurs et qu'on n'a pas trop échoué d'affilée.
  Future<void> _scheduleReconnect(_RelaySession session) async {
    // Plus personne n'écoute → inutile de reconnecter.
    if (!session.hasConsumers) {
      _maybeCloseSession(session);
      return;
    }
    try {
      await session.sub?.cancel();
    } catch (_) {}
    session.sub = null;

    session.reconnectFailures++;
    // Budget adapté : une session qui n'a JAMAIS diffusé un octet
    // n'a droit qu'à quelques retries transitoires — le lecteur doit
    // vite reprendre la main (sonde + cascade) plutôt que d'attendre.
    final int maxFailures = session.everStreamed
        ? _kMaxReconnectFailures
        : _kMaxInitialFailures;
    if (session.reconnectFailures > maxFailures) {
      if (kDebugMode) {
        debugPrint('[Relay] serveur injoignable, abandon ${_short(session.realUrl)}');
      }
      StructuredLogger.instance.warn(
        domain: 'rec',
        event: 'relay.upstream_dead',
        ctx: <String, Object?>{'failures': session.reconnectFailures},
      );
      StreamDiagnostics.instance.recordEvent(
        'relay',
        'Serveur injoignable après ${session.reconnectFailures} tentatives '
            '— abandon de la session',
        level: 'error',
      );
      final bool neverStreamed = !session.everStreamed;
      final String failedUrl = session.realUrl;
      _closeSession(session);
      // Session qui n'a JAMAIS diffusé et que le serveur ignore : on
      // prévient aussi le lecteur — il sondera (diagnostic réseau vs
      // signature) au lieu d'attendre son timeout de démarrage.
      if (neverStreamed) _definitiveFailures.add(failedUrl);
      return;
    }

    StreamDiagnostics.instance.recordEvent(
      'relay',
      'Connexion upstream perdue → reconnexion '
          '#${session.reconnectFailures}',
      level: 'warn',
    );
    final int wait = (2 * session.reconnectFailures).clamp(2, 16);
    await Future<void>.delayed(Duration(seconds: wait));
    if (!session.hasConsumers) {
      _maybeCloseSession(session);
      return;
    }
    await _connectUpstream(session);
  }

  /// Ferme la session si plus aucun consommateur (ni lecteur ni REC).
  void _maybeCloseSession(_RelaySession session) {
    if (session.hasConsumers) return;
    _closeSession(session);
  }

  void _closeSession(_RelaySession session) {
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
        c.res.close();
      } catch (_) {}
      c.markClosed();
    }
    session.players.clear();
    // Si un enregistrement traînait encore, on le ferme proprement.
    final IOSink? sink = session.recordSink;
    session.recordSink = null;
    if (sink != null) {
      try {
        sink.flush().then((_) => sink.close());
      } catch (_) {}
    }
    session.upstreamActive = false;
    _sessions.remove(session.realUrl);
    if (kDebugMode) {
      debugPrint('[Relay] session fermée ${_short(session.realUrl)} '
          '(${_sessions.length} restantes)');
    }
  }

  String _short(String url) =>
      url.length <= 48 ? url : '${url.substring(0, 45)}…';
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
  int reconnectFailures = 0;

  /// Statut HTTP de la DERNIÈRE tentative upstream (null = pas de
  /// réponse : erreur réseau/DNS/timeout). Sert à distinguer un échec
  /// DÉFINITIF (4xx → fermer, laisser la cascade jouer) d'un échec
  /// TRANSITOIRE (retry avec back-off).
  int? lastUpstreamStatus;

  /// `true` dès que la session a diffusé AU MOINS un octet. Avant ça,
  /// un 4xx est définitif et le budget de retry transitoire est réduit.
  bool everStreamed = false;

  /// `true` si l'upstream est une PLAYLIST HLS (mime mpegurl ou URL
  /// .m3u8) : document COURT, pas un flux continu. À l'EOF on ferme
  /// proprement au lieu de « reconnecter » en boucle (le HLS doit être
  /// lu en DIRECT par mpv — cf. HlsPreflight.isHlsUrl côté lecteur).
  bool upstreamIsPlaylist = false;

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
  bool get hasConsumers => players.isNotEmpty || recordSink != null;
}
