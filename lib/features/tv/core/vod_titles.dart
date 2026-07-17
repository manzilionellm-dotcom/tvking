// =========================================================
//  vod_titles.dart — Titres VOD présentables (Cinéma 10-foot)
// =========================================================
//  Les catalogues Xtream/M3U livrent des noms techniques : « EN | Barney's
//  Great Adventure », « MA | Yassar W… », suffixes HD/4K… Les plateformes
//  premium n'affichent JAMAIS ces identifiants (recherche 2026-07-17 :
//  billboard Netflix et carrousel Android TV = titres curés, lisibles).
//
//  Le nettoyage existe déjà pour le Live : TitleCurator (préfixes « FR | »,
//  « [VIP] », suffixes techniques, Title Case respectueux, jamais de
//  résultat vide). Ici on le met À DISPOSITION DU CINÉMA avec un cache
//  (le curateur fait du travail regex — inutile de le refaire à chaque
//  rebuild d'une rangée de 200 affiches).
// =========================================================
import '../../../core/curation/title_curator.dart';

abstract final class VodTitles {
  // Cache nom brut → nom curé. Borné : un catalogue VOD se compte en
  // milliers de titres, pas en millions — on purge par sécurité au-delà.
  static final Map<String, String> _cache = <String, String>{};
  static const int _maxEntries = 8192;

  /// Nom présentable à l'écran (affiches, héros, fiches, téléchargements).
  /// Les IDENTIFIANTS et les recherches continuent d'utiliser le nom brut.
  static String clean(String raw) {
    if (raw.isEmpty) return raw;
    if (_cache.length > _maxEntries) _cache.clear();
    return _cache.putIfAbsent(raw, () => TitleCurator.curate(raw));
  }
}
