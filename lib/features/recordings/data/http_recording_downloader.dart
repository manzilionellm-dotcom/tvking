// =========================================================
//  http_recording_downloader.dart — Downloader HTTP en Dart pur
// =========================================================
//  Remplace l'API libmpv `stream-record` qui s'avère silencieusement
//  inopérante sur les flux IPTV de l'utilisateur (constaté empiriquement :
//  setProperty retourne sans erreur mais le .ts reste à 0 octets,
//  y compris sur des flux bénins comme BFM TV testés 3 minutes).
//
//  Approche : on ouvre nous-mêmes une 2e connexion HTTP vers l'URL du
//  flux, on lit les bytes en streaming, on les écrit dans un fichier
//  local. Aucune dépendance à libmpv pour l'enregistrement.
//
//  Inconvénient : double bande passante (le player tire la 1ère
//  connexion pour lire, on tire la 2e pour enregistrer). Certains
//  fournisseurs IPTV limitent à 1 connexion/credentials — dans ce
//  cas l'une des deux pourrait être éjectée. À surveiller en test.
//
//  Avantage : on contrôle TOUT, on peut reporter la taille en temps
//  réel, et libmpv ne nous bloque plus silencieusement.
//
//  V2 — Recordings parallèles :
//    L'user a demandé "ajoute que je peux enregistrer plus de
//    10 chaînes en même temps". On garde l'API publique singleton
//    mais en interne on maintient une `Map<String, _Job>` keyed
//    par filePath. Chaque job possède son propre HttpClient,
//    StreamSubscription, IOSink et compteur de bytes — totalement
//    isolés les uns des autres.
//
//    start(streamUrl, filePath) crée un nouveau job (sans toucher
//    aux autres). stop(filePath) arrête juste celui demandé.
//    stop() sans argument = arrête TOUT (legacy fallback).
//
//    Pas de limite logicielle au nombre de jobs simultanés ; la
//    limite réelle = nb de sockets que l'OS autorise (~1000) et
//    surtout la bande passante / limite du fournisseur IPTV.
//
//  V3 — Enregistrements longue durée (jusqu'à 6 h) :
//    PROBLÈME constaté par l'utilisateur : l'app affiche bien
//    "enregistrement en cours" mais le fichier ne grossit plus
//    après ~2 minutes. Cause racine : les CDN / serveurs Xtream
//    FERMENT périodiquement la socket HTTP (recyclage de connexion,
//    fin d'un buffer côté edge, load-balancer qui rebascule…).
//    Quand ça arrive, le `Stream` Dart émet `onDone` → l'ancien
//    code nettoyait le job → l'enregistrement s'arrêtait en silence.
//
//    CORRECTIF : pour un flux LIVE, `onDone` ne veut PAS dire "fin
//    de l'émission", ça veut dire "le serveur a coupé, reconnecte".
//    On rouvre donc une nouvelle connexion HTTP et on CONTINUE à
//    écrire dans le MÊME fichier (le .ts est concaténable, comme le
//    font ffmpeg / TiviMate). On ne s'arrête réellement que sur :
//      - un stop() explicite de l'utilisateur,
//      - le plafond de 6 h atteint (kMaxRecordingDuration),
//      - trop d'échecs de reconnexion consécutifs (serveur mort).
//
//    Un Timer par job déclenche l'auto-stop à 6 h. La limite évite
//    qu'un enregistrement oublié remplisse le stockage du téléphone.
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/observability/structured_logger.dart';

/// Durée maximale d'un enregistrement. Demande user : enregistrements
/// ILLIMITÉS. On garde un garde-fou très haut (30 jours) — purement
/// anti-fuite si l'utilisateur oublie d'appuyer sur stop ; en pratique
/// le stockage du téléphone se remplit bien avant. Aucune limite
/// fonctionnelle ressentie par l'utilisateur.
const Duration kMaxRecordingDuration = Duration(days: 30);

/// Nombre d'échecs de reconnexion CONSÉCUTIFS tolérés avant
/// d'abandonner un job. Tant qu'au moins une reconnexion réussit, ce
/// compteur est remis à zéro — donc un flux qui hoquette toute la nuit
/// continue indéfiniment. On n'abandonne que si le serveur est
/// vraiment injoignable plusieurs essais d'affilée.
const int _kMaxReconnectFailures = 12;

/// Phase 1 / F-02 : nombre d'erreurs CONSÉCUTIVES sur `sink.add` tolérées
/// avant de couper le job avec [AutoStopReason.diskError].
///
/// Pourquoi un seuil et pas une coupure immédiate :
///   - Une 1ʳᵉ erreur peut etre transitoire (filesystem qui re-mount,
///     remount externe SD card juste apres ejection, etc.).
///   - On veut surtout proteger contre le cas "le disque est plein,
///     l'erreur se repete au prochain chunk" — qui se manifeste par N
///     erreurs d'affilee.
///
/// 5 = compromis : assez petit pour ne pas gaspiller 30s de data,
/// assez grand pour absorber un hoquet ponctuel. Ajustable.
const int _kMaxConsecutiveSinkErrors = 5;

