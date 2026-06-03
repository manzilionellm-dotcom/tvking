// =========================================================
//  download_repository.dart — Téléchargement de films hors-ligne
// =========================================================
//  Télécharge un film VOD (fichier fini) vers le stockage local pour
//  le regarder SANS connexion (façon Netflix). Gère :
//    - la progression (octets reçus / taille totale),
//    - la REPRISE après coupure (HTTP Range : on repart où on s'est
//      arrêté au lieu de tout retélécharger),
//    - les états (en cours / en pause / terminé / erreur),
//    - la persistance SQLite (la liste survit au redémarrage de l'app),
//    - la lecture hors-ligne (le lecteur ouvre le fichier local).
//
//  Différence clé avec l'enregistrement live : ici le flux a une FIN
//  (EOF = film terminé). On s'arrête à l'EOF au lieu de reconnecter.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../playlists/data/playlist_database.dart';
import '../domain/vod_movie.dart';

/// État d'un téléchargement.
enum DownloadStatus { downloading, paused, done, error }

@immutable
class Download {
  const Download({
    required this.id,
    required this.name,
    required this.sourceUrl,
    required this.filePath,
    required this.status,
    required this.receivedBytes,
    required this.totalBytes,
    required this.createdAt,
    this.posterUrl,
  });

  final String id; // = VodMovie.id
  final String name;
  final String sourceUrl;
  final String filePath;
  final DownloadStatus status;
  final int receivedBytes;
  final int totalBytes; // 0 si inconnu
  final int createdAt;
  final String? posterUrl;

  double get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
  bool get isDone => status == DownloadStatus.done;

  Download copyWith({
    DownloadStatus? status,
    int? receivedBytes,
    int? totalBytes,
  }) {
    return Download(
      id: id,
      name: name,
      sourceUrl: sourceUrl,
      filePath: filePath,
      status: status ?? this.status,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      createdAt: createdAt,
      posterUrl: posterUrl,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'source_url': sourceUrl,
        'file_path': filePath,
        'status': status.name,
        'received_bytes': receivedBytes,
        'total_bytes': totalBytes,
        'created_at': createdAt,
        'poster_url': posterUrl,
      };

  factory Download.fromMap(Map<String, Object?> m) => Download(
        id: m['id'] as String,
        name: m['name'] as String,
        sourceUrl: m['source_url'] as String,
        filePath: m['file_path'] as String,
        status: DownloadStatus.values.firstWhere(
          (DownloadStatus s) => s.name == (m['status'] as String?),
          orElse: () => DownloadStatus.error,
        ),
        receivedBytes: (m['received_bytes'] as num?)?.toInt() ?? 0,
        totalBytes: (m['total_bytes'] as num?)?.toInt() ?? 0,
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
        posterUrl: m['poster_url'] as String?,
      );
}

class DownloadsRepository {
  DownloadsRepository._();
  static final DownloadsRepository instance = DownloadsRepository._();

  bool _initialized = false;
  final StreamController<List<Download>> _controller =
      StreamController<List<Download>>.broadcast();
  List<Download> _cache = const <Download>[];

  /// Jobs actifs (clé = download id). Permet pause/annulation.
  final Map<String, _Job> _jobs = <String, _Job>{};

  Stream<List<Download>> get stream => _controller.stream;
  List<Download> get current => _cache;

