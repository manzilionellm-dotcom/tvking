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

import '../../../core/i18n/l10n_now.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../domain/playlist.dart';
import 'import_progress.dart';
import 'playlist_repository.dart';

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
  /// Signal « le revendeur vient d'ASSIGNER / METTRE À JOUR une source pour
  /// CET appareil » (poussé en TEMPS RÉEL par le panel via le WebSocket).
  /// L'accueil l'écoute pour charger la source IMMÉDIATEMENT — avec l'écran
  /// d'import VIVANT (chaînes qui s'ajoutent en direct) — sans attendre le
  /// prochain tick du sondage. Bumpé par RealtimeSyncService à la réception
  /// d'un événement `sync sources`/`all`.
  static final ValueNotifier<int> pushedTick = ValueNotifier<int>(0);

  /// Réveille les écouteurs (l'accueil) : « une source vient d'être poussée,
  /// charge-la tout de suite ». Best-effort, jamais bloquant.
  static void signalPushed() => pushedTick.value++;

  /// Synchro en cours (dédup in-flight). `sync()` est appelé par PLUSIEURS
  /// boucles concurrentes (timer 5 min, sondage d'activation, WebSocket,
  /// boot) : sans ce verrou, deux appels simultanés pouvaient importer la
  /// MÊME source deux fois (check-then-act non atomique dans `_applySource`)
  /// et doubler le pic mémoire de l'import. Tant qu'une passe tourne, tout
  /// nouvel appel reçoit le MÊME Future.
  static Future<RemoteSyncResult>? _inFlight;

  /// Seam de test : remplace le corps réel (`_doSync`, qui touche le réseau)
  /// pour vérifier la dédup in-flight sans aucune E/S. `null` en production.
  @visibleForTesting
  static Future<RemoteSyncResult> Function()? debugSyncBody;

  /// Récupère la source assignée à cet appareil et la charge si besoin.
  /// Best effort, idempotent (la dédup évite de réimporter à chaque boot).
  /// Renvoie un [RemoteSyncResult] pour permettre un diagnostic précis.
  static Future<RemoteSyncResult> sync() =>
      _inFlight ??= (debugSyncBody ?? _doSync)()
          .whenComplete(() => _inFlight = null);

  /// Corps réel de [sync] — ne pas appeler directement (pas de dédup).
  static Future<RemoteSyncResult> _doSync() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) return RemoteSyncResult.noSource;

      final http.Response resp = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/device-source/$mac'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return RemoteSyncResult.networkError;

      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;

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
        return RemoteSyncResult.noSource; // null = rien d'assigné
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

  /// Récupère la LISTE des sources assignées à cette MAC (sans les charger).
  /// Sert à l'UI d'activation : si une source est en attente, on peut alors
  /// afficher l'écran de progression VIVANT (chaînes qui s'ajoutent) au lieu
  /// d'un simple message. `[]` = rien d'assigné / réseau KO (best-effort).
  static Future<List<Map<String, dynamic>>> fetchAssignedSources() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) return <Map<String, dynamic>>[];
      final http.Response resp = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/device-source/$mac'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return <Map<String, dynamic>>[];
      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final Object? list = body['sources'];
      if (list is List && list.isNotEmpty) {
        return list.whereType<Map<String, dynamic>>().toList();
      }
      final Object? src = body['source'];
      if (src is Map<String, dynamic>) return <Map<String, dynamic>>[src];
      return <Map<String, dynamic>>[];
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteSource] fetch error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// Charge une liste de sources déjà récupérée, en émettant la progression
  /// (phase, catégorie en cours, compteur de chaînes) via [onProgress] pour
  /// alimenter l'écran d'import vivant.
  static Future<RemoteSyncResult> applySources(
    List<Map<String, dynamic>> sources, {
    ImportProgressCallback? onProgress,
  }) async {
    RemoteSyncResult agg = RemoteSyncResult.noSource;
    for (final Map<String, dynamic> item in sources) {
      final RemoteSyncResult r =
          await _applySource(item, onProgress: onProgress);
      if (r == RemoteSyncResult.loaded) {
        agg = RemoteSyncResult.loaded;
      } else if (agg != RemoteSyncResult.loaded &&
          r == RemoteSyncResult.sourceFailed) {
        agg = RemoteSyncResult.sourceFailed;
      }
    }
    return agg;
  }

  /// Charge la source en base locale si elle n'y est pas déjà.
  static Future<RemoteSyncResult> _applySource(
    Map<String, dynamic> src, {
    ImportProgressCallback? onProgress,
  }) async {
    final String type = (src['type'] as String?)?.trim().toLowerCase() ?? '';
    // Nom par défaut LOCALISÉ (langue active au moment de la synchro) :
    // ce libellé est ensuite STOCKÉ comme nom de la playlist — comme tout
    // nom de playlist, il est figé à la création (champ libre, pas
    // re-localisable à l'affichage).
    final String label =
        (src['label'] as String?)?.trim().isNotEmpty == true
            ? (src['label'] as String).trim()
            : l10nNow.playlistDefaultSubscription;
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
          onProgress: onProgress,
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
          onProgress: onProgress,
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