/// Phase 1 / F-03 : motif d'arret automatique. Permet a l'UI de
/// distinguer les trois causes possibles et d'afficher un message
/// adapte (au lieu du "limite de 6 h atteinte" generique trompeur).
enum AutoStopReason {
  /// Plafond [kMaxRecordingDuration] atteint — comportement normal,
  /// l'utilisateur a juste oublie d'arreter.
  maxDurationReached,

  /// Serveur upstream injoignable apres [_kMaxReconnectFailures]
  /// reconnexions consecutives qui ont toutes echoue. Le flux est
  /// probablement mort (provider down, token expire, internet coupe).
  serverUnreachable,

  /// Echec d'ecriture disque (stockage plein, SD card ejectee, droits
  /// retires). Le fichier .ts est tronque a la derniere ecriture reussie.
  diskError,
}

/// Décodeur UTF-8 tolérant aux octets invalides. Sert à lire le
/// corps texte d'une playlist HLS .m3u8 sans crasher si un segment
/// non-UTF-8 traîne (rare mais arrive sur certains serveurs IPTV
/// qui encodent des accents en Latin-1).
const Utf8Decoder _utf8Lenient = Utf8Decoder(allowMalformed: true);

/// Singleton qui orchestre N jobs d'enregistrement parallèles.
/// Chaque "job" = une chaîne en cours de capture (1 connexion HTTP
/// dédiée + 1 IOSink dédié vers son fichier .ts).
class HttpRecordingDownloader {
  HttpRecordingDownloader._();
  static final HttpRecordingDownloader instance = HttpRecordingDownloader._();

  /// Jobs actifs, keyed par filePath (unique par recording).
  final Map<String, _Job> _jobs = <String, _Job>{};

  /// `true` si au moins un job est actif (utile pour le ForegroundService :
  /// on le maintient en vie tant qu'au moins 1 enregistrement tourne).
  bool get isRecording => _jobs.isNotEmpty;

  /// Nombre de recordings en cours en parallèle.
  int get activeCount => _jobs.length;

  /// `true` si ce filePath précis est en cours d'enregistrement.
  bool isRecordingFile(String filePath) => _jobs.containsKey(filePath);

  /// Total cumulé de tous les jobs actifs (utile pour debug).
  int get bytesWritten {
    int sum = 0;
    for (final _Job j in _jobs.values) {
      sum += j.bytesWritten;
    }
    return sum;
  }

  /// Bytes écrits pour un fichier précis (0 si pas trouvé).
  int bytesWrittenFor(String filePath) =>
      _jobs[filePath]?.bytesWritten ?? 0;

  /// Démarre un nouveau job d'enregistrement vers `filePath`.
  /// Plusieurs jobs peuvent coexister tant qu'ils écrivent dans
  /// des fichiers différents. Retourne `false` si :
  ///   - ce filePath est DÉJÀ en cours (double-start ignoré)
  ///   - la requête HTTP échoue après tous les retries
  ///   - l'ouverture du fichier échoue
  ///
  /// [onAutoStopped] est appelé UNIQUEMENT quand le job se termine
  /// de lui-même (plafond de 6 h atteint, ou serveur définitivement
  /// injoignable après plusieurs reconnexions, OU echec disque
  /// consecutif depuis Phase 1). Il N'est PAS appelé quand
  /// l'utilisateur fait stop() lui-même. Permet à l'UI de finaliser
  /// la fiche en base et de retirer le badge "REC".
  ///
  /// Le second argument [AutoStopReason] indique la cause precise — l'UI
  /// adapte son message ("limite 6h" vs "serveur injoignable" vs
  /// "stockage plein"). Phase 1 / F-03.
  Future<bool> start({
    required String streamUrl,
    required String filePath,
    void Function(String filePath, AutoStopReason reason)? onAutoStopped,
  }) async {
    if (_jobs.containsKey(filePath)) {
      if (kDebugMode) debugPrint('[Rec] $filePath déjà en cours');
      return false;
    }

    // ----- Détection du format -----
    // Les flux IPTV viennent en 2 formats principaux :
    //   - MPEG-TS brut (.ts) : 1 seule URL, 1 connexion continue,
    //     on écrit tous les bytes au fil de l'eau dans un fichier.
    //   - HLS (.m3u8) : une playlist qui pointe vers des segments
    //     .ts numérotés. Le serveur met à jour la playlist toutes
    //     les ~10s avec de nouveaux segments. On polle, on
    //     télécharge les nouveaux, on les concatène.
    //
    // Tivimate, OBS, ffmpeg font pareil. Sans ce branchement,
    // un enregistrement .m3u8 donnait juste le texte de la
    // playlist au lieu de la vidéo → 0 bytes vidéo utilisables.
    final bool isHls = streamUrl.toLowerCase().contains('.m3u8');
    if (isHls) {
      return _startHls(
        streamUrl: streamUrl,
        filePath: filePath,
        onAutoStopped: onAutoStopped,
      );
    }
    return _startRaw(
      streamUrl: streamUrl,
      filePath: filePath,
      onAutoStopped: onAutoStopped,
    );
  }

