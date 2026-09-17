// =========================================================
//  source_opt_outs.dart — Suppressions VOLONTAIRES de sources
// =========================================================
//  Retour client (21/08) : « si je supprime l'abonnement, ça doit être
//  supprimé carrément — au redémarrage il est toujours là, c'est pas
//  professionnel. » La cause : la PROVISION AUTOMATIQUE par MAC
//  (RemoteSourceRepository.sync) re-importait au boot la source que le
//  client venait de supprimer localement.
//
//  Ici : on mémorise l'« empreinte » de chaque source supprimée PAR UN
//  GESTE VOLONTAIRE (écran Sources TV/téléphone, ou ordre du panel).
//  La provision automatique la SAUTE tant que l'empreinte est posée.
//
//  =========================================================
//   17/09/2026 — CE FICHIER A RENDU UNE ACTIVATION IMPOSSIBLE
//  =========================================================
//  Le propriétaire, deux jours durant :
//
//    « Si j'écris bonjour, l'application reçoit bonjour. Mais si
//      j'active à distance, l'application ne peut pas s'activer. Et si
//      le client le met manuellement, ça fonctionne. »
//
//  Ces trois faits, mis ensemble, désignaient un seul coupable. Le
//  transport allait bien (le message arrive). Les identifiants allaient
//  bien (la saisie manuelle marche). Restait un filtre, entre les deux,
//  qui ne s'applique QU'À la source poussée : celui-ci.
//
//  Les messages arrivent par `/api/device-messages/:mac`, sans filtre.
//  La source arrive par `/api/device-source/:mac`, et
//  `RemoteSourceRepository._applySource` la SAUTAIT en silence dès
//  qu'une empreinte traînait. Le revendeur poussait dans le vide, le
//  panel affichait « envoyé », et personne — ni lui, ni le client, ni
//  le panneau — ne pouvait voir pourquoi.
//
//  CE QUI ÉTAIT CENSÉ LEVER L'EMPREINTE ne pouvait presque jamais
//  s'exécuter : `signalPushed()` n'est appelé que par un événement
//  WEBSOCKET. Socket coupé, app en arrière-plan, réveil par le sondage
//  de 6 secondes — tous ces chemins arrivaient directement au filtre,
//  empreinte intacte. Le parcours de récupération existait sur le
//  papier ; dans la vraie vie il ne se déclenchait pas.
//
//  LA CORRECTION : une empreinte porte désormais une DATE, et le
//  serveur dit depuis quand la source est assignée (`assigned_at`,
//  c'est-à-dire `device_sources.updated_at`, qui était déjà écrit à
//  chaque poussée du panel — rien à migrer). Les deux besoins cessent
//  alors de se contredire :
//
//    • supprimée APRÈS la dernière assignation → elle reste supprimée.
//      C'est le 21/08, intact.
//    • assignée APRÈS la suppression → le revendeur a reparlé depuis,
//      la source revient. C'est aujourd'hui.
//
//  Plus besoin du WebSocket pour ça : la comparaison se fait sur le
//  chemin normal, celui qui marche déjà puisque les messages passent.
//
//  DANS LE DOUTE, ON NE BLOQUE PAS. Serveur sans date, préférences
//  illisibles, empreinte sans date : on laisse passer. Les deux erreurs
//  ne coûtent pas pareil — une source qui revient une fois de trop est
//  agaçante et visible ; un client payant devant un écran vide coûte un
//  abonnement et un appel.
// =========================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/playlist.dart';

abstract final class SourceOptOuts {
  /// v1 : simple liste d'empreintes, SANS date. Encore lue une fois pour
  /// la migration (voir [_migrerV1]), puis effacée.
  static const String _kKeyV1 = 'remote.source.optout.v1';

  /// v2 : `empreinte|dateMs`. La date est ce qui permet de départager
  /// « supprimée puis réassignée » de « supprimée, point ».
  static const String _kKey = 'remote.source.optout.v2';

  static String _fpXtream(String server, String user) =>
      'x|${server.trim()}|${user.trim()}';
  static String _fpM3u(String url) => 'm|${url.trim()}';

  /// Empreinte d'une playlist locale (null = type inconnu, rien à poser).
  static String? _fpOf(Playlist p) {
    if (p.type == PlaylistType.xtream) {
      return _fpXtream(p.xtreamServer ?? '', p.xtreamUsername ?? '');
    }
    if (p.type == PlaylistType.m3u) return _fpM3u(p.m3uUrl ?? '');
    return null;
  }

