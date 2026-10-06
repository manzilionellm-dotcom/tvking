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
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../../core/app/repair_flags.dart';
import '../../../core/blackbox/black_box.dart';
import '../../playlists/data/playlist_database.dart';
import '../domain/epg_program.dart';
import 'epg_fetch.dart';

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
  /// et l'insère en base.
  ///
  /// • [knownChannelIds] (M3U) : seuls ces identifiants sont gardés.
  /// • [channelIdMap] (Xtream) : identifiant XMLTV → chaînes de l'app
  ///   (voir epg_targets.dart). Avant le 4 octobre 2026 le guide Xtream
  ///   n'était jamais importé.
  /// • Le téléchargement et le décodage se font dans un ISOLATE : le fil
  ///   UI ne lit plus 100 Mo de XML. Les rangées arrivent par lots de 500
  ///   et sont insérées ici. Repli `zuno.epg.inline_parse` (ou un
  ///   [httpClient] injecté par les tests) : tout en ligne, comme avant.
  /// • Délais BORNÉS : [connectTimeout] pour les en-têtes, [idleTimeout]
  ///   pour le silence entre deux paquets. Dépassés → exception, et le
  ///   verrou [isSyncing] est rendu (avant, un serveur muet le gardait
  ///   jusqu'au redémarrage).
  /// • Un ré-import remplace le guide d'une chaîne au lieu de le doubler.
  Future<int> downloadAndImport({
    required String url,
    Set<String>? knownChannelIds,
    Map<String, List<String>>? channelIdMap,
    http.Client? httpClient,
    void Function(int progressBytes)? onProgress,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration idleTimeout = const Duration(seconds: 60),
    bool? inIsolate,
  }) async {
    if (_syncing) return 0;
    _syncing = true;
    final Stopwatch sw = Stopwatch()..start();
    try {
      await initialize();
      // On purge d'abord les vieux programmes pour faire de la place.
      await purgeStale();
      final Database db = await PlaylistDatabase.instance.database;
      final _RowSink sink = _RowSink(db);
      final bool isolate =
          inIsolate ?? (httpClient == null && !RepairFlags.epgInlineParse);
      int total;
      if (isolate) {
        total = await _importInIsolate(
          url: url,
          knownIds: knownChannelIds,
          idMap: channelIdMap,
          connectTimeout: connectTimeout,
          idleTimeout: idleTimeout,
          onProgress: onProgress,
          sink: sink,
        );
      } else {
        final http.Client client = httpClient ?? http.Client();
        try {
          total = await fetchXmltvRows(
            url: url,
            client: client,
            knownIds: knownChannelIds,
            idMap: channelIdMap,
            connectTimeout: connectTimeout,
            idleTimeout: idleTimeout,
            onProgress: onProgress,
            onRows: sink.addRows,
          );
        } finally {
          if (httpClient == null) client.close();
        }
      }
      await sink.flush();
      BlackBox.instance.info(
        'EPG',
        'guide : $total programmes pour ${sink.channels} chaîne(s) '
            'en ${sw.elapsedMilliseconds} ms'
            '${isolate ? ' (isolate)' : ''}',
      );
      if (!_changesController.isClosed) {
        _changesController.add(null);
      }
      return total;
    } finally {
      _syncing = false;
    }
  }

  /// Télécharge et décode dans un isolate ; insère ici par lots.
  /// L'isolate est tué dans tous les cas à la fin (fin, erreur, délai).
  Future<int> _importInIsolate({
    required String url,
    required Set<String>? knownIds,
    required Map<String, List<String>>? idMap,
    required Duration connectTimeout,
    required Duration idleTimeout,
    required void Function(int progressBytes)? onProgress,
    required _RowSink sink,
  }) async {
    final ReceivePort rx = ReceivePort();
    Isolate? worker;
    try {
      worker = await Isolate.spawn<_EpgJob>(
        _epgWorker,
        _EpgJob(
          url: url,
          knownIds: knownIds?.toList(growable: false),
          idMap: idMap,
          connectTimeoutMs: connectTimeout.inMilliseconds,
          idleTimeoutMs: idleTimeout.inMilliseconds,
          port: rx.sendPort,
          gzipByHeader: RepairFlags.epgGzipByHeader,
        ),
        onError: rx.sendPort,
        onExit: rx.sendPort,
        debugName: 'zuno-epg',
      );
      int total = 0;
      bool done = false;
      await for (final Object? msg in rx) {
        if (msg == null) {
          // onExit. Normal après « done », sinon l'isolate est mort.
          if (done) break;
          throw StateError('EPG : décodage interrompu (isolate arrêté)');
        }
        if (msg is int) {
          onProgress?.call(msg);
          continue;
        }
        if (msg is String) {
          if (msg.startsWith('done:')) {
            total = int.tryParse(msg.substring(5)) ?? total;
            done = true;
            break;
          }
          throw Exception(msg.startsWith('error:') ? msg.substring(6) : msg);
        }
        if (msg is List) {
          if (msg.isNotEmpty && msg.first is Map) {
            await sink.addRows(<Map<String, Object?>>[
              for (final Object? m in msg)
                if (m is Map) m.cast<String, Object?>(),
            ]);
            continue;
          }
          // onError : [erreur, pile].
          throw Exception('EPG : ${msg.isEmpty ? 'erreur' : msg.first}');
        }
      }
      return total;
    } finally {
      rx.close();
      worker?.kill(priority: Isolate.immediate);
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

  /// Programmes qui chevauchent [startMs, endMs) (guide « ce soir »).
  ///
  /// Plafonné : une grille complète peut faire des centaines de milliers
  /// de lignes. On n'en ramène qu'un échantillon, trié par heure de début.
  /// Toute erreur (base absente, disque) renvoie une liste vide : l'assistant
  /// affiche « rien ce soir » et le lecteur n'est pas concerné.
  Future<List<EpgProgram>> programsOverlapping(
    int startMs,
    int endMs, {
    int limit = 500,
  }) async {
    try {
      await initialize();
      final Database db = await PlaylistDatabase.instance.database;
      final int cap = limit < 1 ? 1 : (limit > 1000 ? 1000 : limit);
      final List<Map<String, Object?>> rows = await db.query(
        'epg_programs',
        where: 'stop_time > ? AND start_time < ?',
        whereArgs: <Object>[startMs, endMs],
        orderBy: 'start_time ASC',
        limit: cap,
      );
      return rows.map(EpgProgram.fromMap).toList(growable: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[EpgRepository] programmes du soir : $e');
      return const <EpgProgram>[];
    }
  }

  /// Nombre total de programmes en base (pour l'écran EPG).
  Future<int> totalCount() async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows =
        await db.rawQuery('SELECT COUNT(*) as c FROM epg_programs');
    return (rows.first['c'] as int?) ?? 0;
  }
}

/// Insère les rangées par lots de 500. À la première apparition d'une
/// chaîne dans CET import, ses programmes encore en base sont retirés
/// dans le même lot, AVANT ses nouvelles lignes (pas de clé unique dans
/// la table ; une chaîne absente du fichier garde son ancien guide).
class _RowSink {
  _RowSink(this.db);
  final Database db;
  Batch? _batch;
  int _pending = 0;
  final Set<String> _refreshed = <String>{};

  int get channels => _refreshed.length;

  Future<void> addRows(List<Map<String, Object?>> rows) async {
    for (final Map<String, Object?> row in rows) {
      final Batch batch = _batch ??= db.batch();
      final String channelId = row['channel_id'] as String;
      if (_refreshed.add(channelId)) {
        batch.delete(
          'epg_programs',
          where: 'channel_id = ?',
          whereArgs: <Object>[channelId],
        );
      }
      batch.insert('epg_programs', row);
      _pending++;
      if (_pending >= 500) await flush();
    }
  }

  Future<void> flush() async {
    final Batch? batch = _batch;
    if (batch == null || _pending == 0) return;
    _batch = null;
    _pending = 0;
    await batch.commit(noResult: true);
  }
}

/// Ce que l'isolate reçoit. Tout est copiable entre isolates.
class _EpgJob {
  const _EpgJob({
    required this.url,
    required this.knownIds,
    required this.idMap,
    required this.connectTimeoutMs,
    required this.idleTimeoutMs,
    required this.port,
    required this.gzipByHeader,
  });
  final String url;
  final List<String>? knownIds;
  final Map<String, List<String>>? idMap;
  final int connectTimeoutMs;
  final int idleTimeoutMs;
  final SendPort port;

  /// Repli `zuno.epg.gzip_by_header`, lu sur le fil principal : un isolate
  /// ne voit pas les interrupteurs chargés au démarrage.
  final bool gzipByHeader;
}

/// Corps de l'isolate : télécharge, décode, envoie les lots, puis
/// « done:<total> » ou « error:<message> ». Jamais d'accès à la base.
Future<void> _epgWorker(_EpgJob job) async {
  final http.Client client = http.Client();
  try {
    final int total = await fetchXmltvRows(
      url: job.url,
      client: client,
      knownIds: job.knownIds?.toSet(),
      idMap: job.idMap,
      connectTimeout: Duration(milliseconds: job.connectTimeoutMs),
      idleTimeout: Duration(milliseconds: job.idleTimeoutMs),
      onProgress: (int bytes) => job.port.send(bytes),
      onRows: (List<Map<String, Object?>> rows) async => job.port.send(rows),
      gzipByHeader: job.gzipByHeader,
    );
    job.port.send('done:$total');
  } catch (e) {
    job.port.send('error:$e');
  } finally {
    client.close();
  }
}
