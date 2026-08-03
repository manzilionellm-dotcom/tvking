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
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/net/doh_resolver.dart';
import '../../../core/observability/structured_logger.dart';
import 'hls_playlist_normalizer.dart';
import 'player_settings.dart';
import 'stream_diagnostics.dart';
import 'ts_stream_conditioner.dart';

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

/// Un flux TS live est CONTINU : au-delà de ce délai SANS le moindre octet
/// reçu alors que la session diffusait, l'upstream est « silencieux » — il a
/// accepté la connexion puis a cessé d'émettre SANS erreur ni EOF (cas
/// terrain fréquent : edge saturé). Ni `onError` ni `onDone` ne se
/// déclenchent → sans ce garde-fou la session reste figée jusqu'au
/// `idleTimeout` (10 min). On force alors une VRAIE reconnexion amont.
const Duration _kUpstreamStallTimeout = Duration(seconds: 12);

/// Période de la ronde qui surveille le silence d'ingestion ci-dessus.
const Duration _kStallCheckInterval = Duration(seconds: 4);

/// Échec DÉFINITIF annoncé par le relais : l'URL réelle concernée et le
/// dernier statut HTTP vu (`null` = échec réseau / serveur muet, aucune
/// réponse HTTP). Le statut permet au diagnostic de choisir la bonne
/// parade : 403 « slot 1-connexion encore occupé » → backoff + retry ;
/// 404 « mauvais format d'URL » → cascade de variantes directe.
class RelayFailure {
  const RelayFailure({required this.url, this.status});

