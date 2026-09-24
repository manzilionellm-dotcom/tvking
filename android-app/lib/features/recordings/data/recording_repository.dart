// =========================================================
//  recording_repository.dart — Gestion des enregistrements
// =========================================================
//  Crée des fichiers .ts dans le stockage externe accessible
//  de l'app (`/storage/emulated/0/Android/data/.../files/Recordings`)
//  et persiste leur métadonnées en SQLite.
//
//  Le contenu vidéo lui-même est écrit par le downloader HTTP Dart
//  pur (cf. http_recording_downloader.dart). Ce repo se contente de
//  gérer les chemins, les métadonnées et la liste — y compris la
//  recuperation d'orphelins au boot (Phase 1 / F-01).
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/observability/structured_logger.dart';
import '../../playlists/data/playlist_database.dart';
import '../domain/recording.dart';
import 'http_recording_downloader.dart';

class RecordingRepository {
  RecordingRepository._();
  static final RecordingRepository instance = RecordingRepository._();

  bool _initialized = false;
  final StreamController<List<Recording>> _controller =
      StreamController<List<Recording>>.broadcast();
  List<Recording> _cache = const <Recording>[];

  Stream<List<Recording>> get stream => _controller.stream;
  List<Recording> get current => _cache;

  Future<void> initialize() async {
    if (_initialized) return;
    final Database db = await PlaylistDatabase.instance.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        channel_name TEXT NOT NULL,
        program_title TEXT,
        file_path TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        file_size_bytes INTEGER NOT NULL DEFAULT 0,
        channel_logo_url TEXT
      )
    ''');

    // Migration : la colonne `channel_logo_url` a été ajoutée plus tard.
    // Pour les bases existantes, on ALTER TABLE. Idempotent : si la colonne
    // existe déjà, SQLite throw une DatabaseException qu'on ignore.
    try {
      await db.execute(
        'ALTER TABLE recordings ADD COLUMN channel_logo_url TEXT',
      );
    } on DatabaseException catch (_) {
      // Colonne déjà présente — bénin
    }

    // Phase 1 / F-04 : colonne `stream_url` pour persister l'URL
    // upstream. Idempotente comme la precedente.
    try {
      await db.execute(
        'ALTER TABLE recordings ADD COLUMN stream_url TEXT',
      );
    } on DatabaseException catch (_) {
      // deja presente
    }

    // Phase 1 / F-03 : colonne `auto_stop_reason` pour distinguer
    // les causes d'arret automatique (et `interruptedByOsKill` pour
    // les orphelins recuperes par recoverOrphans — F-01).
    try {
      await db.execute(
        'ALTER TABLE recordings ADD COLUMN auto_stop_reason TEXT',
      );
    } on DatabaseException catch (_) {
      // deja presente
    }

    _initialized = true;
    await _refresh();
  }

  /// Dossier où stocker les .ts. Sur Android → externe (visible
  /// dans le file manager sous Android/data/...). Sur iOS →
  /// app documents.
  Future<Directory> getRecordingsDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(base.path, 'Recordings'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Crée un chemin de fichier suggéré pour un nouvel
  /// enregistrement.
  Future<String> createFilePath({
    required String channelName,
    String? programTitle,
  }) async {
    final Directory dir = await getRecordingsDir();
    final DateTime now = DateTime.now();
    String safe(String s) => s.replaceAll(RegExp(r'[^\w\d\-_. ]+'), '_');
    final String stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final String slug = programTitle == null || programTitle.isEmpty
        ? safe(channelName)
        : '${safe(channelName)}-${safe(programTitle)}';
    return p.join(dir.path, '$slug-$stamp.ts');
  }

  // ----- CRUD -----

  Future<Recording> startRecording({
    required String channelId,
    required String channelName,
    String? programTitle,
    required String filePath,
    String? channelLogoUrl,
    String? streamUrl,
  }) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final Recording rec = Recording(
      id: null,
      channelId: channelId,
      channelName: channelName,
      programTitle: programTitle,
      filePath: filePath,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      channelLogoUrl: channelLogoUrl,
      streamUrl: streamUrl,
    );
    final int id = await db.insert('recordings', rec.toMap());
    await _refresh();
    return rec.copyWith(id: id);
  }

  Future<void> finishRecording(Recording rec) async {
    await initialize();
    if (rec.id == null) return;
    final Database db = await PlaylistDatabase.instance.database;
    int size = 0;
    try {
      final File f = File(rec.filePath);
      if (await f.exists()) {
        size = await f.length();
      }
    } catch (_) {}
    await db.update(
      'recordings',
      <String, Object?>{
        'ended_at': DateTime.now().millisecondsSinceEpoch,
        'file_size_bytes': size,
      },
      where: 'id = ?',
      whereArgs: <Object>[rec.id!],
    );
    await _refresh();
  }

  /// Finalise un enregistrement par son CHEMIN de fichier, sans avoir
  /// besoin de l'objet Recording. Utilisé par l'auto-stop du
  /// downloader (plafond 6 h, serveur mort, disque plein) : à ce
  /// moment-là on ne connaît que le filePath, et la fiche peut ne
  /// plus être en mémoire côté UI. On ne touche qu'aux fiches encore
  /// "en cours" (ended_at IS NULL) pour ce chemin.
  ///
  /// [reason] (Phase 1 / F-03) est le motif d'arret persiste — null
  /// si l'arret vient d'un stop() utilisateur. Sert a l'UI pour
  /// afficher un message adapte et au diagnostic pour reperer les
  /// recordings interrompus.
  Future<void> finishRecordingByPath(
    String filePath, {
    String? reason,
  }) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    int size = 0;
    try {
      final File f = File(filePath);
      if (await f.exists()) {
        size = await f.length();
      }
    } catch (_) {}
    await db.update(
      'recordings',
      <String, Object?>{
        'ended_at': DateTime.now().millisecondsSinceEpoch,
        'file_size_bytes': size,
        if (reason != null) 'auto_stop_reason': reason,
      },
      where: 'file_path = ? AND ended_at IS NULL',
      whereArgs: <Object>[filePath],
    );
    await _refresh();
  }

  /// Phase 1 / F-01 : detecte et finalise les recordings "fantomes"
  /// laisses en `ended_at IS NULL` parce que le process a ete tue par
  /// l'OS pendant l'enregistrement (RecordingForegroundService renvoie
  /// `START_NOT_STICKY`, donc ni le service ni le downloader ne
  /// reprennent).
  ///
  /// Sans cette logique, l'UI affichait indefiniment le badge "EN COURS"
  /// pour ces fiches — exactement le cas "l'UI ment a l'utilisateur"
  /// identifie comme P0 dans l'audit Phase 0.
  ///
  /// Strategie :
  ///   1. SELECT * FROM recordings WHERE ended_at IS NULL.
  ///   2. Pour chaque fiche, on saute celles dont le downloader a
  ///      ENCORE un job actif sur ce filePath (cas legitime d'un
  ///      recording en cours juste apres relancement de l'app — ne
  ///      devrait pas arriver vu que `recoverOrphans` doit etre
  ///      appele avant tout `start`, mais ceinture+bretelles).
  ///   3. Pour les vrais orphelins : finishRecordingByPath avec
  ///      reason='interruptedByOsKill'.
  ///   4. Log structure pour diagnostic.
  ///
  /// Idempotent : un 2e appel ne fait rien (les fiches sont deja
  /// finalisees).
  Future<List<Recording>> recoverOrphans() async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      'recordings',
      where: 'ended_at IS NULL',
    );
    if (rows.isEmpty) return const <Recording>[];

    final List<Recording> recovered = <Recording>[];
    final HttpRecordingDownloader dl = HttpRecordingDownloader.instance;

    for (final Map<String, Object?> row in rows) {
      final Recording r = Recording.fromMap(row);
      // Ceinture + bretelles : si un job tourne reellement pour ce
      // path (cas exotique), on ne touche PAS — c'est un vrai
      // recording en cours.
      if (dl.isRecordingFile(r.filePath)) {
        continue;
      }
      await finishRecordingByPath(
        r.filePath,
        reason: 'interruptedByOsKill',
      );
      recovered.add(r);
      StructuredLogger.instance.warn(
        domain: 'rec',
        event: 'job.recovered_orphan',
        ctx: <String, Object?>{
          'id': r.id,
          'filePath': r.filePath,
          'channel': r.channelName,
          'startedAt': r.startedAt,
        },
      );
    }

    if (recovered.isNotEmpty && kDebugMode) {
      debugPrint(
        '[Recordings] recoverOrphans : ${recovered.length} fiche(s) '
        'finalisee(s) (orphelines apres kill OS)',
      );
    }
    return recovered;
  }

  Future<void> delete(Recording rec) async {
    await initialize();
    if (rec.id == null) return;
    try {
      final File f = File(rec.filePath);
      if (await f.exists()) await f.delete();
    } catch (e) {
      if (kDebugMode) debugPrint('[Recordings] delete file failed: $e');
    }
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('recordings', where: 'id = ?', whereArgs: <Object>[rec.id!]);
    await _refresh();
  }

  Future<void> _refresh() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.query('recordings', orderBy: 'started_at DESC');
    _cache = rows.map(Recording.fromMap).toList(growable: false);
    if (!_controller.isClosed) _controller.add(_cache);
  }
}
