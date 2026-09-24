// =========================================================
//  watch_history_repository.dart — Sessions de visionnage
// =========================================================
//  Tracking précis du temps passé sur chaque chaîne. Sert à
//  trois mécaniques Hook Model :
//
//    1. "Reprendre où tu t'es arrêté" — la session la plus
//       récente apparaît dans une bannière au top de l'accueil
//       si elle date de < 60 min.
//
//    2. Affinity scoring par genre — somme des durations par
//       chaîne, agrégée par genre via ChannelClassifier. Permet
//       de réordonner les rangées de l'accueil selon ce que
//       l'utilisateur regarde *réellement* (pas juste ce qu'il
//       a ouvert une fois par erreur).
//
//    3. Adaptation horaire — extraction de l'heure typique de
//       visionnage par genre. Si l'user regarde du sport le
//       samedi soir, on met Sports en haut le samedi soir.
//
//  Cycle de vie d'une session :
//      startSession(channelId, channelName)
//        → écrit une ligne avec started_at, ended_at=null
//        → renvoie l'ID de session
//      endSession(sessionId)
//        → met à jour ended_at + duration_ms
//
//  Les sessions abandonnées (app killée) restent avec ended_at
//  null. On les nettoie au démarrage en leur appliquant une
//  durée par défaut de 5 min.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/flavor/flavor.dart';
import '../../playlists/data/playlist_database.dart';

/// Snapshot d'une session pour l'UI.
@immutable
class WatchSession {
  const WatchSession({
    required this.channelId,
    required this.channelName,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
  });

  final String channelId;
  final String? channelName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationMs;

  /// Temps écoulé depuis la fin de cette session.
  Duration timeSinceEnd(DateTime now) =>
      now.difference(endedAt ?? startedAt);
}

class WatchHistoryRepository extends ChangeNotifier {
  WatchHistoryRepository._();
  static final WatchHistoryRepository instance =
      WatchHistoryRepository._();

  /// Durée par défaut appliquée aux sessions abandonnées (app killée
  /// sans appel à endSession). 5 min = compromis entre "vraie session
  /// regardée" et "ouverture par erreur".
  static const Duration _kAbandonedFallback = Duration(minutes: 5);

  WatchSession? _lastSession;
  WatchSession? get lastSession => _lastSession;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final Database db = await PlaylistDatabase.instance.database;

    // Nettoyage des sessions abandonnées au boot précédent.
    await _cleanupAbandoned(db);

    // Charge la dernière session pour la bannière "Reprendre".
    await _refreshLastSession();
  }

  Future<void> _cleanupAbandoned(Database db) async {
    final int fallbackMs = _kAbandonedFallback.inMilliseconds;
    await db.rawUpdate(
      'UPDATE watch_sessions '
      'SET ended_at = started_at + ?, duration_ms = ? '
      'WHERE ended_at IS NULL',
      <Object?>[fallbackMs, fallbackMs],
    );
  }

  Future<void> _refreshLastSession() async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      'watch_sessions',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      _lastSession = null;
    } else {
      _lastSession = _fromRow(rows.first);
    }
    notifyListeners();
  }

  WatchSession _fromRow(Map<String, Object?> row) {
    final int started = row['started_at'] as int;
    final int? ended = row['ended_at'] as int?;
    final int duration = (row['duration_ms'] as int?) ?? 0;
    return WatchSession(
      channelId: row['channel_id'] as String,
      channelName: row['channel_name'] as String?,
      startedAt: DateTime.fromMillisecondsSinceEpoch(started),
      endedAt: ended != null
          ? DateTime.fromMillisecondsSinceEpoch(ended)
          : null,
      durationMs: duration,
    );
  }

  // ============================================================
  //  Cycle de vie d'une session
  // ============================================================

  /// À appeler dès que le player démarre la lecture d'une chaîne.
  /// Renvoie l'ID de session à passer à `endSession()`.
  Future<int> startSession({
    required String channelId,
    String? channelName,
  }) async {
    // Mode incognito (flavor « Privé ») : on n'enregistre aucune session de
    // visionnage (ni stats d'affinité). -1 = session factice ignorée par
    // endSession (WHERE id = -1 ne touche rien).
    if (FlavorConfig.current.adultOnly) return -1;
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int id = await db.insert('watch_sessions', <String, Object?>{
      'channel_id': channelId,
      'channel_name': channelName,
      'started_at': now,
      'ended_at': null,
      'duration_ms': 0,
    });
    await _refreshLastSession();
    return id;
  }

  /// À appeler dans `dispose()` du player. Si l'app est killée avant,
  /// `_cleanupAbandoned` rattrape au boot suivant.
  Future<void> endSession(int sessionId) async {
    if (sessionId <= 0) return;
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      'watch_sessions',
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final int started = rows.first['started_at'] as int;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int duration = (now - started).clamp(0, 12 * 60 * 60 * 1000);

    await db.update(
      'watch_sessions',
      <String, Object?>{
        'ended_at': now,
        'duration_ms': duration,
      },
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );
    await _refreshLastSession();
  }

  // ============================================================
  //  Lectures agrégées (affinity, time-of-day)
  // ============================================================

  /// Somme totale du temps de visionnage par `channel_id`, sur les
  /// `days` derniers jours. Utilisé par l'affinity scoring (côté
  /// caller : on regroupe par genre via ChannelClassifier).
  Future<Map<String, int>> watchTimeByChannel({int days = 30}) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int since = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT channel_id, SUM(duration_ms) AS total '
      'FROM watch_sessions '
      'WHERE started_at >= ? '
      'GROUP BY channel_id',
      <Object?>[since],
    );
    final Map<String, int> out = <String, int>{};
    for (final Map<String, Object?> r in rows) {
      out[r['channel_id'] as String] = (r['total'] as int?) ?? 0;
    }
    return out;
  }

  /// Distribution du temps de visionnage par heure de la journée
  /// (0-23). Utilisé pour l'adaptation horaire — on apprend quand
  /// l'utilisateur regarde quoi.
  Future<Map<int, int>> watchTimeByHour({int days = 30}) async {
    await initialize();
    final Database db = await PlaylistDatabase.instance.database;
    final int since = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT started_at, duration_ms FROM watch_sessions '
      'WHERE started_at >= ?',
      <Object?>[since],
    );
    final Map<int, int> out = <int, int>{};
    for (final Map<String, Object?> r in rows) {
      final DateTime t = DateTime.fromMillisecondsSinceEpoch(
        r['started_at'] as int,
      );
      final int hour = t.hour;
      out[hour] = (out[hour] ?? 0) + ((r['duration_ms'] as int?) ?? 0);
    }
    return out;
  }

  Future<void> clear() async {
    final Database db = await PlaylistDatabase.instance.database;
    await db.delete('watch_sessions');
    _lastSession = null;
    notifyListeners();
  }
}
