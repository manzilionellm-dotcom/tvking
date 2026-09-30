// =========================================================
//  remote_source_repository.dart — Source poussée par MAC
// =========================================================
//  Modèle « tout géré par le revendeur » : le client n'entre RIEN.
//  Le revendeur assigne la source IPTV (Xtream ou M3U) à l'appareil
//  par sa MAC depuis le panel admin. L'app vient ici la chercher au
//  démarrage et la charge automatiquement.
//
//  Flux :
//    1. On lit la MAC virtuelle de l'appareil (DeviceIdentity).
//    2. GET {backend}/api/device-source/<mac> → { source: {...} | null }.
//    3. Si une source est assignée et qu'elle n'est pas DÉJÀ en base
//       locale (dédup), on la charge via PlaylistRepository.
//
//  Robustesse : ne throw jamais. Si le réseau est down ou qu'aucune
//  source n'est assignée, on ne fait rien (l'app garde ce qu'elle a).
//
//  NB conformité AGENTS.md règle n°2 : aucune URL de flux IPTV n'est
//  en dur ici — tout vient du backend, assigné par l'admin.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../channels/data/recently_watched_repository.dart';
import '../../../core/blackbox/black_box.dart';
import '../../device/data/device_identity.dart';
import '../../device/data/device_secret.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../domain/playlist.dart';
import '../domain/source_fingerprint.dart';
import 'favorites_repository.dart';
import 'playlist_database.dart';
import 'playlist_repository.dart';
import 'removed_list_notice.dart';

/// Résultat d'une synchro de source distante — sert à afficher un
/// message PRÉCIS côté UI au lieu d'un vague « pas de chaînes ».
enum RemoteSyncResult {
  /// Aucune source assignée à cette MAC (ou MAC inconnue du serveur).
  noSource,

  /// Source reçue et chargée (ou déjà présente) avec des chaînes.
  loaded,

  /// Source reçue mais le chargement a échoué (0 chaîne, identifiants/
  /// URL invalides, provider injoignable…). → message « vérifie l'URL ».
  sourceFailed,

  /// Problème réseau (serveur injoignable / réponse non 200).
  networkError,
}

abstract final class RemoteSourceRepository {
  /// Empreintes déjà vues sur CETTE box (listes venues du panel).
  static const String rememberedKey = 'zuno.panel_sources.v1';

  static Future<void> _queue = Future<void>.value();

