// =========================================================
//  recording_repository.dart — Gestion des enregistrements
// =========================================================
//  Crée des fichiers .ts dans le stockage externe accessible
//  de l'app (`/storage/emulated/0/Android/data/.../files/Recordings`)
//  et persiste leur métadonnées en SQLite.
//
//  Le contenu vidéo lui-même est écrit par libmpv via la
//  propriété native `stream-record`. Ce repo se contente de
//  gérer les chemins, les métadonnées et la liste.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../playlists/data/playlist_database.dart';
import '../domain/recording.dart';

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
  /// downloader (plafond 6 h ou serveur mort) : à ce moment-là on ne
  /// connaît que le filePath, et la fiche peut ne plus être en
  /// mémoire côté UI. On ne touche qu'aux fiches encore "en cours"
  /// (ended_at IS NULL) pour ce chemin.
  Future<void> finishRecordingByPath(String filePath) async {
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
      },
      where: 'file_path = ? AND ended_at IS NULL',
      whereArgs: <Object>[filePath],
    );
    await _refresh();
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
