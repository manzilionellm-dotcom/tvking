import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playlist_database.dart';

/// Mémoire durable des suppressions, commune au panel et aux sauvegardes.
/// Les empreintes sont hachées : aucun code IPTV supplémentaire n'est gardé.
abstract final class DeletedSources {
  static const String legacyKey = 'zuno.source.tv_refused.v1';

  /// Migration unique des anciens refus TV avant tout ajout/restauration.
  /// Le format historique contenait l'empreinte en clair et un horodatage.
  static Future<void> migrateLegacy() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(legacyKey);
    if (raw == null) return;
    final Object? value;
    try {
      value = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (value is! Map) return;
    await remember(<String>[
      for (final MapEntry<Object?, Object?> entry in value.entries)
        if (entry.key is String && entry.value is num) entry.key as String,
    ]);
    await prefs.remove(legacyKey);
  }

  static Future<List<String>> hashes(Iterable<String> fingerprints) async {
    final List<String> out = <String>[];
    for (final String fp in fingerprints.toSet()) {
      final Hash hash = await Sha256().hash(utf8.encode(fp));
      out.add(hash.bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join());
    }
    return out;
  }

  static Future<Set<String>> read() async {
    await migrateLegacy();
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query('deleted_sources');
    return rows.map((Map<String, Object?> row) => row['fingerprint'] as String).toSet();
  }

  static Future<void> remember(Iterable<String> fingerprints) async {
    final List<String> keys = await hashes(fingerprints);
    final Database db = await PlaylistDatabase.instance.database;
    await db.transaction((Transaction txn) => rememberHashes(txn, keys));
  }

  /// Sauvegarde v2 : seules des empreintes SHA-256 valides sont acceptées.
  /// On fusionne les refus ; une ancienne sauvegarde ne peut en retirer.
  static Future<void> restoreHashes(Iterable<Object?> values) async {
    final RegExp digest = RegExp(r'^[0-9a-f]{64}$');
    final List<String> keys = values.whereType<String>()
        .where((String key) => digest.hasMatch(key)).toSet().toList();
    final Database db = await PlaylistDatabase.instance.database;
    await db.transaction((Transaction txn) => rememberHashes(txn, keys));
  }

  static Future<void> rememberHashes(DatabaseExecutor db, List<String> keys) async {
    for (final String key in keys) {
      await db.insert('deleted_sources', <String, Object?>{'fingerprint': key},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}

class PlaylistDeletedException implements Exception {
  const PlaylistDeletedException();

  @override
  String toString() => 'Cette liste a été supprimée. Ajoute-la à nouveau pour la rétablir.';
}