  /// Pipeline classique : flux MPEG-TS live tiré en 1 GET HTTP qui
  /// dure tant que le serveur envoie des bytes. On streame directement
  /// dans le fichier sans buffer mémoire.
  ///
  /// Nouveauté V3 : si le serveur ferme la socket (onDone) ou qu'une
  /// erreur réseau survient (onError), on NE s'arrête PAS — on rouvre
  /// une connexion et on continue d'écrire dans le même fichier, tant
  /// qu'on n'a pas dépassé 6 h ni reçu de stop() explicite. C'est ça
  /// qui corrige le bug "l'enregistrement s'arrête au bout de 2 min".
  Future<bool> _startRaw({
    required String streamUrl,
    required String filePath,
    void Function(String filePath, AutoStopReason reason)? onAutoStopped,
  }) async {
    final _Job job = _Job(filePath: filePath, streamUrl: streamUrl)
      ..onAutoStopped = onAutoStopped;

    // 1) On ouvre le fichier de sortie AVANT toute connexion. Il
    //    restera ouvert pendant toute la durée de l'enregistrement,
    //    y compris à travers les reconnexions (on append).
    try {
      final File file = File(filePath);
      await file.parent.create(recursive: true);
      job.sink = file.openWrite();
    } catch (e) {
      if (kDebugMode) debugPrint('[Rec] ouverture fichier KO ($filePath): $e');
      await _stopJob(job);
      return false;
    }

    // 2) Première connexion. Si elle échoue d'emblée, on rend false
    //    pour que l'UI affiche l'erreur (serveur injoignable / refus).
    final HttpClientResponse? resp = await _openRawConnection(job, streamUrl);
    if (resp == null) {
      await _stopJob(job);
      return false;
    }

    // 3) Le job est officiellement actif. On programme l'auto-stop à
    //    6 h et on branche l'écoute des bytes.
    _jobs[filePath] = job;
    _armMaxDurationTimer(job);
    _attachRawListener(job, streamUrl, resp);

    if (kDebugMode) {
      debugPrint(
          '[Rec] raw downloader started → $filePath (${_jobs.length} actifs)');
    }
    StructuredLogger.instance.info(
      domain: 'rec',
      event: 'job.start',
      ctx: <String, Object?>{
        'filePath': filePath,
        'pipeline': 'raw',
        'activeCount': _jobs.length,
      },
    );
    return true;
  }

