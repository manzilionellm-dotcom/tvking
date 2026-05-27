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
// =========================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
  Future<bool> start({
    required String streamUrl,
    required String filePath,
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
      return _startHls(streamUrl: streamUrl, filePath: filePath);
    }
    return _startRaw(streamUrl: streamUrl, filePath: filePath);
  }

  /// Pipeline classique : 1 GET HTTP qui dure tant que le serveur
  /// envoie des bytes (flux MPEG-TS live). On streame directement
  /// dans le fichier sans buffer mémoire.
  Future<bool> _startRaw({
    required String streamUrl,
    required String filePath,
  }) async {
    final _Job job = _Job(filePath: filePath);
    try {
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
        // User-Agent réaliste — les Xtream filtrent souvent les
        // 'Dart/...' génériques en les bloquant.
        ..userAgent = 'VLC/3.0.20 LibVLC/3.0.20';

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
        job.client?.close(force: true);
        return false;
      }

      final File file = File(filePath);
      await file.parent.create(recursive: true);
      job.sink = file.openWrite();
      _jobs[filePath] = job;

      job.sub = resp.listen(
        (List<int> chunk) {
          try {
            job.sink?.add(chunk);
            job.bytesWritten += chunk.length;
          } catch (e) {
            if (kDebugMode) debugPrint('[Rec] sink write error: $e');
          }
        },
        onError: (Object e, StackTrace s) {
          if (kDebugMode) debugPrint('[Rec] stream error ($filePath): $e');
          // Ne PAS cleanup ici sur micro-erreur réseau — un flux
          // live peut hoqueter sans devoir tuer le recording.
          // L'user verra simplement les bytes ne plus s'incrémenter.
        },
        onDone: () {
          if (kDebugMode) {
            debugPrint(
                '[Rec] stream done ($filePath), ${job.bytesWritten} bytes');
          }
          _cleanupJob(filePath);
        },
        // false = on continue d'écouter même si une erreur passe.
        // Critique pour les flux live qui hoquettent souvent.
        cancelOnError: false,
      );

      if (kDebugMode) {
        debugPrint(
            '[Rec] raw downloader started → $filePath (${_jobs.length} actifs)');
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Rec] _startRaw failed ($filePath): $e');
      _cleanupJob(filePath);
      return false;
    }
  }

  /// Pipeline HLS : on polle la playlist toutes les 5 s, on
  /// télécharge les segments .ts qu'on n'a pas encore vus, et on
  /// les concatène dans le fichier de sortie. Tourne en boucle
  /// jusqu'au stop() ou jusqu'à 3 erreurs consécutives.
  Future<bool> _startHls({
    required String streamUrl,
    required String filePath,
  }) async {
    final _Job job = _Job(filePath: filePath);
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

      // Boucle de poll/download en arrière-plan. On ne await pas —
      // start() doit rendre la main immédiatement pour que l'UI
      // affiche 'enregistrement démarré'.
      _runHlsLoop(streamUrl: streamUrl, filePath: filePath, job: job);

      if (kDebugMode) {
        debugPrint(
            '[Rec] HLS downloader started → $filePath (${_jobs.length} actifs)');
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Rec] _startHls failed ($filePath): $e');
      _cleanupJob(filePath);
      return false;
    }
  }

  /// Boucle infinie qui polle la playlist HLS et télécharge les
  /// segments. S'arrête quand le job est retiré de _jobs (par
  /// stop()) ou après 5 erreurs consécutives.
  Future<void> _runHlsLoop({
    required String streamUrl,
    required String filePath,
    required _Job job,
  }) async {
    final Uri playlistUri = Uri.parse(streamUrl);
    int consecutiveErrors = 0;

    while (_jobs.containsKey(filePath) && consecutiveErrors < 5) {
      try {
        final HttpClientResponse resp = await _httpGet(
          job.client!,
          playlistUri,
        );
        final String body = await resp.transform(_utf8Lenient).join();
        final List<String> segments = _parseHlsSegments(body, playlistUri);

        // On télécharge UNIQUEMENT les segments pas encore vus.
        // Beaucoup de duplicates sinon (la playlist live garde
        // ~3-6 segments dans une fenêtre glissante).
        int newlyDownloaded = 0;
        for (final String segUrl in segments) {
          if (!_jobs.containsKey(filePath)) break; // stop demandé
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
              '[Rec] HLS loop error ($consecutiveErrors/5) on $filePath: $e');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }

    if (kDebugMode) {
      debugPrint(
          '[Rec] HLS loop EXITED for $filePath '
          '(${job.bytesWritten} bytes, errors=$consecutiveErrors)');
    }
    _cleanupJob(filePath);
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

  /// Parse une playlist HLS .m3u8 et retourne les URLs absolues
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
        job.sink!.add(chunk);
        job.bytesWritten += chunk.length;
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
      final int size = job.bytesWritten;
      await _stopJob(job);
      _jobs.remove(filePath);
      if (kDebugMode) {
        debugPrint(
            '[Rec] stopped $filePath ($size bytes, ${_jobs.length} actifs restants)');
      }
      return size;
    }
    // Mode "stop all" → arrête tous les jobs et retourne le total.
    int total = 0;
    final List<_Job> all = _jobs.values.toList();
    for (final _Job job in all) {
      total += job.bytesWritten;
      await _stopJob(job);
    }
    _jobs.clear();
    if (kDebugMode) debugPrint('[Rec] stopped ALL ($total bytes total)');
    return total;
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
  _Job({required this.filePath});
  final String filePath;
  HttpClient? client;
  StreamSubscription<List<int>>? sub;
  IOSink? sink;

  /// URLs des segments .ts HLS déjà téléchargés — déduplique entre
  /// 2 polls de la playlist (la fenêtre live garde 3-6 segments
  /// dont la plupart sont déjà téléchargés au cycle précédent).
  /// Utilisé uniquement par _runHlsLoop ; les jobs raw l'ignorent.
  final Set<String> seenSegments = <String>{};
  int bytesWritten = 0;
}
