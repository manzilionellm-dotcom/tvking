// =========================================================
//  source_fingerprint.dart — Reconnaître UNE liste
// =========================================================
//  La même chaîne que le Worker (cloudflare/source_revoke.js).
//  Sert à savoir quelle liste locale correspond à celle que le
//  panel vient de retirer, sans jamais comparer les mots de passe.
// =========================================================

import 'playlist.dart';
import 'm3u_link.dart';

/// Empreinte stable d'une source IPTV.
abstract final class SourceFingerprint {
  /// Toutes les empreintes sous lesquelles une liste LOCALE peut être
  /// reconnue. Une liste Xtream venue d'un lien get.php du panel
  /// (m3u_link.dart) en a deux : la sienne (`xtream|…`) et celle du lien
  /// que le panel connaît (`m3u|…`). L'effacement et l'interrupteur
  /// allumé / éteint la retrouvent par l'une ou l'autre.
  static List<String> ofPlaylist(Playlist playlist) {
    final List<String> out = <String>[];
    if (playlist.type == PlaylistType.xtream) {
      out.addAll(xtreamAliases(playlist.xtreamServer, playlist.xtreamUsername));
    }
    out.addAll(ofM3uUrl(playlist.m3uUrl));
    return out.toSet().toList();
  }

  /// Le même abonnement peut être saisi en M3U puis servi en Xtream, ou
  /// inversement. Le refus conserve les deux formes, même après redémarrage.
  static List<String> ofM3uUrl(String? url) {
    final String? link = m3u(url);
    if (link == null) return const <String>[];
    final XtreamAccount? account = xtreamFromM3uLink(url);
    return <String>[link, if (account != null)
      ...xtreamAliases(account.serverUrl, account.username)];
  }

  /// :80 et l'absence de port désignent le même serveur HTTP (:443 en HTTPS).
  /// On garde aussi l'ancienne forme pour relire les refus déjà enregistrés.
  static List<String> xtreamAliases(String? server, String? username) {
    final String? original = xtream(server, username);
    if (original == null) return const <String>[];
    final Uri? uri = Uri.tryParse((server ?? '').trim());
    if (uri == null || uri.host.isEmpty || !<String>['http', 'https'].contains(uri.scheme)) return <String>[original];
    final int defaultPort = uri.scheme == 'https' ? 443 : 80;
    final String port = uri.port == defaultPort ? '' : ':${uri.port}';
    final String canonical = '${uri.scheme}://${uri.host}$port${uri.path.replaceAll(RegExp(r'/+$'), '')}';
    final String? normalized = xtream(canonical, username);
    return <String>{original, if (normalized != null) normalized}.toList();
  }

  static List<String> allFromMap(Map<String, dynamic> item) {
    final String? primary = fromMap(item);
    return <String>{if (primary != null) primary,
      if (item['type'] == 'xtream') ...xtreamAliases(item['server_url'] as String?, item['username'] as String?),
      ...ofM3uUrl(item['m3u_url'] as String?)}.toList();
  }

  static String? xtream(String? server, String? username) {
    final String host = (server ?? '').trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
    final String user = (username ?? '').trim();
    if (host.isEmpty || user.isEmpty) return null;
    return 'xtream|$host|$user';
  }

  static String? m3u(String? url) {
    final String u = (url ?? '').trim();
    if (u.isEmpty) return null;
    return 'm3u|$u';
  }

  /// Depuis un objet renvoyé par le Worker (`revoked[]` ou `sources[]`).
  static String? fromMap(Map<String, dynamic> item) {
    final String type = (item['type'] as String? ?? '').trim().toLowerCase();
    if (type == 'xtream') {
      return xtream(item['server_url'] as String?, item['username'] as String?);
    }
    if (type == 'm3u') return m3u(item['m3u_url'] as String?);
    return null;
  }

  static List<String> revokedFromBody(Map<String, dynamic> body) {
    final Object? raw = body['revoked'];
    if (raw is! List) return const <String>[];
    final List<String> out = <String>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final String? fp = fromMap(item.cast<String, dynamic>());
      if (fp != null && !out.contains(fp)) out.add(fp);
    }
    return out;
  }
}

/// Quelles empreintes faut-il effacer en local ?
///
/// - [revoked] : tombstones du panel (même si la box ne les avait
///   jamais « mémorisées »).
/// - [remembered] : listes que CETTE box a déjà reçues du panel.
/// - [current] : listes encore assignées. On ne retire JAMAIS une
///   liste qui est encore là.
Set<String> fingerprintsToDrop({
  required Set<String> remembered,
  required Set<String> current,
  required Set<String> revoked,
}) {
  final Set<String> drop = <String>{...revoked, ...remembered.difference(current)};
  drop.removeAll(current);
  return drop;
}

// ---------------------------------------------------------------------------
//  Interrupteur du panel : liste « allumée » / « éteinte »
// ---------------------------------------------------------------------------

/// Ce que la box doit faire après avoir relu les listes du panel.
class PanelVisibilityPlan {
  const PanelVisibilityPlan({required this.apply, required this.nextApplied});

  /// Empreinte → `true` (réafficher) ou `false` (masquer). Seulement ce
  /// qui CHANGE : une liste déjà dans le bon état n'est pas retouchée.
  final Map<String, bool> apply;

  /// Mémoire à garder sur la box : les listes que le PANEL a éteintes.
  final Map<String, bool> nextApplied;
}

/// Le panel envoie `enabled: false` sur une liste éteinte (champ absent =
/// allumée). La box :
/// - masque une liste que le panel vient d'éteindre ;
/// - réaffiche une liste que le panel avait éteinte et rallume ;
/// - ne touche JAMAIS une liste que le panel n'a jamais éteinte : si le
///   client l'a masquée lui-même sur sa TV, son choix est respecté ;
/// - oublie une liste qui n'est plus envoyée (elle est effacée ailleurs).
///
/// [applied] = empreintes que le panel avait éteintes au tour précédent.
PanelVisibilityPlan planPanelVisibility({
  required Iterable<Map<String, dynamic>> served,
  required Map<String, bool> applied,
}) {
  final Map<String, bool> apply = <String, bool>{};
  final Map<String, bool> next = <String, bool>{};
  for (final Map<String, dynamic> item in served) {
    final String? fp = SourceFingerprint.fromMap(item);
    if (fp == null) continue;
    final bool off = item['enabled'] == false;
    if (off) {
      next[fp] = false;
      if (applied[fp] != false) apply[fp] = false;
    } else if (applied[fp] == false) {
      apply[fp] = true;
    }
  }
  return PanelVisibilityPlan(apply: apply, nextApplied: next);
}