  /// Ouvre (ou rouvre) une connexion HTTP brute vers le flux et
  /// retourne la réponse prête à être écoutée, ou `null` si le
  /// serveur refuse / est injoignable. Réutilisable pour la 1ère
  /// connexion ET pour chaque reconnexion.
  Future<HttpClientResponse?> _openRawConnection(
    _Job job,
    String streamUrl,
  ) async {
    try {
      // On repart d'un HttpClient neuf à chaque (re)connexion : plus
      // sûr que de réutiliser un client dont la socket vient de mourir.
      try {
        job.client?.close(force: true);
      } catch (_) {}
      job.client = HttpClient()
        // 30s pour ouvrir la socket — certains serveurs Xtream
        // sont lents à répondre la première fois.
        ..connectionTimeout = const Duration(seconds: 30)
        // 10 min sans bytes avant de fermer — les flux live ont
        // parfois des creux entre segments, ne pas couper trop vite.
        ..idleTimeout = const Duration(minutes: 10)
        // CRITIQUE : sinon dart:io décompresse les bytes en gzip et
        // on enregistre du binaire CASSÉ au lieu du MPEG-TS brut.
        ..autoUncompress = false
        // User-Agent IDENTIQUE à celui du lecteur (mpv user-agent) pour
        // ne pas se faire bloquer (403) par les Xtream à whitelist stricte.
        ..userAgent = 'VLC/3.0.18 LibVLC/3.0.18';

      final HttpClientRequest req =
          await job.client!.getUrl(Uri.parse(streamUrl));
      // CRITIQUE : sans ces 2 lignes, dart:io NE SUIT PAS les
      // redirects 302/307 que font tous les serveurs Xtream pour
      // router vers l'edge le plus proche. La requête échoue
      // silencieusement avec un body vide.
      req.followRedirects = true;
      req.maxRedirects = 8;
      req.headers.set(HttpHeaders.acceptHeader, '*/*');

      final HttpClientResponse resp = await req.close();
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        if (kDebugMode) {
          debugPrint('[Rec] HTTP ${resp.statusCode} sur $streamUrl');
        }
        try {
          job.client?.close(force: true);
        } catch (_) {}
        return null;
      }
      return resp;
    } catch (e) {
      if (kDebugMode) debugPrint('[Rec] _openRawConnection KO: $e');
      return null;
    }
  }

  /// Branche l'écoute des bytes d'une réponse HTTP sur le sink du job.
  /// À la moindre fin de flux (onDone) ou erreur (onError), on tente
  /// une reconnexion au lieu d'arrêter — sauf si stop() a été demandé.
  void _attachRawListener(
    _Job job,
    String streamUrl,
    HttpClientResponse resp,
  ) {
    job.sub = resp.listen(
      (List<int> chunk) {
        try {
          job.sink?.add(chunk);
          job.bytesWritten += chunk.length;
          // Une ecriture reussie remet a 0 le compteur d'erreurs disque
          // — un hoquet ponctuel n'abat pas le job.
          if (job.sinkErrorCount != 0) {
            job.sinkErrorCount = 0;
          }
        } catch (e) {
          // Phase 1 / F-02 : on COMPTE chaque echec de sink.add.
          // Au-dela du seuil, on coupe proprement avec
          // AutoStopReason.diskError pour ne PAS continuer a tirer
          // de la bande passante en ecrivant dans le vide.
          job.sinkErrorCount++;
          if (kDebugMode) {
            debugPrint(
                '[Rec] sink write error (${job.sinkErrorCount}/$_kMaxConsecutiveSinkErrors) '
                '${job.filePath}: $e');
          }
          StructuredLogger.instance.warn(
            domain: 'rec',
            event: 'job.disk_error',
            ctx: <String, Object?>{
              'filePath': job.filePath,
              'consecutive': job.sinkErrorCount,
              'bytesWritten': job.bytesWritten,
              'error': e.toString(),
            },
          );
          if (job.sinkErrorCount >= _kMaxConsecutiveSinkErrors) {
            _autoFinish(job.filePath, AutoStopReason.diskError);
          }
        }
      },
      onError: (Object e, StackTrace s) {
        if (kDebugMode) debugPrint('[Rec] stream error (${job.filePath}): $e');
        // cancelOnError:true → la souscription est terminée après
        // cette erreur, on enchaîne sur une reconnexion.
        _reconnectRaw(job, streamUrl);
      },
      onDone: () {
        if (kDebugMode) {
          debugPrint(
              '[Rec] socket fermée par le serveur (${job.filePath}), '
              '${job.bytesWritten} bytes — tentative de reconnexion');
        }
        _reconnectRaw(job, streamUrl);
      },
      // true : après une erreur, la souscription se termine et c'est
      // NOUS qui décidons de reconnecter (évite le double-déclenchement
      // onError + onDone sur la même souscription).
      cancelOnError: true,
    );
  }

  /// Rouvre une connexion et reprend l'écriture dans le même fichier.
  /// Appelée quand le serveur a coupé. S'arrête définitivement si :
  ///   - stop() a été demandé entre-temps (job.stopping),
  ///   - le job n'est plus dans la map (déjà nettoyé),
  ///   - on a dépassé 6 h,
  ///   - trop d'échecs de reconnexion consécutifs.
  Future<void> _reconnectRaw(_Job job, String streamUrl) async {
    if (job.stopping || !_jobs.containsKey(job.filePath)) return;

    // Plafond 6 h — on finalise proprement.
    if (job.elapsed >= kMaxRecordingDuration) {
      if (kDebugMode) {
        debugPrint('[Rec] plafond 6 h atteint sur ${job.filePath}');
      }
      _autoFinish(job.filePath, AutoStopReason.maxDurationReached);
      return;
    }

    // On annule la souscription morte (le client sera recréé dans
    // _openRawConnection). Le sink reste ouvert : on append.
    try {
      await job.sub?.cancel();
    } catch (_) {}
    job.sub = null;

    // Petit délai avant de retaper le serveur (évite le hammering
    // si le serveur est en train de rebasculer d'edge).
    await Future<void>.delayed(const Duration(seconds: 2));
    if (job.stopping || !_jobs.containsKey(job.filePath)) return;

    final HttpClientResponse? resp = await _openRawConnection(job, streamUrl);
    if (resp == null) {
      job.reconnectFailures++;
      StructuredLogger.instance.warn(
        domain: 'rec',
        event: 'job.reconnect_fail',
        ctx: <String, Object?>{
          'filePath': job.filePath,
          'consecutiveFailures': job.reconnectFailures,
          'maxFailures': _kMaxReconnectFailures,
        },
      );
      if (job.reconnectFailures >= _kMaxReconnectFailures) {
        if (kDebugMode) {
          debugPrint('[Rec] serveur injoignable, abandon ${job.filePath}');
        }
        _autoFinish(job.filePath, AutoStopReason.serverUnreachable);
        return;
      }
      // Back-off progressif : 2s, 4s, 6s… plafonné à 16s.
      final int wait = (2 * job.reconnectFailures).clamp(2, 16);
      await Future<void>.delayed(Duration(seconds: wait));
      return _reconnectRaw(job, streamUrl);
    }

    // Reconnexion réussie → on repart de zéro côté compteur d'échecs.
    job.reconnectFailures = 0;
    job.reconnectCount++;
    if (kDebugMode) {
      debugPrint(
          '[Rec] reconnecté ${job.filePath} '
          '(reconnexion #${job.reconnectCount}, ${job.bytesWritten} bytes)');
    }
    StructuredLogger.instance.info(
      domain: 'rec',
      event: 'job.reconnect_success',
      ctx: <String, Object?>{
        'filePath': job.filePath,
        'reconnectCount': job.reconnectCount,
        'bytesWritten': job.bytesWritten,
      },
    );
    _attachRawListener(job, streamUrl, resp);
  }

  /// Pipeline HLS : on polle la playlist toutes les 5 s, on
  /// télécharge les segments .ts qu'on n'a pas encore vus, et on
  /// les concatène dans le fichier de sortie. Tourne en boucle
  /// jusqu'au stop() ou jusqu'à 3 erreurs consécutives.
  Future<bool> _startHls({
    required String streamUrl,
    required String filePath,
    void Function(String filePath, AutoStopReason reason)? onAutoStopped,
  }) async {
    final _Job job = _Job(filePath: filePath, streamUrl: streamUrl)
      ..onAutoStopped = onAutoStopped;
    try {
      job.client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..idleTimeout = const Duration(minutes: 2)
        ..autoUncompress = false
        ..userAgent = 'VLC/3.0.20 LibVLC/3.0.20';

      // Test rapide : la playlist répond-elle ?
      final HttpClientResponse probe = await _httpGet(
        job.client!,
        Uri.parse(streamUrl),
      );
      if (probe.statusCode != 200) {
        job.client?.close(force: true);
        return false;
      }
      await probe.drain<void>();

      final File file = File(filePath);
      await file.parent.create(recursive: true);
      job.sink = file.openWrite();
      _jobs[filePath] = job;
      _armMaxDurationTimer(job);

      // Boucle de poll/download en arrière-plan. On ne await pas —
      // start() doit rendre la main immédiatement pour que l'UI
      // affiche 'enregistrement démarré'.
      _runHlsLoop(streamUrl: streamUrl, filePath: filePath, job: job);

      if (kDebugMode) {
        debugPrint(
            '[Rec] HLS downloader started → $filePath (${_jobs.length} actifs)');
      }
      StructuredLogger.instance.info(
        domain: 'rec',
        event: 'job.start',
        ctx: <String, Object?>{
          'filePath': filePath,
          'pipeline': 'hls',
          'activeCount': _jobs.length,
        },
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Rec] _startHls failed ($filePath): $e');
      _cleanupJob(filePath);
      return false;
    }
  }

  /// Boucle qui polle la playlist HLS et télécharge les segments.
  /// Tourne jusqu'à un stop() explicite OU le plafond de 6 h. Comme
  /// pour le pipeline raw, une coupure serveur ne tue plus le
  /// recording : on tolère beaucoup d'erreurs consécutives (le live
  /// peut hoqueter longtemps) et on n'abandonne que si le serveur
  /// reste injoignable un long moment d'affilée.
  Future<void> _runHlsLoop({
    required String streamUrl,
    required String filePath,
    required _Job job,
  }) async {
    final Uri masterUri = Uri.parse(streamUrl);
    // URL de la media playlist EFFECTIVE. Resolue une fois depuis la
    // master playlist (correctif bug #1) : sans ca, _parseHlsSegments
    // prenait les sous-.m3u8 d'une master pour des "segments" et
    // enregistrait du TEXTE de playlist au lieu de la video -> ecran noir.
    Uri mediaUri = masterUri;
    bool resolvedMedia = false;
    int consecutiveErrors = 0;

    // Phase 1 / F-03 : on tracke la raison qui fera sortir de la
    // boucle pour propager au callback. Par defaut on assume le
    // serveur mort (cas le plus frequent dans la pratique IPTV) ; le
    // plafond 6 h ecrit explicitement maxDurationReached avant break.
    AutoStopReason exitReason = AutoStopReason.serverUnreachable;

    while (_jobs.containsKey(filePath) && !job.stopping) {
      // Plafond 6 h.
      if (job.elapsed >= kMaxRecordingDuration) {
        if (kDebugMode) {
          debugPrint('[Rec] plafond 6 h atteint sur $filePath (HLS)');
        }
        exitReason = AutoStopReason.maxDurationReached;
        break;
      }
      try {
        // Resolution de la media playlist (une seule fois), en
        // descendant la master via la variante de plus haute bande
        // passante (BANDWIDTH). Pour une media playlist directe, rien
        // ne change : _isMasterPlaylist renvoie false.
        if (!resolvedMedia) {
          final String head = await _fetchPlaylist(job.client!, masterUri);
          if (_isMasterPlaylist(head)) {
            final Uri? v = _selectVariant(head, masterUri);
            if (v != null) mediaUri = v;
          }
          resolvedMedia = true;
        }

        final String body = await _fetchPlaylist(job.client!, mediaUri);
        // Securite : si la "variante" choisie est elle-meme une master
        // (master imbriquee, tres rare) on redescend d'un niveau.
        if (_isMasterPlaylist(body)) {
          final Uri? v = _selectVariant(body, mediaUri);
          if (v != null) mediaUri = v;
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        final List<String> segments = _parseHlsSegments(body, mediaUri);

        // On télécharge UNIQUEMENT les segments pas encore vus.
        // Beaucoup de duplicates sinon (la playlist live garde
        // ~3-6 segments dans une fenêtre glissante).
        int newlyDownloaded = 0;
        for (final String segUrl in segments) {
          if (!_jobs.containsKey(filePath) || job.stopping) break;
          if (job.seenSegments.contains(segUrl)) continue;
          job.seenSegments.add(segUrl);
          await _downloadSegment(job, segUrl);
          newlyDownloaded++;
        }
        consecutiveErrors = 0; // un cycle réussi, on reset

        // HLS recommande de re-poll au demi du target duration
        // (~5s en pratique pour la plupart des flux). Si on a déjà
        // downloadé plein de segments, on poll plus vite pour
        // rattraper le live, sinon on attend 5s.
        await Future<void>.delayed(Duration(
          seconds: newlyDownloaded > 0 ? 3 : 5,
        ));
      } catch (e) {
        consecutiveErrors++;
        if (kDebugMode) {
          debugPrint(
              '[Rec] HLS loop error '
              '($consecutiveErrors/$_kMaxReconnectFailures) on $filePath: $e');
        }
        // On n'abandonne qu'après BEAUCOUP d'erreurs d'affilée
        // (serveur vraiment mort), avec back-off progressif.
        if (consecutiveErrors >= _kMaxReconnectFailures) {
          if (kDebugMode) {
            debugPrint('[Rec] serveur HLS injoignable, abandon $filePath');
          }
          break;
        }
        final int wait = (2 * consecutiveErrors).clamp(2, 16);
        await Future<void>.delayed(Duration(seconds: wait));
      }
    }

    if (kDebugMode) {
      debugPrint(
          '[Rec] HLS loop EXITED for $filePath '
          '(${job.bytesWritten} bytes, errors=$consecutiveErrors, '
          'reason=${exitReason.name})');
    }
    // Si on sort de la boucle alors que ce n'était PAS un stop()
    // explicite, c'est un auto-stop (6 h ou serveur mort ou diskError
    // declenche depuis _downloadSegment) → on prévient l'UI.
    // Sinon stop() s'occupe déjà de tout.
    if (!job.stopping) {
      // _downloadSegment a peut-etre deja appele _autoFinish suite a
      // une rafale d'erreurs disque ; dans ce cas le job a deja ete
      // retire de _jobs et le second _autoFinish sera no-op.
      _autoFinish(filePath, exitReason);
    }
  }

  /// Helper : GET HTTP avec follow redirects activé. Indispensable
  /// pour les CDN qui rebondissent vers l'edge le plus proche.
  Future<HttpClientResponse> _httpGet(HttpClient client, Uri uri) async {
    final HttpClientRequest req = await client.getUrl(uri);
    req.followRedirects = true;
    req.maxRedirects = 8;
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    return req.close();
  }

  /// Récupère le corps texte d'une playlist (.m3u8). Suit les
  /// redirects. Utilisé pour la master ET la media playlist.
  Future<String> _fetchPlaylist(HttpClient client, Uri uri) async {
    final HttpClientResponse resp = await _httpGet(client, uri);
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      // On draine pour libérer la socket avant de lever.
      await resp.drain<void>();
      throw HttpException('HTTP ${resp.statusCode}', uri: uri);
    }
    return resp.transform(_utf8Lenient).join();
  }

  /// Une MASTER playlist contient des `#EXT-X-STREAM-INF` (déclaration
  /// de variantes par qualité), contrairement à une MEDIA playlist qui
  /// contient des `#EXTINF` + segments. Le bug #1 venait de l'absence
  /// totale de cette distinction.
  bool _isMasterPlaylist(String body) => body.contains('#EXT-X-STREAM-INF');

  /// Choisit la variante de PLUS HAUTE bande passante (attribut
  /// `BANDWIDTH=`) d'une master playlist et retourne l'URL absolue de
  /// sa media playlist. `null` si aucune variante exploitable.
  Uri? _selectVariant(String masterBody, Uri base) {
    final List<String> lines = masterBody.split('\n');
    int bestBw = -1;
    String? bestUri;
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final Match? m = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final int bw = m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0;
      // L'URI suit sur la 1re ligne non vide / non commentaire.
      for (int j = i + 1; j < lines.length; j++) {
        final String cand = lines[j].trim();
        if (cand.isEmpty || cand.startsWith('#')) continue;
        if (bw > bestBw) {
          bestBw = bw;
          bestUri = cand;
        }
        break;
      }
    }
    if (bestUri == null) return null;
    try {
      return base.resolve(bestUri);
    } catch (_) {
      return null;
    }
  }

  /// Parse une MEDIA playlist HLS .m3u8 et retourne les URLs absolues
  /// des segments .ts. Ignore les lignes #EXT*, mais utilise
  /// l'URI courante pour résoudre les chemins relatifs.
  List<String> _parseHlsSegments(String body, Uri base) {
    final List<String> out = <String>[];
    for (final String raw in body.split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      // Ligne non-commentaire = URL du segment, relative ou absolue.
      try {
        final Uri u = base.resolve(line);
        out.add(u.toString());
      } catch (_) {
        // URL malformée → on saute
      }
    }
    return out;
  }

  /// Télécharge UN segment .ts et l'append au fichier de sortie.
  /// Toute erreur est loguée mais n'arrête pas la boucle (un
  /// segment perdu ≠ recording perdu).
  Future<void> _downloadSegment(_Job job, String segUrl) async {
    try {
      final HttpClientResponse resp =
          await _httpGet(job.client!, Uri.parse(segUrl));
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        await resp.drain<void>();
        return;
      }
      await for (final List<int> chunk in resp) {
        if (job.sink == null) return; // stop demandé
        try {
          job.sink!.add(chunk);
          job.bytesWritten += chunk.length;
          if (job.sinkErrorCount != 0) {
            job.sinkErrorCount = 0;
          }
        } catch (sinkErr) {
          // Phase 1 / F-02 : meme logique que le pipeline raw — on
          // compte les echecs disque et on coupe au seuil.
          job.sinkErrorCount++;
          StructuredLogger.instance.warn(
            domain: 'rec',
            event: 'job.disk_error',
            ctx: <String, Object?>{
              'filePath': job.filePath,
              'pipeline': 'hls',
              'consecutive': job.sinkErrorCount,
              'bytesWritten': job.bytesWritten,
              'error': sinkErr.toString(),
            },
          );
          if (job.sinkErrorCount >= _kMaxConsecutiveSinkErrors) {
            _autoFinish(job.filePath, AutoStopReason.diskError);
            return; // sort du await-for, la boucle exterieure verra _jobs vide
          }
          // Sous le seuil : on continue (le chunk est perdu mais le job vit).
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Rec] segment download error: $e');
    }
  }

  /// Arrête un job d'enregistrement précis (par filePath) ou TOUS
  /// les jobs si `filePath == null` (legacy : maintient la compat
  /// avec l'ancien code qui appelait `.stop()` sans argument).
  /// Retourne le total d'octets écrits pour le(s) job(s) arrêté(s).
  Future<int> stop({String? filePath}) async {
    if (filePath != null) {
      final _Job? job = _jobs[filePath];
      if (job == null) return 0;
      // On marque `stopping` AVANT de couper : ça empêche une boucle
      // HLS ou une reconnexion raw en cours de relancer une connexion
      // pendant qu'on ferme.
      job.stopping = true;
      final int size = job.bytesWritten;
      await _stopJob(job);
      _jobs.remove(filePath);
      if (kDebugMode) {
        debugPrint(
            '[Rec] stopped $filePath ($size bytes, ${_jobs.length} actifs restants)');
      }
      StructuredLogger.instance.info(
        domain: 'rec',
        event: 'job.stop',
        ctx: <String, Object?>{
          'filePath': filePath,
          'bytesWritten': size,
          'elapsedSeconds': job.elapsed.inSeconds,
          'reconnectCount': job.reconnectCount,
          'activeCount': _jobs.length,
        },
      );
      return size;
    }
    // Mode "stop all" → arrête tous les jobs et retourne le total.
    int total = 0;
    final List<_Job> all = _jobs.values.toList();
    for (final _Job job in all) {
      job.stopping = true;
      total += job.bytesWritten;
      await _stopJob(job);
    }
    _jobs.clear();
    if (kDebugMode) debugPrint('[Rec] stopped ALL ($total bytes total)');
    return total;
  }

  /// Programme l'arrêt automatique du job à 6 h. Si l'utilisateur fait
  /// stop() avant, le timer est annulé dans _stopJob.
  void _armMaxDurationTimer(_Job job) {
    job.maxTimer = Timer(kMaxRecordingDuration, () {
      if (kDebugMode) {
        debugPrint('[Rec] timer 6 h déclenché → arrêt ${job.filePath}');
      }
      _autoFinish(job.filePath, AutoStopReason.maxDurationReached);
    });
  }

  /// Arrêt PROVOQUÉ PAR LE JOB lui-même (plafond 6 h atteint,
  /// serveur définitivement injoignable, OU erreur disque consecutive
  /// — Phase 1 / F-02), par opposition à stop() déclenché par
  /// l'utilisateur. On ferme proprement puis on notifie l'UI via le
  /// callback [onAutoStopped] pour qu'elle finalise la fiche en base
  /// et retire le badge "REC". Le motif [reason] est propage au
  /// callback (Phase 1 / F-03) pour que l'UI choisisse le message
  /// adapte.
  void _autoFinish(String filePath, AutoStopReason reason) {
    final _Job? job = _jobs.remove(filePath);
    if (job == null) return;
    job.stopping = true;
    final void Function(String, AutoStopReason)? cb = job.onAutoStopped;
    StructuredLogger.instance.info(
      domain: 'rec',
      event: 'job.auto_stop',
      ctx: <String, Object?>{
        'filePath': filePath,
        'reason': reason.name,
        'bytesWritten': job.bytesWritten,
        'elapsedSeconds': job.elapsed.inSeconds,
        'reconnectCount': job.reconnectCount,
        'activeCount': _jobs.length,
      },
    );
    // _stopJob est async mais on n'a pas besoin de l'attendre ici —
    // le flush/close se fait en arrière-plan, et le callback peut
    // partir tout de suite (l'UI lira la taille du fichier ensuite).
    _stopJob(job);
    if (cb != null) {
      // On déclenche le callback hors de la pile d'appels courante
      // pour éviter tout effet de bord de réentrance.
      scheduleMicrotask(() => cb(filePath, reason));
    }
  }

  /// Cleanup d'un job sans le retirer de la map (utilisé par onDone /
  /// onError quand le stream se termine de lui-même côté serveur).
  void _cleanupJob(String filePath) {
    final _Job? job = _jobs.remove(filePath);
    if (job == null) return;
    _stopJob(job);
  }

  Future<void> _stopJob(_Job job) async {
    try {
      job.maxTimer?.cancel();
    } catch (_) {}
    job.maxTimer = null;
    try {
      await job.sub?.cancel();
    } catch (_) {}
    job.sub = null;
    try {
      await job.sink?.flush();
      await job.sink?.close();
    } catch (_) {}
    job.sink = null;
    try {
      job.client?.close(force: true);
    } catch (_) {}
    job.client = null;
  }
}

