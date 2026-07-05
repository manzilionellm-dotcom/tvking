// =========================================================
//  vod_download_service.dart — Téléchargement de films (hors-ligne)
// =========================================================
//  « Regarder plus tard, sans connexion » (comme Netflix). MODULE
//  INDÉPENDANT : télécharge le FICHIER du film (VOD Xtream = un vrai
//  fichier mp4/mkv, déjà compressé par le fournisseur) vers le stockage
//  local, puis le film se lit HORS-LIGNE via le lecteur EXISTANT (fichier
//  local → ExoPlayer, isLive:false → mêmes commandes Netflix ±10 s).
//
//  « INTELLIGENT comme Netflix » — la vérité, sans mythe :
//   • Netflix ne « compresse » rien par magie au téléchargement : il
//     livre un fichier DÉJÀ encodé efficacement à la qualité choisie. Un
//     film VOD IPTV est PAREIL — un fichier fini, bien plus léger que le
//     flux live (pas de sur-débit). On le tire donc DIRECTEMENT.
//   • Ce qui rend Netflix « fluide et rapide » : téléchargement EN TÂCHE
//     DE FOND à pleine vitesse + REPRISE après coupure. On fait les deux :
//     requêtes HTTP Range → on reprend EXACTEMENT où on s'est arrêté (zéro
//     octet re-téléchargé), reconnexion auto avec back-off, progression en
//     temps réel. Rien à ré-encoder sur la box (ce qui tuerait la qualité
//     ET la batterie) : on copie l'octet, point.
//
//  STOCKAGE : fichier dans <external>/Downloads ; métadonnées en JSON
//  (SharedPreferences). Reprise possible entre deux ouvertures de l'app.
//  Best-effort : ne jette jamais, n'impacte ni le lecteur ni le direct.
// =========================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vod_movie.dart';

enum VodDownloadStatus { queued, downloading, paused, done, error }

/// Un film en cours / terminé de téléchargement.
class VodDownload {
  VodDownload({
    required this.id,
    required this.name,
    required this.filePath,
    required this.streamUrl,
    this.posterUrl,
    this.category = '',
    this.year,
    this.rating,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = VodDownloadStatus.queued,
  });

  final String id;
  final String name;
  final String filePath;
  final String streamUrl;
  final String? posterUrl;
  final String category;
  final String? year;
  final String? rating;
  int totalBytes;
  int downloadedBytes;
  VodDownloadStatus status;

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
  bool get isComplete => status == VodDownloadStatus.done;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'filePath': filePath,
        'streamUrl': streamUrl,
        'posterUrl': posterUrl,
        'category': category,
        'year': year,
        'rating': rating,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        // Un téléchargement interrompu reprend en 'paused' (jamais 'downloading'
        // au rechargement de l'app).
        'status': (status == VodDownloadStatus.downloading
                ? VodDownloadStatus.paused
                : status)
            .name,
      };

  factory VodDownload.fromJson(Map<String, dynamic> j) => VodDownload(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        filePath: j['filePath'] as String,
        streamUrl: (j['streamUrl'] as String?) ?? '',
        posterUrl: j['posterUrl'] as String?,
        category: (j['category'] as String?) ?? '',
        year: j['year'] as String?,
        rating: j['rating'] as String?,
        totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
        downloadedBytes: (j['downloadedBytes'] as num?)?.toInt() ?? 0,
        status: VodDownloadStatus.values.firstWhere(
          (VodDownloadStatus s) => s.name == j['status'],
          orElse: () => VodDownloadStatus.paused,
        ),
      );
}

class VodDownloadService extends ChangeNotifier {
  VodDownloadService._();
  static final VodDownloadService instance = VodDownloadService._();

  static const String _kKey = 'vod_downloads.v1';

  final Map<String, VodDownload> _items = <String, VodDownload>{};
  final Map<String, HttpClient> _clients = <String, HttpClient>{};
  bool _loaded = false;

  /// Liste (téléchargements récents d'abord suffit ; ordre d'insertion ici).
  List<VodDownload> get all => _items.values.toList(growable: false);
  VodDownload? byId(String id) => _items[id];
  bool isDownloaded(String id) => _items[id]?.isComplete ?? false;

