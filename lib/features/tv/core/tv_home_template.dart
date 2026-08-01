// =========================================================
//  tv_home_template.dart — Templates d'accueil TV (au choix du client)
// =========================================================
//  Chaque client choisit la DISPOSITION de sa home qui lui parle
//  (« facile pour moi », « comme à la maison »). Persisté par appareil
//  (SharedPreferences) + ChangeNotifier → la home se reconstruit à chaud
//  quand on change de template. Même modèle que LocaleRepository.
//
//  Extensible : pour ajouter un template, on ajoute une valeur à l'enum
//  + son rendu dans tv_app (sélection du widget de home). Le « Classique »
//  reste la home historique, inchangée (repli sûr).
// =========================================================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../playlists/data/favorites_repository.dart';

/// Univers de favoris associé à un template : « The Few » (Classique) garde ses
/// favoris historiques (portée `default`) ; « Seven » (IBO/TiviMate) a les
/// siens (portée `seven`). Chaque univers est autonome sur les favoris.
String favoritesScopeForTemplate(TvHomeTemplate t) =>
    t == TvHomeTemplate.classic ? FavoritesRepository.defaultScope : 'seven';

/// LES MODÈLES D'ACCUEIL.
///
/// Décision client (2026-08-01) : on repart d'UN seul modèle — le A, celui
/// qui a toujours été la maison. Les trois autres (grandes tuiles, rails,
/// panneau chaînes) ont été RETIRÉS du code : ils diluaient l'effort de
/// mise au point sur quatre accueils au lieu d'un seul irréprochable.
/// Un second modèle viendra, fourni par le client — l'énumération, le
/// sélecteur et la persistance restent donc en place, prêts à l'accueillir.
enum TvHomeTemplate {
  classic, // menu compact en haut, liste des chaînes en grand
  iptv, // Modèle B (design client) : ambiance selon l'heure, reco + grille
}

extension TvHomeTemplateInfo on TvHomeTemplate {
  String get id {
    switch (this) {
      case TvHomeTemplate.classic:
        return 'classic';
      case TvHomeTemplate.iptv:
        return 'iptv';
    }
  }

  /// Nom court affiché dans le sélecteur. Noms NEUTRES (lettres) — aucune
  /// marque concurrente (ni « IBO » ni « TiviMate ») : ce sont NOS modèles.
  String get label {
    switch (this) {
      case TvHomeTemplate.classic:
        return 'Modèle A';
      case TvHomeTemplate.iptv:
        return 'Modèle B';
    }
  }

  /// Sous-titre explicatif dans le sélecteur — décrit la DISPOSITION, sans
  /// jamais citer une app tierce.
  String get description {
    switch (this) {
      case TvHomeTemplate.classic:
        return 'Menu compact en haut, liste des chaînes en grand.';
      case TvHomeTemplate.iptv:
        return 'Ambiance selon l\'heure, reco en haut, grille de chaînes.';
    }
  }
}

/// Le modèle SUIVANT dans la liste (cyclique). Sert à la petite pastille de
/// bascule posée en haut de chaque accueil : le Modèle A affiche « Modèle
/// B », le Modèle B affiche « Modèle A » — un seul OK suffit, sans passer
/// par un écran de sélection. Avec un 3ᵉ modèle, la pastille fera le tour.
TvHomeTemplate otherTemplate(TvHomeTemplate t) {
  const List<TvHomeTemplate> all = TvHomeTemplate.values;
  return all[(all.indexOf(t) + 1) % all.length];
}

TvHomeTemplate _templateFromId(String? id) {
  for (final TvHomeTemplate t in TvHomeTemplate.values) {
    if (t.id == id) return t;
  }
  return TvHomeTemplate.classic; // repli sûr
}

class TvHomeTemplateRepository extends ChangeNotifier {
  TvHomeTemplateRepository._();
  static final TvHomeTemplateRepository instance = TvHomeTemplateRepository._();

  static const String _kKey = 'tv.home.template.v1';

  TvHomeTemplate _template = TvHomeTemplate.classic;
  TvHomeTemplate get template => _template;

  /// À appeler UNE fois au boot (avant le 1er rendu de la home).
  Future<void> initialize() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _template = _templateFromId(prefs.getString(_kKey));
    } catch (_) {
      _template = TvHomeTemplate.classic;
    }
    // Chaque univers a ses favoris → on aligne la portée sur le template actif.
    await FavoritesRepository.instance
        .setScope(favoritesScopeForTemplate(_template));
    notifyListeners();
  }

  /// Change le template : application IMMÉDIATE (notify) + persistance.
  Future<void> setTemplate(TvHomeTemplate t) async {
    if (t == _template) return;
    _template = t;
    // Bascule d'univers → bascule des favoris (chaque univers a les siens).
    await FavoritesRepository.instance.setScope(favoritesScopeForTemplate(t));
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, t.id);
    } catch (_) {
      // Best-effort : le choix reste actif en mémoire même si l'écriture rate.
    }
  }
}
