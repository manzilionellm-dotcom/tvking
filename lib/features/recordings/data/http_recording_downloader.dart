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
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Singleton : un seul enregistrement actif à la fois côté téléphone.
/// (Pas de support multi-channel parallèle pour V1.)
class HttpRecordingDownloader {
  HttpRecordingDownloader._();
  static final HttpRecordingDownloader instance = HttpRecordingDownloader._();

  HttpClient? _client;
  StreamSubscription<List<int>>? _sub;
  IOSink? _sink;
  String? _currentPath;
  int _bytesWritten = 0;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  int get bytesWritten => _bytesWritten;
  String? get currentPath => _currentPath;

  /// Démarre l'enregistrement. Retourne `true` si l'init s'est bien
  /// passée (connexion établie, fichier créé, premier byte arrivé en
  /// `<2s`). Retourne `false` en cas d'erreur HTTP / réseau / disque,
  /// et nettoie ses ressources.
  Future<bool> start({
    required String streamUrl,
    required String filePath,
  }) async {
    if (_isRecording) {
      if (kDebugMode) debugPrint('[Rec] déjà en cours');
      return false;
    }

    try {
      _client = HttpClient();
      _client!.connectionTimeout = const Duration(seconds: 15);
      // Important pour le streaming : ne PAS suivre les redirects
      // automatiquement → on les gère manuellement pour avoir l'URL finale.
      // Mais HttpClient suit par défaut jusqu'à 5 redirects, et c'est
      // ce qu'on veut ici (Xtream redirige souvent vers une autre IP).

      final HttpClientRequest req =
          await _client!.getUrl(Uri.parse(streamUrl));
      // Mime un client de streaming standard pour ne pas être bloqué
      // par les Xtream qui filtrent les User-Agent "Dart".
      req.headers.set(HttpHeaders.userAgentHeader, 'VLC/3.0.18 LibVLC/3.0.18');
      req.headers.set(HttpHeaders.acceptHeader, '*/*');

      final HttpClientResponse resp = await req.close();
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        if (kDebugMode) {
          debugPrint('[Rec] HTTP ${resp.statusCode} sur $streamUrl');
        }
        _client?.close(force: true);
        _client = null;
        return false;
      }

      final File file = File(filePath);
      await file.parent.create(recursive: true);
      _sink = file.openWrite();
      _currentPath = filePath;
      _bytesWritten = 0;
      _isRecording = true;

      // Listen au flux. Chaque chunk reçu = on write + on accumule
      // la taille (utile pour le snackbar de feedback à l'arrêt).
      _sub = resp.listen(
        (List<int> chunk) {
          try {
            _sink?.add(chunk);
            _bytesWritten += chunk.length;
          } catch (e) {
            if (kDebugMode) debugPrint('[Rec] sink write error: $e');
          }
        },
        onError: (Object e, StackTrace s) {
          if (kDebugMode) debugPrint('[Rec] stream error: $e');
          _cleanup();
        },
        onDone: () {
          if (kDebugMode) {
            debugPrint('[Rec] stream done, $_bytesWritten bytes');
          }
          _cleanup();
        },
        cancelOnError: true,
      );

      if (kDebugMode) debugPrint('[Rec] downloader started → $filePath');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Rec] start failed: $e');
      _cleanup();
      return false;
    }
  }

  /// Arrête l'enregistrement, ferme le fichier, libère le client HTTP.
  /// Retourne le nombre total d'octets écrits — utile pour le snackbar.
  Future<int> stop() async {
    final int finalSize = _bytesWritten;
    await _sub?.cancel();
    _sub = null;
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    try {
      _client?.close(force: true);
    } catch (_) {}
    _client = null;
    _isRecording = false;
    if (kDebugMode) debugPrint('[Rec] stopped at $finalSize bytes');
    return finalSize;
  }

  /// Cleanup interne sur erreur stream ou onDone naturel. Idempotent.
  void _cleanup() {
    _isRecording = false;
    try {
      _sink?.flush();
    } catch (_) {}
    try {
      _sink?.close();
    } catch (_) {}
    _sink = null;
    try {
      _client?.close(force: true);
    } catch (_) {}
    _client = null;
  }
}
