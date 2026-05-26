// =========================================================
//  remote_config_repository.dart — Provisioning à distance
// =========================================================
//  L'app fetch périodiquement un JSON hébergé par l'admin
//  (GitHub Gist, GitHub Pages, S3, n'importe quel endpoint
//  HTTP qui retourne du JSON). Le JSON contient un mapping
//  de MACs vers leurs playlists assignées :
//
//    {
//      "MK:A3:B2:F1:8E:91": {
//        "playlists": [
//          {
//            "name": "Mon abonnement",
//            "type": "m3u",
//            "url": "http://serveur.com/get.php?username=...",
//            "epg_url": "http://serveur.com/xmltv.php?username=..."
//          }
//        ]
//      },
//      "MK:99:88:77:66:55": {
//        "playlists": [
//          {
//            "name": "Test",
//            "type": "xtream",
//            "server": "http://serveur.com:8080",
//            "username": "user",
//            "password": "pass"
//          }
//        ]
//      }
//    }
//
//  Quand on trouve une entrée pour notre MAC :
//    - Si playlist nouvelle ou changée → on l'importe en local
//    - Si playlist déjà importée et identique → on ne fait rien
//    - Si playlist supprimée côté admin → on la supprime localement
//
//  Stocke l'URL de provisioning + le timestamp de dernière
//  sync dans SharedPreferences.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../playlists/data/playlist_repository.dart';
import '../../playlists/domain/playlist.dart';
import 'device_identity.dart';

class RemoteConfigStatus {
  const RemoteConfigStatus({
    required this.lastAttemptAt,
    required this.lastSuccessAt,
    required this.lastError,
    required this.url,
    required this.knownAtAdmin,
    required this.playlistsApplied,
  });

  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final String? lastError;
  final String? url;
  final bool knownAtAdmin;
  final int playlistsApplied;
}

class RemoteConfigRepository extends ChangeNotifier {
  RemoteConfigRepository._();
  static final RemoteConfigRepository instance =
      RemoteConfigRepository._();

  static const String _kUrlKey = 'remote_config.url';
  static const String _kLastSuccessKey = 'remote_config.last_success_at';
  static const String _kLastAttemptKey = 'remote_config.last_attempt_at';
  static const String _kLastHashKey = 'remote_config.last_hash';
  static const Duration _kPollInterval = Duration(minutes: 30);

  String? _url;
  DateTime? _lastSuccessAt;
  DateTime? _lastAttemptAt;
  String? _lastError;
  bool _knownAtAdmin = false;
  int _playlistsApplied = 0;
  Timer? _pollTimer;
  bool _syncing = false;

  RemoteConfigStatus get status => RemoteConfigStatus(
        lastAttemptAt: _lastAttemptAt,
        lastSuccessAt: _lastSuccessAt,
        lastError: _lastError,
        url: _url,
        knownAtAdmin: _knownAtAdmin,
        playlistsApplied: _playlistsApplied,
      );

  bool get isSyncing => _syncing;

  // ============================================================
  //  Init + polling
  // ============================================================

  Future<void> initialize() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _url = prefs.getString(_kUrlKey);
    final int? lastSuccess = prefs.getInt(_kLastSuccessKey);
    if (lastSuccess != null) {
      _lastSuccessAt = DateTime.fromMillisecondsSinceEpoch(lastSuccess);
    }
    final int? lastAttempt = prefs.getInt(_kLastAttemptKey);
    if (lastAttempt != null) {
      _lastAttemptAt = DateTime.fromMillisecondsSinceEpoch(lastAttempt);
    }
    notifyListeners();

