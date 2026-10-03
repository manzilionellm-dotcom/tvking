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
//  Robustesse : ne throw jamais. Si le réseau est down, on ne fait
//  rien (l'app garde ce qu'elle a).
//
//  Effacement panel → box : voir remote_source_sync.dart.
//  `source: null` tout seul ne veut PAS dire « effacé » (jamais
//  assigné, ou licence bloquée). Seul `cleared: true` le dit, et
//  seulement si l'interrupteur HONOR_REMOTE_LIST_CLEAR est allumé
//  (coupé par défaut). Sinon l'app garde la liste, comme avant.
//
//  NB conformité AGENTS.md règle n°2 : aucune URL de flux IPTV n'est
//  en dur ici — tout vient du backend, assigné par l'admin.
// =========================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../channels/data/recently_watched_repository.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../domain/playlist.dart';
import 'playlist_repository.dart';
import 'remote_pushed_memory.dart';
import 'remote_source_sync.dart';

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
  /// Une requête déjà en vol, seulement quand l'interrupteur d'effacement
  /// est allumé (le sondage à 2 s peut croiser les autres sondages).
  static Future<RemoteSyncResult>? _clearPoll;

  /// Récupère la source assignée à cet appareil et la charge si besoin.
  /// Best effort, idempotent (la dédup évite de réimporter à chaque boot).
  /// Renvoie un [RemoteSyncResult] pour permettre un diagnostic précis.
  static Future<RemoteSyncResult> sync() {
    // Interrupteur coupé : aucun partage de requête, chaque appel part
    // comme avant.
    if (!kHonorRemoteListClear) return _syncOnce();
    final Future<RemoteSyncResult>? running = _clearPoll;
    if (running != null) return running;
    final Future<RemoteSyncResult> run = _syncOnce();
    _clearPoll = run;
    return run.whenComplete(() {
      if (identical(_clearPoll, run)) _clearPoll = null;
    });
  }

  static Future<RemoteSyncResult> _syncOnce() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) return RemoteSyncResult.noSource;

      final http.Response resp = await http.get(
        Uri.parse('$kSubscriptionBaseUrl/api/device-source/$mac'),
        headers: const <String, String>{'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return RemoteSyncResult.networkError;

      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;

      // Effacement explicite (cleared:true) ou remplacement de trio.
      // Inerte pour l'écran tant que l'interrupteur est coupé : dans ce
      // cas on note seulement les identités reçues, sans rien supprimer.
      await _applyClearPlan(body);

      // TRIO (jusqu'à 3 sources sur une MAC) : si le serveur renvoie un
      // tableau `sources`, on les charge TOUTES. Le client peut ensuite
      // basculer de l'une à l'autre depuis l'accueil. Repli sur la source
      // unique historique si le tableau est absent.
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
        // null sans source exploitable. La suppression éventuelle a déjà
        // été décidée par _applyClearPlan (et seulement si l'interrupteur
        // est allumé ET que le serveur a envoyé cleared:true).
        return RemoteSyncResult.noSource;
      }
      return await _applySource(src);
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteSource] sync error: $e');
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
      final http.Response resp = await http.get(
        Uri.parse('$kSubscriptionBaseUrl/api/history/$mac'),
        headers: const <String, String>{'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final Object? rec = body['recent'];
      if (rec is List && rec.isNotEmpty) {
        final List<String> ids = rec.map((Object? e) => e.toString()).toList();
        await RecentlyWatchedRepository.instance.seedIfEmpty(ids);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteSource] history sync error: $e');
    }
  }

  /// Applique le plan d'effacement. Ne throw jamais : un souci de
  /// préférences ne doit pas empêcher le chargement d'une source.
  static Future<void> _applyClearPlan(Map<String, dynamic> body) async {
    try {
      final Set<String> liveKeys = payloadIdentityKeys(body);
      final bool explicitClear = liveKeys.isEmpty && body['cleared'] == true;
      // source:null sans drapeau d'effacement : jamais assigné, licence
      // bloquée, ou ancien worker. Aucun accès disque, aucune suppression.
      if (!explicitClear && liveKeys.isEmpty) return;
      // Interrupteur coupé : un effacement panel est ignoré. La liste
      // déjà chargée reste, exactement comme avant ce correctif.
      if (!kHonorRemoteListClear && explicitClear) return;

      final RemotePushedMemory mem = await RemotePushedMemory.load();
      final List<LocalSourceRef> local =
          kHonorRemoteListClear ? await _localRefs() : const <LocalSourceRef>[];
      final RemoteListSyncPlan plan = planRemoteListSync(
        honorClear: kHonorRemoteListClear,
        local: local,
        rememberedKeys: mem.remembered,
        blockedRestoreKeys: mem.blocked,
        body: body,
      );
      if (kHonorRemoteListClear) {
        for (final int id in plan.removeIds) {
          await PlaylistRepository.instance.deletePlaylist(id);
        }
      }
      if (_sameKeys(mem.remembered, plan.rememberKeys) &&
          _sameKeys(mem.blocked, plan.blockRestoreKeys)) {
        return;
      }
      await RemotePushedMemory.save(
        remembered: plan.rememberKeys,
        blocked: plan.blockRestoreKeys,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteSource] plan effacement: $e');
    }
  }

  static Future<List<LocalSourceRef>> _localRefs() async {
    final List<Playlist> local =
        await PlaylistRepository.instance.getAllPlaylists();
    final List<LocalSourceRef> refs = <LocalSourceRef>[];
    for (final Playlist p in local) {
      final int? id = p.id;
      if (id == null) continue;
      refs.add(
        LocalSourceRef(
          id: id,
          key: identityKeyForLocal(
            type: p.type.name,
            m3uUrl: p.m3uUrl,
            xtreamServer: p.xtreamServer,
            xtreamUsername: p.xtreamUsername,
          ),
        ),
      );
    }
    return refs;
  }

  static bool _sameKeys(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final String key in a) {
      if (!b.contains(key)) return false;
    }
    return true;
  }

  /// Charge la source en base locale si elle n'y est pas déjà.
  static Future<RemoteSyncResult> _applySource(Map<String, dynamic> src) async {
    final String type = (src['type'] as String?)?.trim().toLowerCase() ?? '';
    final String label = (src['label'] as String?)?.trim().isNotEmpty == true
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

      final bool already = existing
          .any((Playlist p) => p.type == PlaylistType.m3u && p.m3uUrl == m3u);
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
}
