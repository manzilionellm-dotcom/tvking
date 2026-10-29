// =========================================================
//  tv_delete.dart — « Supprimer » sur la télé tient pour de bon
// =========================================================
//  Mesuré le 06/10/2026 sur la box de test : le serveur sert deux listes,
//  « Mon abonnement » (origine panel) et « 6 » (ajoutée par le client,
//  rangée sur le serveur). Supprimer sur la télé n'effaçait que la copie
//  locale : la vérification suivante la réimportait. Le propriétaire :
//  « si je les efface, elles reviennent ».
//
//  Règle (pure, testée) :
//    • liste ajoutée par le client (origin 'self', avec un id serveur)
//      → supprimée AUSSI sur le serveur (DELETE /api/self-source) ;
//    • liste envoyée par le panel → retirée de la télé et REFUSÉE
//      durablement, même après synchronisation, renvoi ou redémarrage ;
//    • liste que le serveur ne connaît pas → même refus local durable.
//  Seul un nouvel ajout volontaire dans l'app rétablit une source.
//  Un réseau indisponible n'empêche pas la suppression locale.
// =========================================================

import 'source_fingerprint.dart';

enum TvDeleteKind { removeOnServer, refusePanelList, localOnly }

class TvDeleteDecision {
  const TvDeleteDecision(this.kind, {this.serverId, this.fingerprints = const <String>[]});
  final TvDeleteKind kind;

  /// Identifiant de la liste côté serveur (liste ajoutée par le client).
  final String? serverId;

  /// Empreintes à refuser (liste du panel).
  final List<String> fingerprints;
}

/// Décide quoi faire d'une suppression sur la télé, d'après les listes que
/// le serveur sert à cette box ([served] = `sources[]` de device-source).
TvDeleteDecision decideTvDelete({
  required List<String> playlistFingerprints,
  required List<Map<String, dynamic>> served,
}) {
  final Set<String> mine = playlistFingerprints.toSet();
  for (final Map<String, dynamic> item in served) {
    final String? fp = SourceFingerprint.fromMap(item);
    if (fp == null || !mine.contains(fp)) continue;
    final String origin = (item['origin'] as String? ?? 'panel').trim();
    final String id = (item['id'] as String? ?? '').trim();
    if (origin == 'self' && id.isNotEmpty) {
      return TvDeleteDecision(TvDeleteKind.removeOnServer, serverId: id);
    }
    return TvDeleteDecision(
      TvDeleteKind.refusePanelList,
      fingerprints: <String>{fp, ...playlistFingerprints}.toList(),
    );
  }
  return const TvDeleteDecision(TvDeleteKind.localOnly);
}

/// Listes refusées sur la télé : empreinte → instant de la suppression (ms).
/// Un retrait reste un retrait même après absence temporaire ou renvoi
/// global du panel. Seul un nouvel ajout volontaire peut rétablir la liste.
Map<String, int> pruneRefused(
  Map<String, int> refused, {
  required Set<String> servedFingerprints,
  int? panelResendAtMs,
}) {
  return Map<String, int>.of(refused);
}

/// Vrai si une liste servie a été refusée sur la télé.
bool isRefusedOnTv(String? fingerprint, Map<String, int> refused) =>
    fingerprint != null && refused.containsKey(fingerprint);
