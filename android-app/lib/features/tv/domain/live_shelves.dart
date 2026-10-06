// =========================================================
//  live_shelves.dart — Tendances et « Pour vous » SANS calcul lourd
// =========================================================
//  ANR mesuré le 06/10/2026 sur la SHIELD (boîte noire, 09:07:21) :
//  l'écran Direct reçoit d'abord 1 000 chaînes, les pré-calcule (drapeau
//  « pré-calcul terminé » vrai), puis reçoit 50 000 chaînes. Le drapeau
//  n'était remis à faux qu'APRÈS le recalcul des rayons : Tendances et
//  « Pour vous » lisaient alors `cleanName`, `genre`, `country` des 50 000
//  chaînes. Ces getters CALCULENT quand la valeur manque (des dizaines
//  d'expressions régulières par chaîne) : fil UI figé, la box a tué l'app.
//
//  Ici, uniquement des LECTURES de cache (ChannelPrecompute.cached…). Une
//  chaîne pas encore pré-calculée est simplement ignorée ; elle apparaît
//  quand le pré-calcul (isolate) a fini et que l'écran recalcule.
//  Aucune fonction de ce fichier ne déclenche le moindre calcul de nom,
//  de genre ou de pays (prouvé par live_shelves_test.dart).
// =========================================================

import '../../channels/domain/channel.dart';

/// Chaînes « Tendances » dans l'ordre de [trending] (noms, insensible à la
/// casse), d'après les noms curés DÉJÀ en cache.
List<Channel> trendingFromCache(List<Channel> all, List<String> trending) {
  if (trending.isEmpty || all.isEmpty) return const <Channel>[];
  final Map<String, Channel> byName = <String, Channel>{};
  for (final Channel c in all) {
    final String? clean = ChannelPrecompute.cachedCleanName(c);
    if (clean == null) continue;
    byName.putIfAbsent(clean.trim().toLowerCase(), () => c);
  }
  final List<Channel> out = <Channel>[];
  final Set<String> seen = <String>{};
  for (final String name in trending) {
    final Channel? c = byName[name.trim().toLowerCase()];
    if (c != null && seen.add(c.id)) out.add(c);
  }
  return out;
}

/// « Pour vous » : profil de goût (genre ×2 + pays ×1, pondéré par la
/// récence) construit sur [recent] (ids, le plus récent d'abord), puis
/// meilleures chaînes hors déjà vues / favorites. Valeurs lues en cache
/// seulement.
List<Channel> forYouFromCache({
  required List<Channel> all,
  required Map<String, Channel> byId,
  required List<String> recent,
  required Set<String> favorites,
  int limit = 40,
}) {
  if (recent.isEmpty || all.isEmpty) return const <Channel>[];
  final Map<ChannelGenre, double> genreScore = <ChannelGenre, double>{};
  final Map<String, double> countryScore = <String, double>{};
  int rank = 0;
  for (final String id in recent.take(20)) {
    final Channel? c = byId[id];
    if (c == null) continue;
    final double w = 1.0 / (1 + rank);
    rank++;
    final ChannelGenre? g = ChannelPrecompute.cachedGenre(c);
    if (g != null && g != ChannelGenre.other) genreScore[g] = (genreScore[g] ?? 0) + w;
    final String? cc = ChannelPrecompute.cachedCountry(c).country?.code;
    if (cc != null && cc.isNotEmpty) countryScore[cc] = (countryScore[cc] ?? 0) + w;
  }
  if (genreScore.isEmpty && countryScore.isEmpty) return const <Channel>[];
  final Set<String> exclude = <String>{...recent, ...favorites};
  final List<Channel> cand = <Channel>[];
  final Map<String, double> score = <String, double>{};
  for (final Channel c in all) {
    if (exclude.contains(c.id)) continue;
    double s = 0;
    final ChannelGenre? g = ChannelPrecompute.cachedGenre(c);
    if (g != null && g != ChannelGenre.other) s += (genreScore[g] ?? 0) * 2.0;
    final String? cc = ChannelPrecompute.cachedCountry(c).country?.code;
    if (cc != null) s += countryScore[cc] ?? 0;
    if (s > 0) {
      score[c.id] = s;
      cand.add(c);
    }
  }
  cand.sort((Channel a, Channel b) => (score[b.id] ?? 0).compareTo(score[a.id] ?? 0));
  return cand.length > limit ? cand.sublist(0, limit) : cand;
}