  /// Pose l'empreinte d'une source supprimée VOLONTAIREMENT, datée.
  static Future<void> markDeleted(Playlist p) async {
    final String? fp = _fpOf(p);
    if (fp == null) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, int> all = await _lire(prefs);
      all[fp] = DateTime.now().millisecondsSinceEpoch;
      await _ecrire(prefs, all);
      if (kDebugMode) debugPrint('[OptOut] posé : $fp');
    } catch (_) {
      // best-effort — au pire la source revient une fois de plus.
    }
  }

  /// La provision automatique doit-elle SAUTER cette source Xtream ?
  ///
  ///  [assignedAt] = `assigned_at` renvoyé par le serveur (ms). `null` ou
  ///  0 = le serveur ne le dit pas (vieux Worker) → on NE BLOQUE PAS.
  static Future<bool> isXtreamOptedOut(
    String server,
    String user, {
    int? assignedAt,
  }) =>
      _doitSauter(_fpXtream(server, user), assignedAt);

  /// La provision automatique doit-elle SAUTER cette source M3U ?
  static Future<bool> isM3uOptedOut(String url, {int? assignedAt}) =>
      _doitSauter(_fpM3u(url), assignedAt);

  /// LE JUGE. Fonction pure, sortie exprès du stockage pour être testable.
  ///
  ///  [suppressionMs] : quand le client l'a supprimée (0 / null = inconnu).
  ///  [assignationMs] : depuis quand le panel l'assigne (0 / null = inconnu).
  @visibleForTesting
  static bool doitSauter({int? suppressionMs, int? assignationMs}) {
    final int supp = suppressionMs ?? 0;
    // Jamais supprimée → rien à sauter.
    if (supp <= 0) return false;
    final int assign = assignationMs ?? 0;
    // Le serveur ne dit pas depuis quand il l'assigne (vieux Worker, ou
    // empreinte migrée). On ne peut pas trancher — donc on ne bloque pas :
    // priver un client payant coûte plus cher qu'une source de trop.
    if (assign <= 0) return false;
    // Réassignée APRÈS la suppression → le revendeur a reparlé depuis.
    // Strictement supérieur : à égalité de milliseconde, la suppression
    // gagne (elle est forcément postérieure à l'assignation qu'elle vise).
    return supp >= assign;
  }

  static Future<bool> _doitSauter(String fp, int? assignedAt) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, int> all = await _lire(prefs);
      return doitSauter(suppressionMs: all[fp], assignationMs: assignedAt);
    } catch (_) {
      return false; // en cas de doute : ne jamais bloquer une provision
    }
  }

  /// Lève TOUTES les empreintes — appelé quand le panel POUSSE une source
  /// en temps réel (geste délibéré du revendeur = récupération).
  ///
  ///  Reste utile, mais n'est PLUS le seul filet : le chemin normal sait
  ///  désormais trancher tout seul grâce aux dates. C'était le défaut du
  ///  21/08 → 17/09, où tout reposait sur un WebSocket qui n'arrivait pas.
  static Future<void> clearAll() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
      await prefs.remove(_kKeyV1);
      if (kDebugMode) debugPrint('[OptOut] tout levé (push panel)');
    } catch (_) {
      // best-effort.
    }
  }

  // ---------------------------------------------------------
  //  Stockage
  // ---------------------------------------------------------
  static Future<Map<String, int>> _lire(SharedPreferences prefs) async {
    final Map<String, int> out = <String, int>{};
    for (final String e in prefs.getStringList(_kKey) ?? const <String>[]) {
      final int i = e.lastIndexOf('|');
      if (i <= 0) continue;
      final int? ts = int.tryParse(e.substring(i + 1));
      if (ts == null) continue;
      out[e.substring(0, i)] = ts;
    }
    await _migrerV1(prefs, out);
    return out;
  }

  /// AMNISTIE UNIQUE des empreintes v1 (17/09/2026).
  ///
  ///  Une empreinte v1 n'a pas de date : impossible de savoir si elle est
  ///  antérieure ou postérieure à l'assignation. On ne peut donc pas
  ///  trancher — et `doitSauter` ne bloque pas dans le doute.
  ///
  ///  Conséquence ASSUMÉE : sur chaque appareil déjà bloqué aujourd'hui,
  ///  la source assignée revient UNE fois. C'est précisément ce qu'on
  ///  veut — c'est ce qui débloque le parc sans que personne ait à
  ///  toucher un téléphone. Si le client la resupprime, l'empreinte est
  ///  réécrite avec une vraie date et tient, cette fois pour de bon.
  ///
  ///  On convertit en date 0 (« inconnue ») plutôt que de jeter la clé
  ///  tout de suite : la trace reste lisible en débogage, et la v1 est
  ///  effacée une bonne fois.
  static Future<void> _migrerV1(
    SharedPreferences prefs,
    Map<String, int> out,
  ) async {
    final List<String>? v1 = prefs.getStringList(_kKeyV1);
    if (v1 == null) return;
    for (final String fp in v1) {
      out.putIfAbsent(fp, () => 0);
    }
    await prefs.remove(_kKeyV1);
    await _ecrire(prefs, out);
    if (kDebugMode) debugPrint('[OptOut] v1 migrée (${v1.length}) — amnistie');
  }

  static Future<void> _ecrire(
    SharedPreferences prefs,
    Map<String, int> all,
  ) async {
    await prefs.setStringList(
      _kKey,
      all.entries.map((MapEntry<String, int> e) => '${e.key}|${e.value}')
          .toList(),
    );
  }
}
