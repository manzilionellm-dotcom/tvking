import 'package:sqflite/sqflite.dart';

import '../../playlists/data/playlist_database.dart';
import '../domain/cinema_models.dart';

/// Certaines sources révèlent le classement seulement dans la fiche détaillée.
/// On retient ce signal positif par source, sans secret et sans changer l'id.
/// La clé étrangère le retire avec la source ou son profil propriétaire.
abstract final class CinemaAdultSignals {
  static Future<Set<String>> read(String profileId) async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT a.title_id FROM cinema_adult_signals a '
      'JOIN playlists p ON p.id = a.playlist_id WHERE p.profile_id = ?',
      <Object>[profileId],
    );
    return rows
        .map((Map<String, Object?> row) => row['title_id'] as String)
        .toSet();
  }

  static Future<bool> remember(
          {required String profileId,
          required int playlistId,
          required String titleId}) =>
      rememberMany(
          profileId: profileId,
          playlistId: playlistId,
          titleIds: <String>{titleId});

  /// Les épisodes déjà reçus avec une fiche adulte héritent de la même preuve.
  /// Aucun autre épisode ni aucune autre fiche n'est demandé au fournisseur.
  static Future<bool> rememberMany(
      {required String profileId,
      required int playlistId,
      required Set<String> titleIds}) async {
    final Database db = await PlaylistDatabase.instance.database;
    return db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> owner = await txn.query('playlists',
          columns: <String>['id'],
          where: 'id = ? AND profile_id = ?',
          whereArgs: <Object>[playlistId, profileId],
          limit: 1);
      if (owner.isEmpty) return false;
      final List<Map<String, Object?>> downloads = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'downloads'");
      final Batch batch = txn.batch();
      for (final String titleId in titleIds) {
        batch.insert(
            'cinema_adult_signals',
            <String, Object>{
              'playlist_id': playlistId,
              'title_id': titleId,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (downloads.isNotEmpty) {
          batch.update('downloads', <String, Object>{'declared_adult': 1},
              where: 'id = ? AND profile_id = ?',
              whereArgs: <Object>[titleId, profileId]);
        }
      }
      await batch.commit(noResult: true);
      return true;
    });
  }

  static CinemaTitle apply(CinemaTitle title, Set<String> known) =>
      !title.declaredAdult && known.contains(title.id)
          ? title.copyWith(declaredAdult: true)
          : title;
}