    if (_url != null && _url!.isNotEmpty) {
      // Premier sync au démarrage + polling régulier
      unawaited(syncNow());
      _pollTimer = Timer.periodic(_kPollInterval, (_) => syncNow());
    }
  }

  Future<void> setUrl(String? url) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      _url = null;
      await prefs.remove(_kUrlKey);
      _pollTimer?.cancel();
      _pollTimer = null;
    } else {
      _url = url.trim();
      await prefs.setString(_kUrlKey, _url!);
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_kPollInterval, (_) => syncNow());
      unawaited(syncNow());
    }
    notifyListeners();
  }

  // ============================================================
  //  Sync : fetch + applique
  // ============================================================

  Future<void> syncNow() async {
    if (_url == null || _url!.isEmpty || _syncing) return;
    _syncing = true;
    _lastAttemptAt = DateTime.now();
    notifyListeners();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kLastAttemptKey,
      _lastAttemptAt!.millisecondsSinceEpoch,
    );

    try {
      final http.Response resp = await http
          .get(Uri.parse(_url!))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final String body = resp.body;

      // Si le contenu n'a pas changé depuis la dernière sync OK,
      // on évite de retoucher la base.
      final String hash = body.hashCode.toString();
      final String? previousHash = prefs.getString(_kLastHashKey);

      final Map<String, dynamic> full =
          jsonDecode(body) as Map<String, dynamic>;
      final String mac = await DeviceIdentity.instance.mac;

      // Deux formats supportés :
      //
      // 1) Worker Cloudflare (nouveau backend) : l'URL est
      //    `…/config/<MAC>` et le payload est déjà filtré pour
      //    cette MAC. Il a la forme `{ "name": "...", "playlists": [...] }`.
      //
      // 2) Legacy GitHub Gist : un seul JSON multi-MAC où
      //    chaque entrée racine est une MAC. Forme :
      //    `{ "MK:AA:..": { "playlists": [...] }, ... }`.
      //
      // On essaie le format 1 d'abord (présence de la clef
      // "playlists" en racine), puis on retombe sur le format 2.
      final dynamic mine = full.containsKey('playlists')
          ? full
          : full[mac];

      if (mine == null) {
        _knownAtAdmin = false;
        _playlistsApplied = 0;
        _lastError = null;
        _lastSuccessAt = DateTime.now();
        await prefs.setInt(
          _kLastSuccessKey,
          _lastSuccessAt!.millisecondsSinceEpoch,
        );
        await prefs.setString(_kLastHashKey, hash);
        notifyListeners();
        return;
      }

      _knownAtAdmin = true;

      if (previousHash == hash) {
        // Rien changé — on n'applique pas pour éviter de re-télécharger
        _lastSuccessAt = DateTime.now();
        await prefs.setInt(
          _kLastSuccessKey,
          _lastSuccessAt!.millisecondsSinceEpoch,
        );
        _lastError = null;
        notifyListeners();
        return;
      }

      // Applique : on supprime les playlists existantes provisionnées
      // par config distante, puis on importe celles du JSON.
      final List<dynamic> playlistsJson =
          (mine as Map<String, dynamic>)['playlists'] as List<dynamic>? ??
              <dynamic>[];

      int applied = 0;
      for (final dynamic raw in playlistsJson) {
        if (raw is! Map<String, dynamic>) continue;
        final String type = (raw['type'] as String?) ?? 'm3u';
        final String name = (raw['name'] as String?) ?? 'Distant';

        // Si une playlist du même nom existe déjà → on la supprime
        // puis on la re-crée (simple et idempotent).
        final List<Playlist> existing =
            PlaylistRepository.instance.currentPlaylists;
        for (final Playlist p in existing) {
          if (p.name == name && p.id != null) {
            await PlaylistRepository.instance.deletePlaylist(p.id!);
          }
        }

        try {
          if (type == 'xtream') {
            final String server = (raw['server'] as String?) ?? '';
            final String user = (raw['username'] as String?) ?? '';
            final String pass = (raw['password'] as String?) ?? '';
            if (server.isEmpty || user.isEmpty || pass.isEmpty) continue;
            await PlaylistRepository.instance.addXtreamPlaylist(
              name: name,
              serverUrl: server,
              username: user,
              password: pass,
            );
          } else {
            final String url = (raw['url'] as String?) ?? '';
            final String? epgUrl = raw['epg_url'] as String?;
            if (url.isEmpty) continue;
            await PlaylistRepository.instance.addM3uPlaylist(
              name: name,
              url: url,
              epgUrl: epgUrl,
            );
          }
          applied++;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[RemoteConfig] failed to apply "$name": $e');
          }
        }
      }

      _playlistsApplied = applied;
      _lastError = null;
      _lastSuccessAt = DateTime.now();
      await prefs.setInt(
        _kLastSuccessKey,
        _lastSuccessAt!.millisecondsSinceEpoch,
      );
      await prefs.setString(_kLastHashKey, hash);
      notifyListeners();
    } on Exception catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }
}