  /// Une seule synchro à la fois. La suivante attend la fin de
  /// la précédente, sans en lancer une deuxième en parallèle.
  static Future<T> _serial<T>(Future<T> Function() job) {
    final Completer<T> done = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await job());
      } catch (e, st) {
        if (!done.isCompleted) done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// Récupère la source assignée à cet appareil et la charge si besoin.
  /// Best effort, idempotent (la dédup évite de réimporter à chaque boot).
  /// Renvoie un [RemoteSyncResult] pour permettre un diagnostic précis.
  static Future<RemoteSyncResult> sync() {
    return _serial(_syncBody);
  }

  /// Efface tout de suite les listes dont le panel a publié
  /// l'empreinte (réponse légère de /api/status). N'importe rien.
  /// Un échec réseau ne doit pas appeler cette méthode.
  static Future<int> applyRevocations(List<String> revoked) {
    if (revoked.isEmpty) return Future<int>.value(0);
    return _serial(() => _wipeFingerprints(revoked.toSet()));
  }

  static Future<RemoteSyncResult> _syncBody() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) return RemoteSyncResult.noSource;

      // Enregistre le secret de cette box avant de demander les codes.
      // Si le serveur connaît déjà l'empreinte, la requête suivante
      // doit présenter le header. Sinon (box pas encore enrôlée côté
      // serveur), l'ancienne lecture par MAC reste acceptée.
      await DeviceSecret.instance.enroll(mac);
      final http.Response resp = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/device-source/$mac'),
            headers: await DeviceSecret.instance.headers(),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        BlackBox.instance.warn('PANEL', 'device-source HTTP ${resp.statusCode}');
        return RemoteSyncResult.networkError;
      }

      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;

      // D'abord ce que le panel a RETIRÉ. On ne le fait qu'après
      // un HTTP 200 : une coupure ne vide pas la box.
      await _reconcileFromBody(body);

      // MULTI-SOURCES (jusqu'à 6 par MAC côté panel, aucune limite ici) : si le
      // serveur renvoie un tableau `sources`, on les charge TOUTES ; sur TV
      // elles sont FUSIONNÉES dans Direct (PlaylistRepository.mergeAllPlaylists).
      // Repli sur la source unique historique si le tableau est absent.
      final Object? list = body['sources'];
      if (list is List && list.isNotEmpty) {
        RemoteSyncResult agg = RemoteSyncResult.noSource;
        for (final Object? item in list) {
          if (item is Map<String, dynamic>) {
            final RemoteSyncResult r = await _applySource(item);
            if (r == RemoteSyncResult.loaded) {
              agg = RemoteSyncResult.loaded;
            } else if (agg != RemoteSyncResult.loaded &&
                r == RemoteSyncResult.sourceFailed) {
              agg = RemoteSyncResult.sourceFailed;
            }
          }
        }
        return agg;
      }

      final Object? src = body['source'];
      if (src is! Map<String, dynamic>) {
        return RemoteSyncResult.noSource; // null = rien d'assigné
      }
      return await _applySource(src);
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteSource] sync error: $e');
      BlackBox.instance.warn('PANEL', 'device-source injoignable : $e');
      return RemoteSyncResult.networkError;
    }
  }

  /// Restaure l'historique de visionnage depuis le serveur (synchro multi-box).
  /// L'app appelle ceci au démarrage : si la box est neuve (historique local
  /// vide), on récupère l'historique sauvegardé pour CETTE MAC et on l'amorce,
  /// pour retrouver « Récemment » et « Pour vous » immédiatement. Best-effort :
  /// ne throw jamais, n'écrase jamais un historique local déjà présent.
  static Future<void> syncHistory() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) return;
      final http.Response resp = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/history/$mac'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final Object? rec = body['recent'];
      if (rec is List && rec.isNotEmpty) {
        final List<String> ids =
            rec.map((Object? e) => e.toString()).toList();
        await RecentlyWatchedRepository.instance.seedIfEmpty(ids);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteSource] history sync error: $e');
    }
  }

  /// Charge la source en base locale si elle n'y est pas déjà.
  static Future<RemoteSyncResult> _applySource(Map<String, dynamic> src) async {
    final String type = (src['type'] as String?)?.trim().toLowerCase() ?? '';
    final String label =
        (src['label'] as String?)?.trim().isNotEmpty == true
            ? (src['label'] as String).trim()
            : 'Mon abonnement';
    final String? epg = (src['epg_url'] as String?)?.trim();

    // On s'assure que la liste locale est chargée avant la dédup.
    final List<Playlist> existing =
        await PlaylistRepository.instance.getAllPlaylists();

    if (type == 'xtream') {
      final String server = (src['server_url'] as String?)?.trim() ?? '';
      final String user = (src['username'] as String?)?.trim() ?? '';
      final String pass = (src['password'] as String?)?.trim() ?? '';
      if (server.isEmpty || user.isEmpty || pass.isEmpty) {
        return RemoteSyncResult.sourceFailed;
      }

      final bool already = existing.any((Playlist p) =>
          p.type == PlaylistType.xtream &&
          p.xtreamServer == server &&
          p.xtreamUsername == user);
      if (already) return RemoteSyncResult.loaded;

      try {
        await PlaylistRepository.instance.addXtreamPlaylist(
          name: label,
          serverUrl: server,
          username: user,
          password: pass,
        );
        if (kDebugMode) debugPrint('[RemoteSource] Xtream chargé ($server)');
        return RemoteSyncResult.loaded;
      } catch (e) {
        // Identifiants/serveur invalides, 0 chaîne… → le repo a rejeté.
        if (kDebugMode) debugPrint('[RemoteSource] Xtream KO: $e');
        return RemoteSyncResult.sourceFailed;
      }
    } else if (type == 'm3u') {
      final String m3u = (src['m3u_url'] as String?)?.trim() ?? '';
      if (m3u.isEmpty) return RemoteSyncResult.sourceFailed;

      final bool already = existing.any((Playlist p) =>
          p.type == PlaylistType.m3u && p.m3uUrl == m3u);
      if (already) return RemoteSyncResult.loaded;

      try {
        await PlaylistRepository.instance.addM3uPlaylist(
          name: label,
          url: m3u,
          epgUrl: (epg != null && epg.isNotEmpty) ? epg : null,
        );
        if (kDebugMode) debugPrint('[RemoteSource] M3U chargé');
        return RemoteSyncResult.loaded;
      } catch (e) {
        // URL M3U incomplète / provider injoignable / 0 chaîne.
        if (kDebugMode) debugPrint('[RemoteSource] M3U KO: $e');
        return RemoteSyncResult.sourceFailed;
      }
    }
    return RemoteSyncResult.noSource;
  }

  /// Compare les listes encore assignées, celles déjà vues, et
  /// les tombstones. Met à jour la mémoire locale.
  static Future<void> _reconcileFromBody(Map<String, dynamic> body) async {
    final List<Map<String, dynamic>> currentMaps = <Map<String, dynamic>>[];
    final Object? list = body['sources'];
    if (list is List) {
      for (final Object? item in list) {
        if (item is Map<String, dynamic>) currentMaps.add(item);
      }
    } else {
      final Object? src = body['source'];
      if (src is Map<String, dynamic>) currentMaps.add(src);
    }
    final Set<String> current = <String>{};
    for (final Map<String, dynamic> item in currentMaps) {
      final String? fp = SourceFingerprint.fromMap(item);
      if (fp != null) current.add(fp);
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Set<String> remembered =
        (prefs.getStringList(rememberedKey) ?? const <String>[]).toSet();
    final Set<String> revoked =
        SourceFingerprint.revokedFromBody(body).toSet();
    await _wipeFingerprints(fingerprintsToDrop(
      remembered: remembered,
      current: current,
      revoked: revoked,
    ));
    await prefs.setStringList(rememberedKey, current.toList());
  }

  /// Supprime les playlists locales dont l'empreinte est dans [drop].
  /// Chaînes, favoris, récents, sessions et identifiants (la ligne
  /// playlist porte le mot de passe et l'URL) partent avec.
  /// Renvoie le nombre de listes vraiment retirées.
  static Future<int> _wipeFingerprints(Set<String> drop) async {
    if (drop.isEmpty) return 0;
    final List<Playlist> playlists =
        await PlaylistRepository.instance.getAllPlaylists();
    int removed = 0;
    final List<String> channelIds = <String>[];
    for (final Playlist playlist in playlists) {
      final int? id = playlist.id;
      if (id == null) continue;
      final String? fp = playlist.type == PlaylistType.xtream
          ? SourceFingerprint.xtream(
              playlist.xtreamServer, playlist.xtreamUsername)
          : SourceFingerprint.m3u(playlist.m3uUrl);
      if (fp == null || !drop.contains(fp)) continue;
      channelIds.addAll(await _channelIdsOf(id));
      await PlaylistRepository.instance.deletePlaylist(id);
      removed++;
    }
    if (channelIds.isNotEmpty) {
      await FavoritesRepository.instance.forgetChannels(channelIds);
      await RecentlyWatchedRepository.instance.forgetChannels(channelIds);
      await _forgetSessions(channelIds);
    }
    if (removed > 0) {
      final List<Playlist> left =
          await PlaylistRepository.instance.getAllPlaylists();
      RemovedListNotice.instance.signal(
        removed: removed,
        noneLeft: left.isEmpty,
      );
    }
    return removed;
  }

  static Future<List<String>> _channelIdsOf(int playlistId) async {
    final Database db = await PlaylistDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      'channels',
      columns: const <String>['external_id'],
      where: 'playlist_id = ?',
      whereArgs: <Object>[playlistId],
    );
    return rows
        .map((Map<String, Object?> r) => (r['external_id'] as String?) ?? '')
        .where((String id) => id.isNotEmpty)
        .toList();
  }

  static Future<void> _forgetSessions(List<String> channelIds) async {
    final Database db = await PlaylistDatabase.instance.database;
    const int chunk = 400;
    for (int i = 0; i < channelIds.length; i += chunk) {
      final List<String> part = channelIds.sublist(
        i,
        i + chunk > channelIds.length ? channelIds.length : i + chunk,
      );
      final String marks = List<String>.filled(part.length, '?').join(',');
      await db.delete(
        'watch_sessions',
        where: 'channel_id IN ($marks)',
        whereArgs: part,
      );
    }
  }
}
