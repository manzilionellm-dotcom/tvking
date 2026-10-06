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

import '../../../core/i18n/l10n_now.dart';
import '../../../core/update/build_flags.dart';
import '../../channels/data/recently_watched_repository.dart';
import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_backend.dart'
    show kSubscriptionBaseUrl;
import '../../subscription/data/subscription_state.dart';
import '../domain/panel_source_decision.dart';
import '../domain/playlist.dart';
import 'source_opt_outs.dart';
import 'source_link_utils.dart';
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
  /// CONFORMITÉ MAGASINS (refus Amazon du 19/08/2026, « pirated content ») :
  /// dans les builds DISTRIBUÉS PAR UN STORE (Google Play TV, Amazon
  /// Appstore — `PLAY_BUILD=true`), l'app était un LECTEUR « apporte ton
  /// abonnement » : AUCUNE source poussée par le panel.
  ///
  /// DÉCISION DU PROPRIÉTAIRE (20/09/2026), réaffirmée deux fois après
  /// avoir été prévenu du risque : « l'activation à distance doit être le
  /// cœur du code — même sur le Play Store ». La source poussée par le
  /// panel est donc chargée PARTOUT, build Play compris. Ce qui reste hors
  /// du build Play, et qui est la partie que Google sanctionne le plus
  /// sûrement : les offres, les prix, le bouton d'achat et le verrou de
  /// licence (voir mac_activation_view, subscription_state). Le risque
  /// résiduel — un examen qui verrait des chaînes arriver sans que
  /// l'utilisateur les ait ajoutées — est connu du propriétaire ; un
  /// réviseur avec une installation neuve ne reçoit rien, puisqu'aucun
  /// revendeur n'a assigné de source à SON numéro.
  ///
  /// Le champ reste (et reste testable) : remettre `kIsPlayBuild` ici
  /// suffit à revenir à la posture magasin stricte.
  @visibleForTesting
  static bool storeBuild = false;

  /// Signal « le revendeur vient d'ASSIGNER / METTRE À JOUR une source pour
  /// CET appareil » (poussé en TEMPS RÉEL par le panel via le WebSocket).
  /// L'accueil l'écoute pour charger la source IMMÉDIATEMENT — avec l'écran
  /// d'import VIVANT (chaînes qui s'ajoutent en direct) — sans attendre le
  /// prochain tick du sondage. Bumpé par RealtimeSyncService à la réception
  /// d'un événement `sync sources`/`all`.
  static final ValueNotifier<int> pushedTick = ValueNotifier<int>(0);

  /// Réveille les écouteurs (l'accueil) : « une source vient d'être poussée,
  /// charge-la tout de suite ». Best-effort, jamais bloquant.
  ///
  /// Un push est un geste DÉLIBÉRÉ du revendeur : il lève aussi les
  /// empreintes de suppression volontaire (SourceOptOuts) — c'est le
  /// parcours de RÉCUPÉRATION d'une source supprimée par accident
  /// (« contacte ton revendeur, il te la remet »).
  static void signalPushed() {
    // ignore: discarded_futures
    SourceOptOuts.clearAll();
    pushedTick.value++;
  }

  /// Récupère la source assignée à cet appareil et la charge si besoin.
  /// Best effort, idempotent (la dédup évite de réimporter à chaque boot).
  /// Renvoie un [RemoteSyncResult] pour permettre un diagnostic précis.
  static Future<RemoteSyncResult> sync({int hop = 0}) async {
    // Build store : pas de source poussée, pas d'ordres du panel (cf.
    // [storeBuild]). L'utilisateur ajoute ses sources lui-même.
    if (storeBuild) return RemoteSyncResult.noSource;
    try {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        m3uLinkAsM3u = prefs.getBool(m3uLinkAsM3uKey) ?? false;
        panelReconcileOff = prefs.getBool(panelReconcileOffKey) ?? false;
      } catch (_) {}
      final String mac = await DeviceIdentity.instance.mac;
      if (!mac.startsWith('MK:')) return RemoteSyncResult.noSource;

      final http.Response resp = await http
          .get(
            Uri.parse('$kSubscriptionBaseUrl/api/device-source/$mac'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return RemoteSyncResult.networkError;

      final Object? decoded = jsonDecode(resp.body);
      if (decoded is! Map) return RemoteSyncResult.networkError;
      final Map<String, dynamic> body = decoded is Map<String, dynamic>
          ? decoded
          : decoded.map(
              (Object? k, Object? v) => MapEntry<String, dynamic>('$k', v),
            );

      // AVANT le verrou : une MAC tombstonée renvoie blocked + le
      // nouveau numéro. Si on markBlocked d'abord, l'écran reste
      // verrouillé sur l'ANCIEN code.
      final String? reassigned = DeviceIdentity.newMacFromReassigned(
        body['mac_reassigned'],
      );
      if (reassigned != null && reassigned != mac && hop < 1) {
        final bool changed = await DeviceIdentity.instance.adopt(reassigned);
        if (changed) return sync(hop: hop + 1);
      }

      // VERROU SERVEUR : expired/frozen/banned/loaned → pas de playlist,
      // et on bascule l'état local tout de suite (sondage 60 s, plus
      // rapide que le heartbeat périodique).
      final Object? blocked = body['blocked'];
      if (blocked is String && blocked.isNotEmpty && blocked != 'mac_reassigned') {
        await SubscriptionState.instance.markBlockedFromSource(blocked);
        return RemoteSyncResult.noSource;
      }

      // Source LIVRÉE (pas de `blocked`) alors que l'écran est encore
      // verrouillé : le panel vient d'activer. Le sondage sources (60 s)
      // voyait déjà le bouquet mais ne refetchait PAS la licence →
      // tablette restée bloquée avec des chaînes « déjà en base ».
      // Heartbeat = autorité : s'il dit encore expiré, on reste verrouillé
      // (pas de trou freeloader).
      if (SubscriptionState.instance.shouldBlockUser) {
        unawaited(SubscriptionState.instance.syncWithBackend());
      }

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

      // Liste vidée AU PANEL : on retire seulement ce que le panel
      // avait posé (et les cibles d'ordres). Une liste ajoutée à la
      // main, qui n'est dans aucun des deux, reste.
      if (panelClearedSources(body)) {
        await _dropCleared(body['orders']);
        return RemoteSyncResult.noSource;
      }

      final Object? list = body['sources'];
      if (list is List && list.isNotEmpty) {
        final List<Map<String, dynamic>> all =
            list.whereType<Map<String, dynamic>>().toList();
        // ÉTEINTE au panel (`enabled: false`) : le téléphone n'a pas de
        // liste « masquée » ; une liste éteinte n'est donc pas chargée, et
        // retirée si elle l'était. Rallumée, elle revient (par l'API
        // Xtream : quelques secondes). 06/10/2026.
        final List<Map<String, dynamic>> active = panelReconcileOff
            ? all
            : all.where((Map<String, dynamic> s) => s['enabled'] != false).toList();
        // Même boucle que applySources (règle du labo comprise) : une seule
        // implémentation, pas deux comportements qui divergent.
        final RemoteSyncResult r = active.isEmpty
            ? RemoteSyncResult.noSource
            : await applySources(active);
        // RETIRÉE au panel (06/10/2026, « si on retire, on retire ») : avant,
        // seul « Effacer les listes » enlevait une liste du téléphone ;
        // retirer UNE liste parmi plusieurs la laissait là. On enlève ce que
        // le panel avait posé et ne sert plus (ou a éteint). Les listes
        // ajoutées à la main ne sont jamais dans `provisioned`.
        if (!panelReconcileOff) await _dropNoLongerServed(active);
        return r;
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
      if (id == null || id <= 0) continue;
      if (!orderLooksValid(o)) {
        done.add(id);
        continue;
      }
      try {
        final Playlist? target = _matchLocal(t);
        if (target != null && target.id != null) {
          if (kind == 'source_remove') {
            await PlaylistRepository.instance.deletePlaylist(target.id!);
            if (kDebugMode) debugPrint('[Orders] retiree: ' + target.name);
          } else if (kind == 'source_activate' && !target.isActive) {
            await PlaylistRepository.instance.setActivePlaylist(target.id!);
            if (kDebugMode) debugPrint('[Orders] active: ' + target.name);
          } else if (kind == 'source_update') {
            await _updateLocal(target, t['next']);
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

  /// Applique un ordre `source_update` : le revendeur a CORRIGE, depuis le
  /// panel, une liste que le CLIENT avait ajoutee lui-meme (mot de passe
  /// renouvele, serveur qui a bouge). Ces listes n'existent pas cote serveur,
  /// donc seul l'appareil peut les reecrire.
  ///
  /// Deux cas :
  ///  - memes serveur + identifiant, mot de passe different -> on ecrit le
  ///    nouveau mot de passe et on recharge (favoris/reglages conserves) ;
  ///  - serveur ou identifiant differents -> ce n'est plus la meme source :
  ///    on importe la nouvelle, on reprend le statut « active » de l'ancienne,
  ///    puis on retire l'ancienne. Jamais l'inverse : si l'import echoue, le
  ///    client garde ce qu'il avait.
  static Future<void> _updateLocal(Playlist target, Object? rawNext) async {
    if (rawNext is! Map<String, dynamic>) return;
    final String type = (rawNext['type'] as String?)?.trim().toLowerCase() ?? '';
    final String server = (rawNext['server_url'] as String?)?.trim() ?? '';
    final String user = (rawNext['username'] as String?)?.trim() ?? '';
    final String pass = (rawNext['password'] as String?)?.trim() ?? '';
    final String m3u = (rawNext['m3u_url'] as String?)?.trim() ?? '';
    final String? epg = (rawNext['epg_url'] as String?)?.trim();
    final String label = (rawNext['label'] as String?)?.trim().isNotEmpty == true
        ? (rawNext['label'] as String).trim()
        : target.name;

    final bool sameXtream = type == 'xtream' &&
        target.type == PlaylistType.xtream &&
        target.xtreamServer == server &&
        target.xtreamUsername == user;
    if (sameXtream) {
      if (pass.isEmpty || pass == target.xtreamPassword) return;
      await PlaylistRepository.instance.updateXtreamPassword(target.id!, pass);
      await PlaylistRepository.instance
          .refreshPlaylist(target.copyWith(xtreamPassword: pass));
      if (kDebugMode) debugPrint('[Orders] identifiants corriges: ' + target.name);
      return;
    }

    final bool wasActive = target.isActive;
    // Liste regardee AVANT le remplacement : si la source corrigee n'etait pas
    // l'active, l'import ne doit pas voler l'ecran au client.
    final Playlist? previouslyActive =
        wasActive ? null : await PlaylistRepository.instance.getActivePlaylist();
    if (type == 'xtream') {
      if (server.isEmpty || user.isEmpty || pass.isEmpty) return;
      await PlaylistRepository.instance.addXtreamPlaylist(
        name: label,
        serverUrl: server,
        username: user,
        password: pass,
        makeActive: wasActive,
      );
    } else if (type == 'm3u') {
      if (m3u.isEmpty) return;
      // `addM3uPlaylistSmart` (repli Xtream auto) n'expose pas `makeActive` :
      // on remet donc l'active d'avant si on n'aurait pas du en changer.
      await PlaylistRepository.instance.addM3uPlaylistSmart(
        name: label,
        url: m3u,
        epgUrl: (epg != null && epg.isNotEmpty) ? epg : null,
      );
      if (previouslyActive?.id != null &&
          previouslyActive!.id != target.id) {
        await PlaylistRepository.instance
            .setActivePlaylist(previouslyActive.id!);
      }
    } else {
      return;
    }
    // L'import a reussi (sinon on aurait leve) -> l'ancienne peut partir.
    await PlaylistRepository.instance.deletePlaylist(target.id!);
    if (kDebugMode) debugPrint('[Orders] remplacee: ' + target.name);
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
    // Build store : rien d'assigné, jamais (cf. [storeBuild]).
    if (storeBuild) return <Map<String, dynamic>>[];
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
      final String? reassigned = DeviceIdentity.newMacFromReassigned(
        body['mac_reassigned'],
      );
      if (reassigned != null && reassigned != mac) {
        await DeviceIdentity.instance.adopt(reassigned);
      }
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
    // Build store : même les événements temps réel du panel (pushedTick →
    // fetch + apply) ne chargent rien (cf. [storeBuild]).
    if (storeBuild) return RemoteSyncResult.noSource;
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

  /// Depuis quand le panel assigne-t-il cette source ? (`assigned_at`, ms).
  ///
  ///  0 = le serveur ne le dit pas (Worker plus ancien que le 17/09). Le
  ///  juge des empreintes ne bloque alors pas : on préfère une source de
  ///  trop à un client payant devant un écran vide.
  static int _assignationMs(Map<String, dynamic> src) {
    final Object? v = src['assigned_at'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
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

      // SUPPRIMÉE VOLONTAIREMENT par le client (SourceOptOuts) : la
      // provision automatique ne la ressuscite PAS au boot. Un push
      // temps réel du panel lève les empreintes (signalPushed).
      // SUPPRIMÉE PAR LE CLIENT — mais QUAND, par rapport à la dernière
      // poussée du panel ? Sans cette date, ce filtre a rendu toute
      // activation à distance impossible (17/09, voir source_opt_outs.dart).
      if (await SourceOptOuts.isXtreamOptedOut(server, user,
          assignedAt: _assignationMs(src))) {
        if (kDebugMode) debugPrint('[RemoteSource] opt-out, sautée ($server)');
        return RemoteSyncResult.noSource;
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
        await _rememberProvision(ProvisionKey.xtream(server, user));
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
        await _rememberProvision(ProvisionKey.xtream(server, user));
        return RemoteSyncResult.loaded;
      } catch (e) {
        // Identifiants/serveur invalides, 0 chaîne… → le repo a rejeté.
        if (kDebugMode) debugPrint('[RemoteSource] Xtream KO: $e');
        return RemoteSyncResult.sourceFailed;
      }
    } else if (type == 'm3u') {
      final String m3u = (src['m3u_url'] as String?)?.trim() ?? '';
      if (m3u.isEmpty) return RemoteSyncResult.sourceFailed;

      // Même règle que le chemin Xtream : suppression volontaire respectée.
      // Même règle que le chemin Xtream (voir plus haut).
      if (await SourceOptOuts.isM3uOptedOut(m3u,
          assignedAt: _assignationMs(src))) {
        if (kDebugMode) debugPrint('[RemoteSource] opt-out, sautée (m3u)');
        return RemoteSyncResult.noSource;
      }

      // LIEN get.php ENVOYÉ PAR LE PANEL (06/10/2026) : lu par l'API Xtream
      // du même serveur, comme sur la box. Mesuré sur le fournisseur du
      // propriétaire : fichier M3U > 200 Mo (744 000 entrées, 49 s avant
      // le premier octet) contre 28 490 chaînes TV en 8 Mo et 1 s par
      // l'API. Le téléphone restait sur « Pas encore de chaînes ». Si
      // l'API refuse, repli sur le fichier M3U (ci-dessous).
      final ({String server, String username, String password})? creds =
          m3uLinkAsM3u ? null : SourceLinkUtils.tryExtractXtreamCredentials(m3u);
      if (creds != null) {
        final RemoteSyncResult? viaApi = await _applyGetPhpAsXtream(
          src: src,
          m3u: m3u,
          creds: creds,
          label: label,
          existing: existing,
          onProgress: onProgress,
          makeActive: makeActive,
        );
        if (viaApi != null) return viaApi;
      }

      Playlist? existingM3u;
      for (final Playlist p in existing) {
        if (p.type == PlaylistType.m3u && p.m3uUrl == m3u) {
          existingM3u = p;
          break;
        }
      }
      if (existingM3u != null) {
        await _activateIfAsked(existingM3u, makeActive);
        await _rememberProvision(ProvisionKey.m3u(m3u));
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
        await _rememberProvision(ProvisionKey.m3u(m3u));
        return RemoteSyncResult.loaded;
      } catch (e) {
        // URL M3U incomplète / provider injoignable / 0 chaîne.
        if (kDebugMode) debugPrint('[RemoteSource] M3U KO: $e');
        return RemoteSyncResult.sourceFailed;
      }
    }
    return RemoteSyncResult.noSource;
  }

  /// Repli : vrai = un lien get.php du panel est téléchargé comme fichier
  /// M3U complet (ancien comportement). Préférence
  /// `zuno.mobile.getphp_as_m3u`, lue à chaque relecture.
  static bool m3uLinkAsM3u = false;
  static const String m3uLinkAsM3uKey = 'zuno.mobile.getphp_as_m3u';

  /// Repli : vrai = ancien comportement, une liste retirée ou éteinte au
  /// panel RESTE sur le téléphone (seul « Effacer les listes » agit).
  /// Préférence `zuno.mobile.panel_reconcile_off`.
  static bool panelReconcileOff = false;
  static const String panelReconcileOffKey = 'zuno.mobile.panel_reconcile_off';

  /// Tests seulement : client HTTP donné au compte Xtream tiré d'un lien
  /// get.php (en production `null` = le client IPTV habituel).
  @visibleForTesting
  static http.Client Function()? xtreamHttpForTest;

  /// Lien get.php → compte Xtream. `null` = l'API a refusé : l'appelant
  /// retombe sur le fichier M3U. Les DEUX empreintes (lien et compte) sont
  /// retenues : « Effacer » ou « Retirer » au panel (qui parle du lien)
  /// retrouvent la liste Xtream.
  static Future<RemoteSyncResult?> _applyGetPhpAsXtream({
    required Map<String, dynamic> src,
    required String m3u,
    required ({String server, String username, String password}) creds,
    required String label,
    required List<Playlist> existing,
    required ImportProgressCallback? onProgress,
    required bool makeActive,
  }) async {
    // Supprimée par le client sous sa forme Xtream : on respecte.
    if (await SourceOptOuts.isXtreamOptedOut(creds.server, creds.username,
        assignedAt: _assignationMs(src))) {
      return RemoteSyncResult.noSource;
    }
    for (final Playlist p in existing) {
      if (p.type == PlaylistType.xtream &&
          p.xtreamServer == creds.server &&
          p.xtreamUsername == creds.username) {
        await _activateIfAsked(p, makeActive);
        await _rememberProvision(ProvisionKey.m3u(m3u));
        await _rememberProvision(ProvisionKey.xtream(creds.server, creds.username));
        return RemoteSyncResult.loaded;
      }
    }
    try {
      await PlaylistRepository.instance.addXtreamPlaylist(
        name: label,
        serverUrl: creds.server,
        username: creds.username,
        password: creds.password,
        onProgress: onProgress,
        makeActive: makeActive,
        httpClient: xtreamHttpForTest?.call(),
      );
      final bool wasPanelM3u = (await _loadProvisioned()).contains(ProvisionKey.m3u(m3u));
      await _rememberProvision(ProvisionKey.m3u(m3u));
      await _rememberProvision(ProvisionKey.xtream(creds.server, creds.username));
      // L'ancienne copie « fichier M3U » de CE lien, posée par le panel
      // avant cette version, ferait doublon (même abonnement deux fois) :
      // on la retire, la liste Xtream la remplace.
      if (wasPanelM3u) {
        for (final Playlist p in existing) {
          if (p.id != null && p.type == PlaylistType.m3u && p.m3uUrl == m3u) {
            await PlaylistRepository.instance.deletePlaylist(p.id!);
          }
        }
      }
      return RemoteSyncResult.loaded;
    } catch (e) {
      if (kDebugMode) debugPrint('[RemoteSource] get.php par API refusé, repli M3U : $e');
      return null;
    }
  }

  /// Empreintes d'une liste servie par le panel. Un lien get.php vaut
  /// aussi pour le compte Xtream qu'on en a tiré.
  @visibleForTesting
  static Set<ProvisionKey> keysOfServed(List<Map<String, dynamic>> served) {
    final Set<ProvisionKey> out = <ProvisionKey>{};
    for (final Map<String, dynamic> s in served) {
      final String type = '${s['type'] ?? ''}'.trim().toLowerCase();
      if (type == 'xtream') {
        final String server = '${s['server_url'] ?? ''}'.trim();
        final String user = '${s['username'] ?? ''}'.trim();
        if (server.isNotEmpty) out.add(ProvisionKey.xtream(server, user));
      } else if (type == 'm3u') {
        final String m3u = '${s['m3u_url'] ?? ''}'.trim();
        if (m3u.isEmpty) continue;
        out.add(ProvisionKey.m3u(m3u));
        final ({String server, String username, String password})? c =
            SourceLinkUtils.tryExtractXtreamCredentials(m3u);
        if (c != null) out.add(ProvisionKey.xtream(c.server, c.username));
      }
    }
    return out;
  }

  /// Enlève du téléphone les listes que le panel avait posées et qu'il ne
  /// sert plus (retirées ou éteintes). Rien d'autre.
  static Future<void> _dropNoLongerServed(List<Map<String, dynamic>> active) async {
    final Set<ProvisionKey> provisioned = await _loadProvisioned();
    final Set<ProvisionKey> served = keysOfServed(active);
    final Set<ProvisionKey> drop = provisioned.difference(served);
    if (drop.isEmpty) return;
    final List<Playlist> local =
        await PlaylistRepository.instance.getAllPlaylists();
    for (final Playlist p in local) {
      if (p.id == null) continue;
      if (!drop.any((ProvisionKey k) => _playlistIs(p, k))) continue;
      // Une liste encore servie sous une AUTRE empreinte (lien get.php
      // devenu compte Xtream) reste.
      if (served.any((ProvisionKey k) => _playlistIs(p, k))) continue;
      await PlaylistRepository.instance.deletePlaylist(p.id!);
    }
    await _forgetProvision(drop);
  }

  static const String _kProvisioned = 'panel.provisioned_v1';

  static Future<Set<ProvisionKey>> _loadProvisioned() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList(_kProvisioned) ?? <String>[];
    return raw.map(ProvisionKey.parse).whereType<ProvisionKey>().toSet();
  }

  static Future<void> _rememberProvision(ProvisionKey key) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList(_kProvisioned) ?? <String>[];
    if (raw.contains(key.wire)) return;
    raw.add(key.wire);
    await prefs.setStringList(_kProvisioned, raw);
  }

  static Future<void> _forgetProvision(Set<ProvisionKey> keys) async {
    if (keys.isEmpty) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList(_kProvisioned) ?? <String>[];
    final Set<String> drop = keys.map((ProvisionKey k) => k.wire).toSet();
    raw.removeWhere(drop.contains);
    await prefs.setStringList(_kProvisioned, raw);
  }

  /// Effacement explicite : retire les listes que le panel avait posées.
  static Future<void> _dropCleared(Object? rawOrders) async {
    final List<Map<String, dynamic>> orders = <Map<String, dynamic>>[];
    if (rawOrders is List) {
      for (final Object? o in rawOrders) {
        if (o is Map<String, dynamic>) orders.add(o);
      }
    }
    final Set<ProvisionKey> provisioned = await _loadProvisioned();
    final Set<ProvisionKey> drop = keysToRemove(
      explicitClear: true,
      provisioned: provisioned,
      orders: orders,
    );
    if (drop.isEmpty) return;
    final List<Playlist> local =
        await PlaylistRepository.instance.getAllPlaylists();
    for (final Playlist p in local) {
      if (p.id == null) continue;
      final bool hit = drop.any((ProvisionKey k) => _playlistIs(p, k));
      if (!hit) continue;
      await PlaylistRepository.instance.deletePlaylist(p.id!);
    }
    await _forgetProvision(drop);
  }

  static bool _playlistIs(Playlist p, ProvisionKey key) {
    if (key.kind == 'm3u') {
      return p.type == PlaylistType.m3u && (p.m3uUrl ?? '') == key.m3uUrl;
    }
    return p.type == PlaylistType.xtream &&
        (p.xtreamServer ?? '') == key.server &&
        (p.xtreamUsername ?? '') == key.username;
  }
}
