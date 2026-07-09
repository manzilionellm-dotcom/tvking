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

import '../../channels/data/recently_watched_repository.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../../../core/net/iptv_exit.dart';
import '../domain/playlist.dart';
import 'playlist_repository.dart';
import 'source_link_utils.dart';

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
  /// Récupère la source assignée à cet appareil et la charge si besoin.
  /// Best effort, idempotent (la dédup évite de réimporter à chaque boot).
  /// Renvoie un [RemoteSyncResult] pour permettre un diagnostic précis.
  /// Récupère la SORTIE RÉSEAU (proxy/IP) assignée à cet appareil par le
  /// panel et l'applique globalement (IptvExit). Le fournisseur IPTV verra
  /// alors toujours la même IP, où que voyage le client. Best-effort : en
  /// cas d'échec on garde la sortie actuelle (jamais de coupure).
  static Future<void> syncExit() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) return;
      final http.Response resp = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/device-net/$mac'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final Map<String, dynamic> body =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final String proxy = (body['proxy'] as String?)?.trim() ?? '';
      final String label = (body['label'] as String?)?.trim() ?? '';
      IptvExit.instance.update(proxy: proxy, label: label);
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteSource] exit sync error: $e');
    }
  }

  static Future<RemoteSyncResult> sync() async {
    try {
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) return RemoteSyncResult.noSource;

      // Sortie réseau (IP) AVANT tout appel IPTV : si l'admin a changé l'IP
      // du client, les requêtes qui suivent partent déjà par la bonne sortie.
      await syncExit();

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

      // Un lien « M3U » poussé par le panel est TRÈS souvent un compte
      // Xtream déguisé (get.php?username=…&password=…) : le lien VLC du
      // fournisseur. On le reconnaît AVANT la dédup pour :
      //  1. dédupliquer aussi contre la playlist XTREAM équivalente —
      //     sinon, une fois convertie, elle serait ré-importée à CHAQUE
      //     synchro (l'URL m3u ne matcherait plus rien) ;
      //  2. charger via l'API Xtream (streamée, rapide, structurée) au
      //     lieu de télécharger le fichier M3U géant — c'est ce qui
      //     rendait l'ajout poussé « pas fluide » sur la TV.
      final ({String server, String username, String password})? creds =
          SourceLinkUtils.tryExtractXtreamCredentials(m3u);
      final bool already = existing.any((Playlist p) =>
          (p.type == PlaylistType.m3u && p.m3uUrl == m3u) ||
          (creds != null &&
              p.type == PlaylistType.xtream &&
              p.xtreamServer == creds.server &&
              p.xtreamUsername == creds.username));
      if (already) return RemoteSyncResult.loaded;

      try {
        // Smart : API Xtream d'abord si le lien porte des identifiants,
        // repli automatique sur le M3U brut sinon/en cas d'échec.
        await PlaylistRepository.instance.addM3uPlaylistSmart(
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