  /// Fichier local prêt à lire (null si pas terminé).
  String? localFile(String id) {
    final VodDownload? d = _items[id];
    if (d == null || !d.isComplete) return null;
    return d.filePath;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String raw = prefs.getString(_kKey) ?? '[]';
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      _items.clear();
      for (final dynamic e in list) {
        if (e is Map<String, dynamic>) {
          final VodDownload d = VodDownload.fromJson(e);
          _items[d.id] = d;
        }
      }
    } catch (e) {
      debugPrint('[VodDl] load: $e');
    }
    notifyListeners();
  }

  Future<Directory> _dir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(base.path, 'Downloads'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kKey,
          jsonEncode(
              _items.values.map((VodDownload d) => d.toJson()).toList()));
    } catch (e) {
      debugPrint('[VodDl] persist: $e');
    }
  }

  /// Lance (ou reprend) le téléchargement d'un film. Idempotent : si déjà
  /// terminé, ne refait rien ; si en cours, ne relance pas un 2e job.
  Future<void> downloadMovie(VodMovie m) async {
    await load();
    final VodDownload? existing = _items[m.id];
    if (existing != null && existing.isComplete) return;
    if (existing != null && existing.status == VodDownloadStatus.downloading) {
      return;
    }
    if (existing == null) {
      final Directory dir = await _dir();
      final String ext = m.containerExt.isNotEmpty ? m.containerExt : 'mp4';
      final String safe =
          m.name.replaceAll(RegExp(r'[^\w\d\-_. ]+'), '_');
      final String path = p.join(dir.path, '${m.id}_$safe.$ext');
      _items[m.id] = VodDownload(
        id: m.id,
        name: m.name,
        filePath: path,
        streamUrl: m.streamUrl,
        posterUrl: m.posterUrl,
        category: m.category,
        year: m.year,
        rating: m.rating,
      );
    }
    await _run(m.id);
  }

  /// Met en pause (coupe la connexion, garde l'octet déjà écrit → reprise).
  Future<void> pause(String id) async {
    final VodDownload? d = _items[id];
    if (d == null) return;
    _clients.remove(id)?.close(force: true);
    if (d.status == VodDownloadStatus.downloading) {
      d.status = VodDownloadStatus.paused;
      notifyListeners();
      await _persist();
    }
  }

  Future<void> resume(String id) => _run(id);

  /// Supprime le téléchargement ET le fichier local (libère la place).
  Future<void> remove(String id) async {
    _clients.remove(id)?.close(force: true);
    final VodDownload? d = _items.remove(id);
    if (d != null) {
      try {
        final File f = File(d.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    notifyListeners();
    await _persist();
  }

  /// Cœur : GET avec REPRISE (HTTP Range) → écrit en append. Reconnexion
  /// auto avec back-off. La progression est notifiée de façon throttlée.
  Future<void> _run(String id) async {
    final VodDownload? d = _items[id];
    if (d == null || d.isComplete) return;
    if (_clients.containsKey(id)) return; // déjà en cours

    d.status = VodDownloadStatus.downloading;
    notifyListeners();

    final File file = File(d.filePath);
    int already = 0;
    try {
      if (await file.exists()) {
        already = await file.length();
      } else {
        await file.create(recursive: true);
      }
    } catch (_) {
      already = 0;
    }
    d.downloadedBytes = already;

    int attempt = 0;
    const int maxAttempts = 6;
    while (d.status == VodDownloadStatus.downloading && attempt < maxAttempts) {
      final HttpClient client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      _clients[id] = client;
      try {
        final HttpClientRequest req = await client.getUrl(Uri.parse(d.streamUrl));
        req.headers.set(HttpHeaders.userAgentHeader, 'VLC/3.0.20 LibVLC/3.0.20');
        // REPRISE : on demande la suite à partir de l'octet déjà écrit.
        if (already > 0) {
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=$already-');
        }
        final HttpClientResponse resp = await req.close();

        // Le serveur ignore la reprise (200 au lieu de 206) → on repart de 0.
        if (already > 0 && resp.statusCode == HttpStatus.ok) {
          already = 0;
          d.downloadedBytes = 0;
          final IOSink truncate = file.openWrite(mode: FileMode.write);
          await truncate.flush();
          await truncate.close();
        }
        if (resp.statusCode != HttpStatus.ok &&
            resp.statusCode != HttpStatus.partialContent) {
          throw HttpException('HTTP ${resp.statusCode}');
        }

        // Taille totale = octets déjà là + ce qui reste à recevoir.
        final int? cl = resp.contentLength > 0 ? resp.contentLength : null;
        if (cl != null) d.totalBytes = already + cl;

        final IOSink sink = file.openWrite(mode: FileMode.append);
        int sinceNotify = 0;
        await for (final List<int> chunk in resp) {
          if (d.status != VodDownloadStatus.downloading) break;
          sink.add(chunk);
          d.downloadedBytes += chunk.length;
          sinceNotify += chunk.length;
          // Throttle : on ne rafraîchit l'UI que ~tous les 512 Ko.
          if (sinceNotify >= 512 * 1024) {
            sinceNotify = 0;
            notifyListeners();
          }
        }
        await sink.flush();
        await sink.close();

        if (d.status != VodDownloadStatus.downloading) break; // pausé/annulé

        // Terminé si on a atteint la taille annoncée (ou pas de taille connue
        // mais le flux s'est terminé proprement).
        if (d.totalBytes == 0 || d.downloadedBytes >= d.totalBytes) {
          d.totalBytes = d.downloadedBytes;
          d.status = VodDownloadStatus.done;
          _clients.remove(id)?.close();
          notifyListeners();
          await _persist();
          return;
        }
        // Sinon (coupure au milieu) → on reprendra à la boucle suivante.
        already = d.downloadedBytes;
        attempt++;
      } catch (e) {
        debugPrint('[VodDl] $id attempt $attempt: $e');
        already = d.downloadedBytes;
        attempt++;
        _clients.remove(id)?.close(force: true);
        if (d.status != VodDownloadStatus.downloading) break;
        // Back-off 2,4,6…16 s avant de reprendre (Range → zéro re-téléchargé).
        await Future<void>.delayed(
            Duration(seconds: (attempt * 2).clamp(2, 16)));
        continue;
      }
    }

    _clients.remove(id)?.close(force: true);
    if (d.status == VodDownloadStatus.downloading) {
      // Sorti de la boucle sans finir → erreur (max essais atteint).
      d.status =
          d.downloadedBytes > 0 ? VodDownloadStatus.paused : VodDownloadStatus.error;
      notifyListeners();
      await _persist();
    }
  }

  /// « 1,2 Go » / « 640 Mo » — taille lisible.
  static String fmtBytes(int b) {
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
    }
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).round()} Mo';
    if (b >= 1024) return '${(b / 1024).round()} Ko';
    return '$b o';
  }
}