  final String url;
  final int? status;
}

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
  final StreamController<RelayFailure> _definitiveFailures =
      StreamController<RelayFailure>.broadcast();

  /// Échecs DÉFINITIFS (URL réelle + statut HTTP). Le statut permet au
  /// fallback de distinguer un 403 « connexion encore occupée » (backoff
  /// 3 s + retry, comptes 1-connexion) d'un 404 « mauvais format d'URL »
  /// (cascade de variantes immédiate).
  Stream<RelayFailure> get definitiveFailures => _definitiveFailures.stream;

  /// Sessions actives, indexées par l'URL RÉELLE du flux (la clé est
  /// l'URL upstream, pas l'URL locale). Une session = une chaîne tirée
  /// une seule fois et distribuée à ses consommateurs.
  final Map<String, _RelaySession> _sessions = <String, _RelaySession>{};

  /// Jitter des reconnexions (désynchronise les reprises simultanées).
  final Random _reconnectJitter = Random();

  /// `true` si une chaîne donnée est en cours d'enregistrement via le relais.
  bool isRecording(String realUrl) =>
      _sessions[realUrl]?.recordSink != null;

  /// Débit d'INGESTION mesuré (octets/seconde, fenêtre glissante ~10 s) de
  /// la session de [realUrl]. `null` si pas de session active ou pas assez
  /// de recul pour une moyenne honnête. C'est le capteur du moniteur de
  /// stabilité du lecteur TV : un débit d'arrivée durablement inférieur au
  /// débit nominal du flux = gel imminent → le lecteur peut réagir AVANT
  /// l'écran figé (bascule sur la déclinaison HD/SD de la même chaîne).
  double? ingestBytesPerSecond(String realUrl) =>
      _sessions[realUrl]?.rateMeter.bytesPerSecond(DateTime.now());

  /// Nombre de reconnexions upstream de la session en cours (0 si aucune
  /// session). Deuxième capteur du moniteur de stabilité : des reconnexions
  /// répétées = connexion/serveur instable même si le débit moyen semble bon.
  int upstreamReconnects(String realUrl) =>
      _sessions[realUrl]?.reconnectCount ?? 0;

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

  /// Garde-fou mémoire : si le panel met un jeton de session dans l'URL de
  /// playlist, chaque zap ajoute une entrée unique → croissance continue en
  /// endurance. Au-delà de la borne on repart de zéro (au pire, une preuve
  /// re-journalisée une fois par URL).
  static const int _kMaxProvenUrls = 200;

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
    if (_hlsProvenUrls.length > _kMaxProvenUrls) _hlsProvenUrls.clear();
    final bool firstServe = _hlsProvenUrls.add(realUrl);
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = PlayerSettings.instance.userAgent
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);
    installDohResolution(client, acceptInvalidCertificate: true);
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
      // COURSE (correctif d'audit) : `create` est un point d'`await`. Si le
      // DERNIER lecteur s'est débranché pendant cet await, _maybeCloseSession
      // a pu FERMER la session (recordSink encore null → aucun consommateur)
      // et la retirer de _sessions. Poser recordSink ici l'attacherait alors à
      // une session ORPHELINE (upstream mort, absente de la map) → fichier
      // jamais alimenté + sink jamais fermé (fuite de descripteur). On
      // revérifie donc que la session est TOUJOURS celle enregistrée.
      if (_sessions[realUrl] != session) {
        // La session a été fermée sous nos pieds : on la ré-ouvre proprement
        // (REC seul, sans lecteur, est un cas valide) et on relance l'upstream.
        _sessions[realUrl] = session;
        _ensureUpstream(session);
      }
      final IOSink sink = file.openWrite();
      session.recordSink = sink;
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
    // BLINDAGE (anti-OOM lent) : toute exception qui s'échapperait du
    // corps remontait à `server.listen(onError:...)` qui se contente de
    // logger — la réponse HTTP n'était alors JAMAIS fermée → fuite de
    // socket/descripteur à chaque incident. Sur une petite box qui vit
    // des heures, ces zombies s'accumulent jusqu'au kill mémoire natif.
    // Ici : le corps est enveloppé, et la fermeture de la réponse est
    // GARANTIE quoi qu'il arrive (même patron que local_cast_server).
    try {
      await _handleRequestInner(req);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[Relay] _handleRequest KO: $e');
    } finally {
      try {
        await req.response.close();
      } catch (_) {
        // Déjà fermée (chemin nominal) ou socket morte : rien à faire.
      }
    }
  }

  Future<void> _handleRequestInner(HttpRequest req) async {
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
    // DÉMARRAGE À CHAUD (façon TiviMate / tuner DVB) : si la session a déjà
    // diffusé, on envoie D'ABORD la mémoire des derniers octets (alignée sur
    // une frontière de paquet TS). Le démuxeur retrouve immédiatement
    // PAT/PMT + une image clé récente → quand ExoPlayer re-prépare après un
    // gel ou un retry silencieux, l'image revient en une fraction de seconde
    // au lieu d'attendre les prochaines tables au fil de l'eau (1-3 s
    // d'écran noir en moins). Envoi SYNCHRONE avant l'ajout à la liste des
    // lecteurs : aucun risque d'entrelacement avec le fan-out (mono-thread).
    if (session.everStreamed) {
      final List<int> warmup = session.ring.alignedSnapshot();
      if (warmup.isNotEmpty) {
        try {
          res.add(warmup);
        } catch (_) {
          consumer.markClosed();
        }
      }
    }
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
              'retry (le lecteur décide : backoff 1-connexion ou cascade)',
          level: 'error',
        );
        final String failedUrl = session.realUrl;
        _closeSession(session);
        // APRÈS la fermeture : on prévient explicitement le lecteur
        // (URL réelle brute + statut) pour qu'il décide TOUT DE SUITE —
        // sans attendre que mpv réagisse au flux vide.
        _definitiveFailures.add(RelayFailure(url: failedUrl, status: st));
        return;
      }
      _scheduleReconnect(session);
      return;
    }
    session.reconnectFailures = 0;
    if (session.upstreamIsPlaylist) {
      // Playlist HLS = document texte : ni alignement TS ni mémoire.
      session.aligner = null;
    } else {
      // (Re)connexion TS : un aligneur NEUF jette les octets de milieu de
      // paquet (le serveur repart d'un endroit arbitraire du flux). La
      // mémoire de démarrage à chaud est vidée : son contenu d'AVANT la
      // coupure ne se raccorde plus, octet pour octet, au flux réaligné
      // qui suit (le comptage de frontières deviendrait faux).
      session.aligner = TsSyncAligner();
      session.ring.clear();
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
      installDohResolution(session.client!, acceptInvalidCertificate: true);

      final HttpClientRequest cReq =
          await session.client!.getUrl(Uri.parse(url));
      cReq.followRedirects = true;
      cReq.maxRedirects = 8;
      cReq.headers.set(HttpHeaders.acceptHeader, '*/*');

      // TIMEOUT DE RÉPONSE (correctif d'audit) : connectionTimeout ne borne
      // QUE l'établissement TCP. Un serveur qui ACCEPTE la connexion mais
      // n'envoie jamais les en-têtes (edge saturé) faisait pendre ce
      // `close()` jusqu'à idleTimeout (10 min) — la remontée d'échec et la
      // cascade de variantes du lecteur restaient bloquées. On borne donc
      // l'attente des en-têtes à 20 s : au-delà, on considère l'upstream mort.
      final HttpClientResponse cResp =
          await cReq.close().timeout(const Duration(seconds: 20));
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
      // PLACEHOLDER « ÉCRAN NOIR » : beaucoup de fournisseurs redirigent une
      // ligne EXPIRÉE/BLOQUÉE vers un petit clip noir (black.ts…). Le serveur
      // répond alors 200 + vidéo valide → le lecteur jouerait un écran noir en
      // silence. On le DÉTECTE pour l'écrire noir sur blanc et couper la
      // tempête de reconnexions (cf. _abortIfLineDead).
      if (_isBlockedPlaceholder(finalUrl)) {
        StreamDiagnostics.instance.recordUpstreamPlaceholder(finalUrl);
      }
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

  /// Reconnexion FORCÉE (annule la connexion en cours et en rouvre une
  /// neuve). Déclenchée soit par le watchdog de silence (upstream muet), soit
  /// par le LECTEUR quand il détecte un gel : rouvrir mpv sur la même session
  /// ne suffit pas si l'amont est silencieux — il faut relancer l'amont.
  /// @returns true si une session existait pour [realUrl].
  bool forceReconnect(String realUrl) {
    final _RelaySession? session = _sessions[realUrl];
    if (session == null) return false;
    StreamDiagnostics.instance.recordEvent(
      'relay',
      'Reconnexion amont forcée (gel/silence détecté) — '
          '${StreamDiagnostics.maskCredentials(realUrl)}',
      level: 'warn',
    );
    session.reconnectCount++;
    unawaited(_forceReconnectNow(session));
    return true;
  }

  Future<void> _forceReconnectNow(_RelaySession session) async {
    session.stallTimer?.cancel();
    session.stallTimer = null;
    try { await session.sub?.cancel(); } catch (_) {}
    session.sub = null;
    session.reconnectFailures = 0; // acte volontaire, pas un échec consécutif
    if (!session.hasConsumers) {
      _maybeCloseSession(session);
      return;
    }
    // Ligne morte (compte expiré/banni ou écran noir) → ne pas re-marteler.
    if (_abortIfLineDead(session)) return;
    await _connectUpstream(session);
  }

  /// Filename (sans query) en minuscules pour la détection de placeholder.
  static String _fileNameOf(String url) {
    final Uri? u = Uri.tryParse(url);
    final String path = (u?.path ?? url).toLowerCase();
    final int slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(slash + 1) : path;
  }

  /// `true` si l'URL finale est un flux « écran noir » de fournisseur (ligne
  /// expirée/bloquée). Noms de fichiers connus, jamais un numéro de chaîne
  /// légitime (`1562532.ts`). Volontairement STRICT pour zéro faux positif.
  static bool _isBlockedPlaceholder(String finalUrl) {
    const Set<String> names = <String>{
      'black.ts', 'blocked.ts', 'expired.ts', 'offline.ts', 'noaccess.ts',
      'no_access.ts', 'unavailable.ts', 'notavailable.ts', 'blackscreen.ts',
      'block.ts', 'noservice.ts',
    };
    return names.contains(_fileNameOf(finalUrl));
  }

  /// Si le COMPTE est mort (expiré/banni) ou que le fournisseur ne sert qu'un
  /// écran noir, reconnecter est FUTILE : on ferme la session, on signale
  /// l'échec DÉFINITIF (→ le lecteur affiche « abonnement expiré, renouvelle »)
  /// et on renvoie `true`. Sinon `false` (reconnexion normale). Le cas « limite
  /// de connexions » (458) N'est PAS mort : l'autre écran peut se libérer → on
  /// continue de réessayer.
  bool _abortIfLineDead(_RelaySession session) {
    final StreamBlockReason r = StreamDiagnostics.instance.blockReason;
    if (r != StreamBlockReason.expired && r != StreamBlockReason.banned) {
      return false;
    }
    StreamDiagnostics.instance.recordEvent(
      'relay',
      'Abonnement expiré/bloqué (compte) — reconnexions ARRÊTÉES : inutile de '
          'marteler une ligne morte (le fournisseur ne sert qu\'un écran noir). '
          'Renouvelle la ligne auprès du fournisseur.',
      level: 'error',
    );
    final String failedUrl = session.realUrl;
    final int? lastStatus = session.lastUpstreamStatus;
    _closeSession(session);
    _definitiveFailures.add(RelayFailure(url: failedUrl, status: lastStatus));
    return true;
  }

  /// (Re)arme la ronde qui détecte un upstream silencieux. Idempotent.
  void _armStallWatch(_RelaySession session) {
    session.stallTimer?.cancel();
    session.lastByteAt = DateTime.now(); // point de départ propre
    session.stallTimer = Timer.periodic(_kStallCheckInterval, (_) {
      // Playlist HLS = document (pas de flux continu) ; avant le 1er octet
      // c'est le timeout de démarrage du lecteur qui gère ; plus personne
      // n'écoute = rien à surveiller.
      if (session.upstreamIsPlaylist ||
          !session.everStreamed ||
          !session.hasConsumers) {
        return;
      }
      final DateTime? last = session.lastByteAt;
      if (last == null) return;
      if (DateTime.now().difference(last) >= _kUpstreamStallTimeout) {
        StreamDiagnostics.instance.recordEvent(
          'watchdog',
          'Upstream silencieux ${_kUpstreamStallTimeout.inSeconds} s (ni '
              'octet ni erreur) → reconnexion amont forcée',
          level: 'warn',
        );
        session.reconnectCount++;
        unawaited(_forceReconnectNow(session));
      }
    });
  }

  void _attachUpstreamListener(
    _RelaySession session,
    HttpClientResponse resp,
  ) {
    _armStallWatch(session);
    session.sub = resp.listen(
      (List<int> chunk) => _fanout(session, chunk),
      onError: (Object e, StackTrace s) {
        if (kDebugMode) debugPrint('[Relay] upstream onError: $e');
        session.reconnectCount++;
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
        session.reconnectCount++;
        _scheduleReconnect(session);
      },
      cancelOnError: true,
    );
  }

  /// Recopie un paquet vers TOUS les consommateurs : le(s) lecteur(s) et
  /// le fichier d'enregistrement s'il est actif.
  void _fanout(_RelaySession session, List<int> chunk) {
    // HYGIÈNE TS : après chaque (re)connexion, l'aligneur jette les octets
    // de milieu de paquet (le décodeur ne doit JAMAIS voir un demi-paquet
    // collé au flux précédent — artefacts, voire décrochage complet).
    // Les playlists HLS (aligner == null) passent telles quelles.
    List<int> data = chunk;
    final TsSyncAligner? aligner = session.aligner;
    if (aligner != null) {
      data = aligner.feed(chunk);
      if (data.isEmpty) return; // toujours en recherche de synchro
    }
    // Premier octet reçu = la session a réellement diffusé : les
    // coupures ULTÉRIEURES redeviennent des reconnexions légitimes
    // (même sur un 4xx — token/edge recyclé en cours de live).
    session.everStreamed = true;
    session.lastByteAt = DateTime.now(); // watchdog de silence d'ingestion
    // Débitmètre (capteur du moniteur de stabilité TV) + mémoire de
    // démarrage à chaud (burst servi aux lecteurs qui se rebranchent).
    session.rateMeter.addBytes(data.length, DateTime.now());
    if (aligner != null) session.ring.add(data);
    // Lecteurs : on écrit, on retire ceux dont la socket est morte.
    final List<_PlayerConsumer> dead = <_PlayerConsumer>[];
    for (final _PlayerConsumer c in session.players) {
      if (c.isClosed) {
        dead.add(c);
        continue;
      }
      try {
        c.res.add(data);
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
        sink.add(data);
        session.recordBytes += data.length;
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
    // Ligne morte (compte expiré/banni ou écran noir) → on ARRÊTE la tempête de
    // reconnexions et on affiche le message clair, au lieu de marteler en
    // boucle une ligne qui ne reviendra pas (cf. journal : black.ts + Expired).
    if (_abortIfLineDead(session)) return;
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
      final int? lastStatus = session.lastUpstreamStatus;
      _closeSession(session);
      // Session qui n'a JAMAIS diffusé et que le serveur ignore : on
      // prévient aussi le lecteur — il sondera (diagnostic réseau vs
      // signature) au lieu d'attendre son timeout de démarrage.
      if (neverStreamed) {
        _definitiveFailures
            .add(RelayFailure(url: failedUrl, status: lastStatus));
      }
      return;
    }

    StreamDiagnostics.instance.recordEvent(
      'relay',
      'Connexion upstream perdue → reconnexion '
          '#${session.reconnectFailures}',
      level: 'warn',
    );
    // Back-off + JITTER (correctif d'audit) : plusieurs sessions (lecture +
    // enregistrement(s)) qui reconnectent EN PHASE martelaient un panel qui
    // rate-limite. On garde le back-off croissant borné [2 s ; 16 s] mais on
    // ajoute un jitter aléatoire (0-1000 ms) pour désynchroniser les reprises.
    final int base = (2 * session.reconnectFailures).clamp(2, 16);
    final int jitterMs = _reconnectJitter.nextInt(1000);
    await Future<void>.delayed(
        Duration(seconds: base, milliseconds: jitterMs));
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
    session.stallTimer?.cancel();
    session.stallTimer = null;
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

  /// Nombre TOTAL de pertes de connexion upstream depuis l'ouverture de la
  /// session (≠ [reconnectFailures] qui compte les échecs CONSÉCUTIFS et
  /// retombe à 0 dès qu'une reconnexion réussit). Capteur du moniteur de
  /// stabilité du lecteur TV.
  int reconnectCount = 0;

  /// Réaligneur TS de la CONNEXION EN COURS (recréé à chaque (re)connexion,
  /// null pour une playlist HLS). Garantit que lecteurs/fichier ne voient
  /// jamais un demi-paquet après une coupure serveur.
  TsSyncAligner? aligner;

  /// Horodatage du DERNIER octet reçu de l'upstream. Alimente le watchdog de
  /// silence d'ingestion (upstream qui se tait sans erreur ni EOF).
  DateTime? lastByteAt;

  /// Ronde périodique qui détecte un upstream silencieux (voir
  /// [_kUpstreamStallTimeout]) et force une reconnexion.
  Timer? stallTimer;

  /// Mémoire glissante des derniers octets alignés : burst de démarrage à
  /// chaud pour un lecteur qui se (re)branche (image de retour quasi
  /// instantanée après un gel, cf. _handleRequest).
  final TsRingBuffer ring = TsRingBuffer();

  /// Débit d'ingestion (fenêtre glissante) — exposé au lecteur TV via
  /// [LocalStreamRelay.ingestBytesPerSecond].
  final IngestRateMeter rateMeter = IngestRateMeter();

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
