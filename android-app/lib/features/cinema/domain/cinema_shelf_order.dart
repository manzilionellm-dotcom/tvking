// =========================================================
//  cinema_shelf_order.dart — Dans quel ordre ranger le cinéma
// =========================================================
//  Demande du 13/11/2026 : le cinéma doit s'ouvrir sur ce que le
//  client veut voir, dans SA langue, sans qu'il ait à chercher.
//
//  RÈGLE (rien n'est caché, on change seulement l'ORDRE) :
//   1. « ses rayons » : les catégories où il a déjà ouvert des
//      titres, les plus fréquentées d'abord (3 au maximum) ;
//   2. les catégories dans la langue de l'application ;
//   3. les catégories sans langue reconnue (« Netflix », « 4K »…) ;
//   4. les autres langues.
//  Dans chaque groupe, l'ordre du fournisseur est gardé.
//
//  Pourquoi ne pas FILTRER sur la langue : le 27/09/2026 le filtre
//  automatique faisait croire qu'une partie du catalogue manquait.
//  Ici tout reste visible, plus bas dans la liste.
//
//  Pur : pas de Flutter, pas de disque. Facile à tester.
// =========================================================

import 'cinema_language.dart';
import 'cinema_models.dart';

/// Nombre de « rayons préférés » remontés tout en haut.
const int kCinemaFavoriteShelves = 3;

/// Rend [cats] rangées pour [viewerLanguage] (code de la langue de
/// l'application, ex. « fr », « pt-BR ») et pour [taste] (clé de
/// catégorie → nombre de titres ouverts). Liste neuve ; [cats] n'est
/// pas modifiée.
List<CinemaCategory> orderCinemaShelves(
  List<CinemaCategory> cats, {
  required String? viewerLanguage,
  Map<String, int> taste = const <String, int>{},
}) {
  final String? lang = (viewerLanguage == null || viewerLanguage.trim().isEmpty)
      ? null
      : CinemaLanguage.normalizeCode(viewerLanguage);

  // 1. Rayons préférés : seulement ceux encore présents dans le catalogue.
  final List<CinemaCategory> liked = <CinemaCategory>[
    for (final CinemaCategory c in cats)
      if ((taste[c.key] ?? 0) > 0) c,
  ];
  final Map<String, int> position = <String, int>{
    for (int i = 0; i < cats.length; i++) cats[i].key: i,
  };
  liked.sort((CinemaCategory a, CinemaCategory b) {
    final int byTaste = (taste[b.key] ?? 0).compareTo(taste[a.key] ?? 0);
    if (byTaste != 0) return byTaste;
    return (position[a.key] ?? 0).compareTo(position[b.key] ?? 0);
  });
  final List<CinemaCategory> top = liked.length > kCinemaFavoriteShelves
      ? liked.sublist(0, kCinemaFavoriteShelves)
      : liked;
  final Set<String> topKeys = <String>{
    for (final CinemaCategory c in top) c.key,
  };

  // 2 à 4. Le reste, par groupe de langue, ordre du fournisseur gardé.
  final List<CinemaCategory> mine = <CinemaCategory>[];
  final List<CinemaCategory> neutral = <CinemaCategory>[];
  final List<CinemaCategory> others = <CinemaCategory>[];
  for (final CinemaCategory c in cats) {
    if (topKeys.contains(c.key)) continue;
    final String? l = c.languageKey;
    if (l == null) {
      neutral.add(c);
    } else if (lang != null && l == lang) {
      mine.add(c);
    } else {
      others.add(c);
    }
  }
  return <CinemaCategory>[...top, ...mine, ...neutral, ...others];
}

/// Ajoute une ouverture au carnet des rayons. Rend un carnet neuf,
/// limité à [maxEntries] rayons (les moins fréquentés sont oubliés).
Map<String, int> noteCinemaShelf(
  Map<String, int> taste,
  String categoryKey, {
  int maxEntries = 60,
}) {
  if (categoryKey.isEmpty) return taste;
  final Map<String, int> next = Map<String, int>.from(taste);
  next[categoryKey] = (next[categoryKey] ?? 0) + 1;
  if (next.length <= maxEntries) return next;
  final List<MapEntry<String, int>> sorted = next.entries.toList()
    ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
        b.value.compareTo(a.value));
  return <String, int>{
    for (final MapEntry<String, int> e in sorted.take(maxEntries))
      e.key: e.value,
  };
}