/// État interne d'un seul recording en cours.
/// Mutable car les champs sont assignés au fil du start().
class _Job {
  _Job({required this.filePath, required this.streamUrl});
  final String filePath;

  /// URL upstream du flux, conservee pour les logs structures et
  /// pour qu'une future logique de "resume apres kill OS" puisse la
  /// retrouver (Phase 1+ — F-04 prepare le terrain, le resume n'est
  /// PAS implemente ici).
  final String streamUrl;

  HttpClient? client;
  StreamSubscription<List<int>>? sub;
  IOSink? sink;

  /// Horodatage de démarrage — sert à calculer la durée écoulée et à
  /// déclencher l'arrêt automatique à 6 h.
  final DateTime startedAt = DateTime.now();

  /// Durée écoulée depuis le démarrage de l'enregistrement.
  Duration get elapsed => DateTime.now().difference(startedAt);

  /// Passe à `true` dès qu'un stop() explicite (ou un auto-stop) est
  /// demandé. Tant que c'est `false`, les coupures serveur déclenchent
  /// une reconnexion ; à `true`, on laisse tout se fermer.
  bool stopping = false;

  /// Timer d'arrêt automatique à kMaxRecordingDuration (6 h).
  Timer? maxTimer;

  /// Callback optionnel appelé quand le job s'arrête DE LUI-MÊME
  /// (6 h, serveur mort, ou erreur disque), pas sur stop() utilisateur.
  /// Le second argument indique la raison precise pour que l'UI
  /// adapte le message (Phase 1 / F-03).
  void Function(String filePath, AutoStopReason reason)? onAutoStopped;

  /// Nombre de reconnexions réussies (diagnostic / logs).
  int reconnectCount = 0;

  /// Échecs de reconnexion CONSÉCUTIFS. Remis à 0 dès qu'une
  /// reconnexion aboutit. Déclenche l'abandon au-delà de
  /// _kMaxReconnectFailures.
  int reconnectFailures = 0;

  /// Phase 1 / F-02 : echecs de sink.add CONSECUTIFS. Remis a 0 a
  /// chaque ecriture reussie. Au-dela de [_kMaxConsecutiveSinkErrors]
  /// le job est coupe avec [AutoStopReason.diskError].
  int sinkErrorCount = 0;

  /// URLs des segments .ts HLS déjà téléchargés — déduplique entre
  /// 2 polls de la playlist (la fenêtre live garde 3-6 segments
  /// dont la plupart sont déjà téléchargés au cycle précédent).
  /// Utilisé uniquement par _runHlsLoop ; les jobs raw l'ignorent.
  final Set<String> seenSegments = <String>{};
  int bytesWritten = 0;
}