  Future<void> initialize() async {
    if (_initialized) return;
    final Database db = await PlaylistDatabase.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS downloads (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        source_url TEXT NOT NULL,
        file_path TEXT NOT NULL,
        status TEXT NOT NULL,
        received_bytes INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        poster_url TEXT
      )
    ''');
    _initialized = true;
    // Les téléchargements "downloading" laissés par un kill précédent
    // sont remis en "paused" (l'utilisateur pourra reprendre).
    await db.update(
      'downloads',
      <String, Object?>{'status': DownloadStatus.paused.name},
      where: 'status = ?',
      whereArgs: <Object>[DownloadStatus.downloading.name],
    );
    await _refresh();
  }

  Future<Directory> _downloadsDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(base.path, 'Telechargements'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  bool isDownloaded(String id) =>
      _cache.any((Download d) => d.id == id && d.status == DownloadStatus.done);
  Download? byId(String id) {
    for (final Download d in _cache) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Démarre (ou reprend) le téléchargement d'un film.
  Future<void> start(VodMovie movie) async {
    await initialize();
    if (_jobs.containsKey(movie.id)) return; // déjà en cours

    String safe(String s) => s.replaceAll(RegExp(r'[^\w\d\-_. ]+'), '_');
    final Directory dir = await _downloadsDir();
    final Download existing = byId(movie.id) ??
        Download(
          id: movie.id,
          name: movie.name,
          sourceUrl: movie.streamUrl,
          filePath: p.join(dir.path, '${safe(movie.name)}-${movie.id}.${movie.containerExt}'),
          status: DownloadStatus.downloading,
          receivedBytes: 0,
          totalBytes: 0,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          posterUrl: movie.posterUrl,
        );
    await _upsert(existing.copyWith(status: DownloadStatus.downloading));
    _runJob(existing);
  }

  Future<void> pause(String id) async {
    final _Job? job = _jobs[id];
    if (job != null) {
      job.cancelled = true;
      await job.sub?.cancel();
      try { await job.sink?.flush(); await job.sink?.close(); } catch (_) {}
      job.client?.close(force: true);
      _jobs.remove(id);
    }
    final Download? d = byId(id);
    if (d != null && d.status != DownloadStatus.done) {
      await _upsert(d.copyWith(status: DownloadStatus.paused));
    }
  }

  Future<void> resume(String id) async {
    final Download? d = byId(id);
    if (d == null || d.status == DownloadStatus.done) return;
    if (_jobs.containsKey(id)) return;
    await _upsert(d.copyWith(status: DownloadStatus.downloading));
    _runJob(d);
  }

  Future<void> delete(String id) async {
    await pause(id);
    final Download? d = byId(id);
    if (d != null) {
      try {
        final File f = File(d.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('downloads', where: 'id = ?', whereArgs: <Object>[id]);
    await _refresh();
  }

  // ----- Moteur de téléchargement -----

  void _runJob(Download d) {
    final _Job job = _Job();
    _jobs[d.id] = job;
    unawaited(_download(d, job));
  }

  Future<void> _download(Download d, _Job job) async {
    try {
      final File file = File(d.filePath);
      await file.parent.create(recursive: true);
      // Reprise : on repart de la taille déjà téléchargée.
      int start = 0;
      if (await file.exists()) {
        start = await file.length();
      }

      job.client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..autoUncompress = false
        ..userAgent = 'VLC/3.0.18 LibVLC/3.0.18';

      final HttpClientRequest req =
          await job.client!.getUrl(Uri.parse(d.sourceUrl));
      req.followRedirects = true;
      req.maxRedirects = 8;
      if (start > 0) {
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
      }
      final HttpClientResponse resp = await req.close();

      // 200 = depuis le début, 206 = reprise partielle acceptée.
      final bool partial = resp.statusCode == 206;
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw HttpException('HTTP ${resp.statusCode}');
      }
      // Si le serveur ignore le Range (200 alors qu'on demandait une
      // reprise), on repart de zéro proprement.
      if (start > 0 && !partial) {
        start = 0;
        try { await file.delete(); } catch (_) {}
      }

      // Taille totale = (déjà reçu) + contentLength.
      final int contentLen = resp.contentLength;
      int total = d.totalBytes;
      if (contentLen > 0) total = start + contentLen;

      job.sink = file.openWrite(mode: FileMode.append);
      int received = start;
      await _upsert(d.copyWith(
        status: DownloadStatus.downloading,
        receivedBytes: received,
        totalBytes: total,
      ));

      final Completer<void> done = Completer<void>();
      DateTime lastUi = DateTime.now();
      job.sub = resp.listen(
        (List<int> chunk) {
          if (job.cancelled) return;
          job.sink?.add(chunk);
          received += chunk.length;
          // On ne rafraîchit l'UI/DB qu'environ toutes les 700 ms pour
          // ne pas saturer (un film = des dizaines de milliers de chunks).
          final DateTime now = DateTime.now();
          if (now.difference(lastUi).inMilliseconds > 700) {
            lastUi = now;
            unawaited(_upsert(d.copyWith(
              status: DownloadStatus.downloading,
              receivedBytes: received,
              totalBytes: total,
            )));
          }
        },
        onError: (Object e, StackTrace s) {
          if (!done.isCompleted) done.completeError(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );

      await done.future;
      try { await job.sink?.flush(); await job.sink?.close(); } catch (_) {}
      job.client?.close(force: true);
      _jobs.remove(d.id);

      if (job.cancelled) return; // mis en pause par l'utilisateur

      // Terminé : on marque "done".
      final int finalSize =
          await file.exists() ? await file.length() : received;
      await _upsert(d.copyWith(
        status: DownloadStatus.done,
        receivedBytes: finalSize,
        totalBytes: total > 0 ? total : finalSize,
      ));
    } catch (e) {
      if (kDebugMode) debugPrint('[Downloads] ${d.id} erreur: $e');
      try { await job.sink?.flush(); await job.sink?.close(); } catch (_) {}
      job.client?.close(force: true);
      _jobs.remove(d.id);
      final Download? cur = byId(d.id);
      if (cur != null && !job.cancelled) {
        await _upsert(cur.copyWith(status: DownloadStatus.error));
      }
    }
  }

  // ----- Persistance -----

  Future<void> _upsert(Download d) async {
    final Database db = await PlaylistDatabase.instance.database;
    await db.insert(
      'downloads',
      d.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _refresh();
  }

  Future<void> _refresh() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.query('downloads', orderBy: 'created_at DESC');
    _cache = rows.map(Download.fromMap).toList();
    _controller.add(_cache);
  }
}

/// État interne d'un job de téléchargement actif.
class _Job {
  HttpClient? client;
  StreamSubscription<List<int>>? sub;
  IOSink? sink;
  bool cancelled = false;
}
