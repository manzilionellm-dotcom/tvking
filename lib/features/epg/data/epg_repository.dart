// =========================================================
//  epg_repository.dart — Stockage et accès aux programmes EPG
// =========================================================
//  Table SQLite `epg_programs` indexée par (channel_id, start_time).
//
//  Opérations principales :
//    - downloadAndImport(url) : télécharge un XMLTV (avec support
//      gzip), parse en streaming, insère par batch dans SQLite,
//      purge les programmes périmés
//    - currentProgram(channelId) : programme qui se joue maintenant
//    - nextProgram(channelId) : programme suivant
//    - programsBetween(channelId, start, end) : pour la grille TV
//
//  Émet sur un Stream à chaque mise à jour pour que les UI
//  réactives (TV Guide, cards) se rafraîchissent.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../playlists/data/playlist_database.dart';
import '../domain/epg_program.dart';
import 'xmltv_parser.dart';

class EpgRepository {
  EpgRepository._();
  static final EpgRepository instance = EpgRepository._();

  final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  /// Émet à chaque sync EPG → les écrans rebuildent.
  Stream<void> get changes => _changesController.stream;

  bool _initialized = false;
  bool _syncing = false;

  bool get isSyncing => _syncing;

  // ============================================================
  //  Initialisation (création des tables)
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) return;
    final Database db = await PlaylistDatabase.instance.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS epg_programs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel_id TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        stop_time INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        category TEXT,
        icon_url TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_epg_channel_time
      ON epg_programs(channel_id, start_time)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_epg_start_time
      ON epg_programs(start_time)
    ''');

    _initialized = true;
  }

  // ============================================================
  //  TÉLÉCHARGEMENT + IMPORT
  // ============================================================

  /// Télécharge un fichier XMLTV depuis [url] (supporte .gz et plain)
  /// et l'insère en base. Optionnellement filtre par les IDs des
  /// chaînes actuellement connues pour économiser stockage et CPU.
  Future<int> downloadAndImport({
    required String url,
    Set<String>? knownChannelIds,
    http.Client? httpClient,
    void Function(int progressBytes)? onProgress,
  }) async {
    if (_syncing) return 0;
    _syncing = true;
    try {
      await initialize();

      final http.Client client = httpClient ?? http.Client();
      try {
        final http.Request req = http.Request('GET', Uri.parse(url));
        final http.StreamedResponse resp = await client.send(req);
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }

        // Source de bytes (gzip décompressé si nécessaire)
        Stream<List<int>> bytes = resp.stream;
        final String lower = url.toLowerCase();
        final bool isGzip = lower.endsWith('.gz') ||
            lower.endsWith('.gzip') ||
            (resp.headers['content-encoding']?.toLowerCase() == 'gzip') ||
            (resp.headers['content-type']?.toLowerCase() ?? '')
                .contains('gzip');

        if (isGzip) {
          // Décompression streaming via dart:io
          bytes = bytes.transform<List<int>>(gzip.decoder);
        }

        // Compteur progression simple
        if (onProgress != null) {
          int total = 0;
          bytes = bytes.map<List<int>>((List<int> chunk) {
            total += chunk.length;
            onProgress(total);
            return chunk;
          });
        }

        // On purge d'abord les vieux programmes pour faire de la place
        await purgeStale();

        // Batch d'insertion : on accumule 500 programmes puis on commit
        final Database db = await PlaylistDatabase.instance.database;
        Batch batch = db.batch();
        int pending = 0;
        int total = 0;

        await XmltvParser.parse(
          bytes,
          skipPredicate: knownChannelIds == null
              ? null
              : (String id) => !knownChannelIds.contains(id),
          onProgram: (EpgProgram p) async {
            batch.insert('epg_programs', p.toMap());
            pending++;
            total++;
            if (pending >= 500) {
              await batch.commit(noResult: true);
              batch = db.batch();
              pending = 0;
            }
          },
        );

        if (pending > 0) {
          await batch.commit(noResult: true);
        }

        if (kDebugMode) {
          debugPrint('[EpgRepository] $total programmes importés');
        }

        if (!_changesController.isClosed) {
          _changesController.add(null);
        }
        return total;
      } finally {
        if (httpClient == null) client.close();
      }
    } finally {
      _syncing = false;
    }
  }

  /// Supprime tous les programmes terminés depuis plus d'une heure.
  /// Garde 1h dans le passé pour le catch-up immédiat.
  Future<int> purgeStale() async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int cutoff = DateTime.now()
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    return db.delete(
      'epg_programs',
      where: 'stop_time < ?',
      whereArgs: <Object>[cutoff],
    );
  }

  /// Vide complètement la base EPG.
  Future<void> clearAll() async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('epg_programs');
    if (!_changesController.isClosed) _changesController.add(null);
  }

  // ============================================================
  //  LECTURE
  // ============================================================

  /// Programme actuellement diffusé sur cette chaîne (null si rien).
  Future<EpgProgram?> currentProgram(String channelId) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await db.query(
      'epg_programs',
      where: 'channel_id = ? AND start_time <= ? AND stop_time > ?',
      whereArgs: <Object>[channelId, now, now],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return EpgProgram.fromMap(rows.first);
  }

  /// Programme suivant après celui en cours (null si rien programmé).
  Future<EpgProgram?> nextProgram(String channelId) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await db.query(
      'epg_programs',
      where: 'channel_id = ? AND start_time > ?',
      whereArgs: <Object>[channelId, now],
      orderBy: 'start_time ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return EpgProgram.fromMap(rows.first);
  }

  /// Programmes d'une chaîne entre deux instants (pour la grille TV).
  Future<List<EpgProgram>> programsBetween(
    String channelId,
    int startMs,
    int endMs,
  ) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      'epg_programs',
      where:
          'channel_id = ? AND stop_time > ? AND start_time < ?',
      whereArgs: <Object>[channelId, startMs, endMs],
      orderBy: 'start_time ASC',
    );
    return rows.map(EpgProgram.fromMap).toList(growable: false);
  }

  /// Récupère les programmes d'aujourd'hui pour une chaîne donnée.
  Future<List<EpgProgram>> todayPrograms(String channelId) {
    final DateTime now = DateTime.now();
    final DateTime startOfDay =
        DateTime(now.year, now.month, now.day);
    final DateTime endOfDay = startOfDay.add(const Duration(days: 1));
    return programsBetween(
      channelId,
      startOfDay.millisecondsSinceEpoch,
      endOfDay.millisecondsSinceEpoch,
    );
  }

  // ============================================================
  //  STATS
  // ============================================================

  /// Nombre total de programmes en base (pour l'écran EPG).
  Future<int> totalCount() async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.rawQuery('SELECT COUNT(*) as c FROM epg_programs');
    return (rows.first['c'] as int?) ?? 0;
  }
}
