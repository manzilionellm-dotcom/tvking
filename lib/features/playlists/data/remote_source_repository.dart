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

  /// Récupère la source assignée à cet appareil et la charge si besoin.
  /// Best effort, idempotent (la dédup évite de réimporter à chaque boot).
  /// Renvoie un [RemoteSyncResult] pour permettre un diagnostic précis.
  static Future<RemoteSyncResult> sync() async {
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
      //
      // ORDRES DU PANEL sur les listes LOCALES du client (celles qu'il a
      // ajoutées lui-même : absentes de la base serveur, donc seul
      // l'appareil peut les toucher). File durable → un ordre déposé
      // pendant que la box était éteinte s'applique ici, à son réveil.
      await _applyOrders(mac, body['orders']);

      final Object? list = body['sources'];
      if (list is List && list.isNotEmpty) {
        // Même boucle que applySources (règle du labo comprise) : une seule
        // implémentation, pas deux comportements qui divergent.
        return applySources(list.whereType<Map<String, dynamic>>().toList());
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

  /// Applique les ORDRES déposés par le panel sur les listes locales du
  /// client : retirer une liste, ou en faire l'active. La cible est
  /// décrite par serveur+identifiant (et non par index : l'ordre des
  /// listes n'est pas le même d'un appareil à l'autre).
  ///
  /// Best-effort de bout en bout : un ordre dont la cible n'existe plus est
  /// quand même ACQUITTÉ — sinon il resterait en file pour l'éternité et se
  /// rejouerait à chaque synchro.
  static Future<void> _applyOrders(String mac, Object? raw) async {
    if (raw is! List || raw.isEmpty) return;
    final List<int> done = <int>[];
    for (final Object? o in raw) {
      if (o is! Map<String, dynamic>) continue;
      final Object? rawId = o['id'];
      final int? id = rawId is int ? rawId : null;
      final String kind = (o['kind'] as String?) ?? '';
      final Map<String, dynamic> t =
          (o['target'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      if (id == null) continue;
      try {
        final Playlist? target = _matchLocal(t);
        if (target != null && target.id != null) {
          if (kind == 'source_remove') {
            await PlaylistRepository.instance.deletePlaylist(target.id!);
            if (kDebugMode) debugPrint('[Orders] retiree: ' + target.name);
          } else if (kind == 'source_activate' && !target.isActive) {
            await PlaylistRepository.instance.setActivePlaylist(target.id!);
            if (kDebugMode) debugPrint('[Orders] active: ' + target.name);
          }
        }
        done.add(id); // cible absente = ordre sans objet -> acquitte quand meme
      } catch (e) {
        if (kDebugMode) debugPrint('[Orders] echec ordre: $e');
      }
    }
    if (done.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('$kSubscriptionBaseUrl/api/device-orders/ack'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object>{'mac': mac, 'ids': done}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Pas d'accuse -> l'ordre reviendra a la prochaine synchro. Les deux
      // actions sont IDEMPOTENTES (supprimer une liste absente, activer une
      // liste deja active) : le rejouer est sans danger.
    }
  }

  /// Retrouve la playlist locale visee par un ordre.
  static Playlist? _matchLocal(Map<String, dynamic> t) {
    final String server = (t['server'] as String?)?.trim() ?? '';
    final String user = (t['username'] as String?)?.trim() ?? '';
    final String m3u = (t['m3u_url'] as String?)?.trim() ?? '';
    for (final Playlist p in PlaylistRepository.instance.currentPlaylists) {
      if (m3u.isNotEmpty && p.type == PlaylistType.m3u && p.m3uUrl == m3u) {
        return p;
      }
      if (server.isNotEmpty &&
          p.type == PlaylistType.xtream &&
          p.xtreamServer == server &&
          (user.isEmpty || p.xtreamUsername == user)) {
        return p;
      }
    }
    return null;
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
      final RemoteSyncResult r = await _applySource(
        item,
        onProgress: onProgress,
        makeActive: shouldActivate(item, sources),
      );
      if (r == RemoteSyncResult.loaded) {
        agg = RemoteSyncResult.loaded;
      } else if (agg != RemoteSyncResult.loaded &&
          r == RemoteSyncResult.sourceFailed) {
        agg = RemoteSyncResult.sourceFailed;
      }
    }
    return agg;
  }

  /// LABO DU MAÎTRE — une source de test a-t-elle le droit de devenir la
  /// playlist ACTIVE (celle que l'accueil affiche) ?
  ///
  /// Chaque import réussi appelle `setActivePlaylist`, donc la DERNIÈRE
  /// source chargée gagne. Or le worker ajoute les sources labo EN FIN de
  /// tableau : sans cette règle, une box maître qui a un vrai abonnement
  /// bascule sur le serveur de test dès qu'on ajoute une source au labo —
  /// `getAllChannels` ne renvoyant que les chaînes de la playlist active,
  /// l'app paraît cassée.
  ///
  /// Règle : une source `origin: 'lab'` n'est activée QUE si elle est seule
  /// (box maître sans abonnement — coller un M3U au labo doit suffire à
  /// l'alimenter). Toute autre source garde le comportement historique.
  ///
  /// Fonction PURE (ni base ni réseau) pour rester testable.
  @visibleForTesting
  static bool shouldActivate(
    Map<String, dynamic> source,
    List<Map<String, dynamic>> all,
  ) {
    // CHOIX EXPLICITE DU PANEL (`active: true`) : il PRIME sur tout le
    // reste. Sans ça, le revendeur n'avait aucun moyen de dire QUELLE
    // liste le client doit regarder — et le client, lui, ne sait pas la
    // changer dans l'app. Dès qu'UNE source porte le drapeau, elle seule
    // est activée ; les autres sont importées sans prendre la main.
    final bool anyExplicit = all.any((Map<String, dynamic> s) => s['active'] == true);
    if (anyExplicit) return source['active'] == true;

    final bool isLab = (source['origin'] as String?) == 'lab';
    if (!isLab) return true;
    final bool hasRealSource = all.any(
        (Map<String, dynamic> s) => (s['origin'] as String?) != 'lab');
    return !hasRealSource;
  }

  /// Bascule sur [p] si le panel l'a désignée active et qu'elle ne l'est
  /// pas déjà. Utilisé quand la source est DÉJÀ importée : on ne
  /// re-télécharge rien, on change seulement la liste active.
  static Future<void> _activateIfAsked(Playlist p, bool makeActive) async {
    if (!makeActive || p.isActive || p.id == null) return;
    await PlaylistRepository.instance.setActivePlaylist(p.id!);
    if (kDebugMode) debugPrint('[RemoteSource] active -> ' + p.name);
  }

  /// Charge la source en base locale si elle n'y est pas déjà.
  static Future<RemoteSyncResult> _applySource(
    Map<String, dynamic> src, {
    ImportProgressCallback? onProgress,
    // `false` = importer SANS basculer l'accueil dessus (source labo qui
    // cohabite avec l'abonnement réel de la box).
    bool makeActive = true,
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

      // DÉJÀ IMPORTÉE : on ne re-télécharge pas… mais si le panel a désigné
      // CETTE source comme active, il faut quand même basculer dessus.
      // Avant, on sortait sèchement : le revendeur cliquait « rendre
      // active » et il ne se passait RIEN chez un client qui avait déjà la
      // liste — le cas le plus fréquent.
      Playlist? existingXtream;
      for (final Playlist p in existing) {
        if (p.type == PlaylistType.xtream &&
            p.xtreamServer == server &&
            p.xtreamUsername == user) {
          existingXtream = p;
          break;
        }
      }
      if (existingXtream != null) {
        // MOT DE PASSE CHANGÉ côté panel (même serveur, même login) : la
        // liste est « déjà là », mais avec des identifiants morts. On écrit
        // les nouveaux et on recharge le catalogue — sinon le client voit
        // ses chaînes tomber et ne peut rien y faire depuis sa TV.
        if (existingXtream.id != null && existingXtream.xtreamPassword != pass) {
          try {
            await PlaylistRepository.instance
                .updateXtreamPassword(existingXtream.id!, pass);
            final Playlist updated = existingXtream.copyWith(xtreamPassword: pass);
            await PlaylistRepository.instance.refreshPlaylist(updated);
            if (kDebugMode) {
              debugPrint('[RemoteSource] identifiants mis a jour ($server)');
            }
          } catch (e) {
            if (kDebugMode) debugPrint('[RemoteSource] maj identifiants KO: $e');
          }
        }
        await _activateIfAsked(existingXtream, makeActive);
        return RemoteSyncResult.loaded;
      }

      try {
        await PlaylistRepository.instance.addXtreamPlaylist(
          name: label,
          serverUrl: server,
          username: user,
          password: pass,
          onProgress: onProgress,
          makeActive: makeActive,
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

      Playlist? existingM3u;
      for (final Playlist p in existing) {
        if (p.type == PlaylistType.m3u && p.m3uUrl == m3u) {
          existingM3u = p;
          break;
        }
      }
      if (existingM3u != null) {
        await _activateIfAsked(existingM3u, makeActive);
        return RemoteSyncResult.loaded;
      }

      try {
        await PlaylistRepository.instance.addM3uPlaylist(
          name: label,
          url: m3u,
          epgUrl: (epg != null && epg.isNotEmpty) ? epg : null,
          onProgress: onProgress,
          makeActive: makeActive,
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
