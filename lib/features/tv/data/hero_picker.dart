// =========================================================
//  hero_picker.dart — Choix du héro d'accueil (Modèles B/C/D)
// =========================================================
//  ⚠️ EN RÉSERVE (2026-08-01) : les modèles B/C qui l'utilisaient ont été
//  retirés à la demande du client — un seul accueil (Modèle A) est
//  maintenu. Cette brique reste ici, PURE et TESTÉE, prête pour le second
//  modèle que le client fournira. Elle ne coûte rien tant qu'on ne
//  l'appelle pas.
//
//  Brique PURE partagée par les templates d'accueil : ordonne les
//  candidats du grand aperçu (« héro ») et écarte les chaînes que le
//  score de fiabilité local (n°38) sait défaillantes CHEZ CE CLIENT —
//  photo terrain 2026-08-01 : le héro pointait une chaîne coupée côté
//  fournisseur → grand cadre noir en plein accueil.
//
//  Règles :
//    • ordre d'affection : « Ma soirée » (créneau) → récents → favoris
//      → 1re chaîne du bouquet ;
//    • les chaînes fiables passent DEVANT les peu fiables (ordre stable
//      à l'intérieur de chaque groupe) — mais les peu fiables restent en
//      dernier recours : mieux vaut un logo que rien du tout ;
//    • dédoublonnage par id, liste bornée ([max]) : l'accueil bascule
//      de candidat en candidat quand un aperçu échoue (indépendance),
//      jamais en boucle infinie.
// =========================================================
import '../../channels/domain/channel.dart';

/// Candidats du héro, du plus désirable au dernier recours.
/// [byId] est la map mémoïsée du bouquet (10-50 k chaînes : ne PAS la
/// reconstruire ici à chaque événement). [isFlaky] vient de
/// ChannelReliability (n°38) — injecté pour rester pur et testable.
List<Channel> heroCandidates({
  required List<Channel> all,
  required Map<String, Channel> byId,
  String? slotId,
  required Iterable<String> recents,
  required Iterable<String> favorites,
  required bool Function(String id) isFlaky,
  int max = 6,
}) {
  if (all.isEmpty) return const <Channel>[];
  final List<Channel> ordered = <Channel>[];
  final Set<String> seen = <String>{};
  void add(Channel? c) {
    if (c != null && seen.add(c.id)) ordered.add(c);
  }

  if (slotId != null) add(byId[slotId]);
  for (final String id in recents) {
    add(byId[id]);
  }
  for (final String id in favorites) {
    add(byId[id]);
  }
  add(all.first);

  final List<Channel> sound = <Channel>[];
  final List<Channel> flaky = <Channel>[];
  for (final Channel c in ordered) {
    (isFlaky(c.id) ? flaky : sound).add(c);
  }
  final List<Channel> out = <Channel>[...sound, ...flaky];
  return out.length <= max ? out : out.sublist(0, max);
}
