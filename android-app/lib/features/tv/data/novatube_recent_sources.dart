import 'package:shared_preferences/shared_preferences.dart';

import '../../playlists/data/playlist_secret.dart';

/// Trois adresses saisies avec succès, chiffrées séparément pour chaque profil.
abstract final class NovatubeRecentSources {
  static String _key(String profile) => 'novatube_tv.recent_sources.v1.$profile';

  static Future<List<String>> read(String profile) async {
    final prefs = await SharedPreferences.getInstance();
    final records = prefs.getStringList(_key(profile)) ?? const <String>[];
    final result = <String>[];
    for (final record in records.take(3)) {
      if (!record.startsWith(PlaylistSecret.prefix)) continue;
      final address = await PlaylistSecret.open(record);
      if (address != null && Uri.tryParse(address)?.hasAuthority == true) {
        result.add(address);
      }
    }
    return result;
  }

  static Future<void> remember(String profile, String address) async {
    final previous = await read(profile);
    final records = <String>[];
    for (final item in <String>{address, ...previous}.take(3)) {
      final secret = await PlaylistSecret.seal(item);
      // Si le chiffrement échoue, aucune adresse en clair ne va sur disque.
      if (secret == null || !secret.startsWith(PlaylistSecret.prefix)) return;
      records.add(secret);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(profile), records);
  }
}
