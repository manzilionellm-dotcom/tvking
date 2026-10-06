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
//    • liste envoyée par le panel → retirée de la télé et REFUSÉE : la box
//      ne la réimporte plus tant que le panel ne la renvoie pas (un ordre
//      « liste » du panel, plus récent que la suppression, la fait revenir :
//      le panel reste le maître) ou ne la retire pas ;
//    • liste que le serveur ne connaît pas → effacée de la télé, c'est tout.
//  Repli `zuno.source.tv_delete_legacy` : ancien comportement (copie
//  locale seulement, la liste revient).
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
/// On oublie un refus quand le panel ne sert plus la liste (plus rien à
/// refuser) ou quand le panel a renvoyé des listes APRÈS la suppression.
Map<String, int> pruneRefused(
  Map<String, int> refused, {
  required Set<String> servedFingerprints,
  int? panelResendAtMs,
}) {
  final Map<String, int> out = <String, int>{};
  refused.forEach((String fp, int at) {
    if (!servedFingerprints.contains(fp)) return;
    if (panelResendAtMs != null && panelResendAtMs > at) return;
    out[fp] = at;
  });
  return out;
}

/// Vrai si une liste servie a été refusée sur la télé.
bool isRefusedOnTv(String? fingerprint, Map<String, int> refused) =>
    fingerprint != null && refused.containsKey(fingerprint);
