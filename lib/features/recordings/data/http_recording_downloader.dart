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
import 'dart:io';

import 'package:flutter/foundation.dart';

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
  ///   - la requête HTTP échoue
  ///   - l'ouverture du fichier échoue
  Future<bool> start({
    required String streamUrl,
    required String filePath,
  }) async {
    if (_jobs.containsKey(filePath)) {
      if (kDebugMode) debugPrint('[Rec] $filePath déjà en cours');
      return false;
    }

    final _Job job = _Job(filePath: filePath);
    try {
      job.client = HttpClient();
      job.client!.connectionTimeout = const Duration(seconds: 15);

      final HttpClientRequest req =
          await job.client!.getUrl(Uri.parse(streamUrl));
      // Mime un client de streaming standard pour ne pas être bloqué
      // par les Xtream qui filtrent les User-Agent "Dart".
      req.headers.set(HttpHeaders.userAgentHeader, 'VLC/3.0.18 LibVLC/3.0.18');
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
          _cleanupJob(filePath);
        },
        onDone: () {
          if (kDebugMode) {
            debugPrint(
                '[Rec] stream done ($filePath), ${job.bytesWritten} bytes');
          }
          _cleanupJob(filePath);
        },
        cancelOnError: true,
      );

      if (kDebugMode) {
        debugPrint(
            '[Rec] downloader started → $filePath (${_jobs.length} actifs)');
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Rec] start failed ($filePath): $e');
      _cleanupJob(filePath);
      return false;
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
  int bytesWritten = 0;
}
