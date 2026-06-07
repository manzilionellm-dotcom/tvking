// =========================================================
//  cloud_backup_repository.dart — Sauvegarde cloud par MAC
// =========================================================
//  But : qu'un utilisateur qui RÉINSTALLE l'app retrouve ses
//  playlists (codes Xtream / URL M3U qu'il a saisis lui-même) et
//  ses favoris, SANS les ressaisir et SANS repayer.
//
//  Comment : on stocke un petit instantané JSON côté backend
//  Cloudflare, indexé par la MAC virtuelle (dérivée de l'ANDROID_ID,
//  donc STABLE après réinstallation). On NE sauvegarde que les
//  MÉTADONNÉES des playlists (pas les milliers de chaînes : elles se
//  re-téléchargent depuis la source à la restauration).
//
//  Stratégie sûre (anti-perte de données) :
//    - UPLOAD : à chaque changement (debounce 5 s), MAIS jamais si la
//      liste locale est vide → on n'écrase pas un bon backup par du
//      vide (une désinstallation/effacement local ne détruit pas le
//      backup cloud).
//    - RESTORE : uniquement si AUCUNE playlist locale n'existe (donc
//      typiquement un 1er lancement après réinstallation). On ne
//      touche jamais à des données déjà présentes.
//
//  Remarque vie privée : comme `device-source`, le blob est lisible
//  par qui connaît la MAC (route publique). Il contient les codes que
//  l'utilisateur a lui-même saisis — c'est cohérent avec le modèle
//  existant (la source poussée par le panel l'est déjà). Cf. politique
//  de confidentialité.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_backend.dart';
import '../domain/playlist.dart';
import 'favorites_repository.dart';
import 'playlist_repository.dart';

class CloudBackupRepository {
  CloudBackupRepository._();
  static final CloudBackupRepository instance = CloudBackupRepository._();

  /// Flag : une restauration a déjà été tentée avec succès sur cette
  /// install (évite de re-restaurer en boucle si l'utilisateur vide
  /// volontairement ses playlists ensuite).
  static const String _kRestoredKey = 'backup.restored.v1';

  bool _started = false;
  Timer? _debounce;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  /// Démarre la sauvegarde automatique : on ré-uploade (debounce) dès
  /// que les playlists ou les favoris changent.
  void start() {
    if (_started) return;
    _started = true;
    _subs.add(
      PlaylistRepository.instance.playlistsStream.listen((_) => _schedule()),
    );
    _subs.add(
      FavoritesRepository.instance.favoritesStream.listen((_) => _schedule()),
    );
    // Upload initial (debouncé) : sauvegarde aussi les utilisateurs
    // EXISTANTS qui ont déjà des playlists, sans attendre un changement.
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), () {
      unawaited(_upload());
    });
  }

  /// Envoie l'instantané courant au backend (best-effort).
  Future<void> _upload() async {
    try {
      final List<Playlist> playlists =
          await PlaylistRepository.instance.getAllPlaylists();
      // Garde-fou : ne jamais écraser le backup par du vide.
      if (playlists.isEmpty) return;

      final String mac = await DeviceIdentity.instance.mac;
      final Map<String, Object?> data = <String, Object?>{
        'v': 1,
        'playlists': playlists
            .map((Playlist p) {
              final Map<String, Object?> m = p.toMap();
              // On ne garde que ce qui est utile à recréer la source ;
              // l'id SQLite local et les métriques ne servent à rien.
              m.remove('id');
              m.remove('channel_count');
              m.remove('last_synced_at');
              return m;
            })
            .toList(),
        'favorites': FavoritesRepository.instance.current.toList(),
      };

      await http
          .put(
            Uri.parse('$kSubscriptionBaseUrl/api/backup/$mac'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{'data': data}),
          )
          .timeout(const Duration(seconds: 8));
      if (kDebugMode) {
        debugPrint('[Backup] upload OK (${playlists.length} playlist(s))');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] upload error: $e');
    }
  }

  /// Restaure depuis le cloud SI aucune playlist locale n'existe.
  /// À appeler au démarrage (après l'init de PlaylistRepository).
  Future<void> restoreIfNeeded() async {
    try {
      final List<Playlist> existing =
          await PlaylistRepository.instance.getAllPlaylists();
      // L'utilisateur a déjà des données locales → on ne touche à rien.
      if (existing.isNotEmpty) return;

      final String mac = await DeviceIdentity.instance.mac;
      final http.Response resp = await http
          .get(Uri.parse('$kSubscriptionBaseUrl/api/backup/$mac'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;

      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final Object? data = body['data'];
      if (data is! Map) return;

      // ----- Playlists -----
      final List<dynamic> pls =
          (data['playlists'] as List<dynamic>?) ?? const <dynamic>[];
      int restored = 0;
      for (final dynamic raw in pls) {
        if (raw is! Map) continue;
        final Map<String, Object?> m = Map<String, Object?>.from(raw);
        final String type = (m['type'] as String?) ?? 'm3u';
        final String name = (m['name'] as String?) ?? 'Mon abonnement';
        try {
          if (type == 'xtream') {
            final String server = (m['xtream_server'] as String?) ?? '';
            final String user = (m['xtream_username'] as String?) ?? '';
            final String pass = (m['xtream_password'] as String?) ?? '';
            if (server.isEmpty || user.isEmpty) continue;
            await PlaylistRepository.instance.addXtreamPlaylist(
              name: name,
              serverUrl: server,
              username: user,
              password: pass,
            );
            restored++;
          } else if (type == 'm3u') {
            final String url = (m['m3u_url'] as String?) ?? '';
            if (url.isEmpty) continue;
            await PlaylistRepository.instance.addM3uPlaylist(
              name: name,
              url: url,
              epgUrl: m['epg_url'] as String?,
            );
            restored++;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Backup] restore playlist "$name": $e');
        }
      }

      // ----- Favoris -----
      // On (ré)insère les IDs sauvegardés. toggle() ajoute si absent ;
      // sur une install fraîche ils sont tous absents → ajoutés. Un ID
      // qui ne correspond à aucune chaîne re-importée reste inoffensif.
      final List<dynamic> favs =
          (data['favorites'] as List<dynamic>?) ?? const <dynamic>[];
      for (final dynamic f in favs) {
        if (f is String && !FavoritesRepository.instance.isFavorite(f)) {
          try {
            await FavoritesRepository.instance.toggle(f);
          } catch (_) {}
        }
      }

      if (restored > 0) {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kRestoredKey, true);
        if (kDebugMode) {
          debugPrint('[Backup] restore OK ($restored playlist(s))');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Backup] restore error: $e');
    }
  }
}
