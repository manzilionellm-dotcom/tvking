// =========================================================
//  scheduled_recording_repository.dart — Table `scheduled_recordings`
// =========================================================
//  Persistance SQLite des programmations (même base que les playlists et
//  les enregistrements). Expose un flux pour que les écrans « Prévus »
//  se rafraîchissent seuls. La LOGIQUE (quand démarrer, quoi faire) vit
//  dans recording_scheduler.dart — ici, uniquement du stockage.
// =========================================================

import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../playlists/data/playlist_database.dart';
import '../domain/scheduled_recording.dart';

class ScheduledRecordingRepository {
  ScheduledRecordingRepository._();
  static final ScheduledRecordingRepository instance =
      ScheduledRecordingRepository._();

  bool _initialized = false;
  final StreamController<List<ScheduledRecording>> _controller =
      StreamController<List<ScheduledRecording>>.broadcast();
  List<ScheduledRecording> _cache = const <ScheduledRecording>[];

  Stream<List<ScheduledRecording>> get stream => _controller.stream;

  /// Toutes les programmations, triées par début croissant.
  List<ScheduledRecording> get current => _cache;

  /// Celles qui comptent encore (prévues ou en cours).
  List<ScheduledRecording> get active => _cache
      .where((ScheduledRecording s) => s.isActive)
      .toList(growable: false);

  Future<void> initialize() async {
    if (_initialized) return;
    final Database db = await PlaylistDatabase.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_recordings (
        id TEXT PRIMARY KEY,
        channel_id TEXT NOT NULL,
        channel_name TEXT NOT NULL,
        channel_logo_url TEXT,
        stream_url TEXT NOT NULL,
        program_title TEXT,
        start_ms INTEGER NOT NULL,
        stop_ms INTEGER NOT NULL,
        margin_before_ms INTEGER NOT NULL DEFAULT 120000,
        margin_after_ms INTEGER NOT NULL DEFAULT 300000,
        file_path TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        recording_id INTEGER,
        bytes INTEGER NOT NULL DEFAULT 0,
        error TEXT
      )
    ''');
    _initialized = true;
    await _refresh();
  }

  ScheduledRecording? byId(String id) {
    for (final ScheduledRecording s in _cache) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Programmation ACTIVE pour (chaîne, début) — sert aux icônes du guide.
  ScheduledRecording? activeFor(String channelId, int startMs) {
    final String id = ScheduledRecording.idFor(channelId, startMs);
    final ScheduledRecording? s = byId(id);
    return (s != null && s.isActive) ? s : null;
  }

  Future<void> upsert(ScheduledRecording s) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    await db.insert(
      'scheduled_recordings',
      s.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _refresh();
  }

  Future<void> delete(String id) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('scheduled_recordings',
        where: 'id = ?', whereArgs: <Object>[id]);
    await _refresh();
  }

  /// Hygiène : retire les entrées terminées/manquées/annulées de plus de
  /// [keep] (l'historique récent reste visible dans « Prévus »).
  Future<void> pruneOlderThan(Duration keep) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int cutoff =
        DateTime.now().subtract(keep).millisecondsSinceEpoch;
    await db.delete(
      'scheduled_recordings',
      where: "status IN ('done','missed','failed','cancelled') AND stop_ms < ?",
      whereArgs: <Object>[cutoff],
    );
    await _refresh();
  }

  Future<void> _refresh() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.query('scheduled_recordings', orderBy: 'start_ms ASC');
    _cache = rows.map(ScheduledRecording.fromMap).toList(growable: false);
    if (!_controller.isClosed) _controller.add(_cache);
  }
}
