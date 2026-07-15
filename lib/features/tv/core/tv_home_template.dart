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
    t == TvHomeTemplate.classic
        ? FavoritesRepository.defaultScope
        : 'seven';

enum TvHomeTemplate {
  classic, // home historique : menu compact en haut + contenu plein écran
  launcher, // grandes tuiles façon lanceur (IBO « grille »), simple et direct
  rails, // aperçu + rangée d'icônes + rail de favoris (IBO « rails »)
  tivimate, // panneau chaînes (rail + groupes + liste + aperçu EPG) façon TiviMate
}

extension TvHomeTemplateInfo on TvHomeTemplate {
  String get id {
    switch (this) {
      case TvHomeTemplate.classic:
        return 'classic';
      case TvHomeTemplate.launcher:
        return 'launcher';
      case TvHomeTemplate.rails:
        return 'rails';
      case TvHomeTemplate.tivimate:
        return 'tivimate';
    }
  }

  /// Nom court affiché dans le sélecteur.
  String get label {
    switch (this) {
      case TvHomeTemplate.classic:
        return 'Classique';
      case TvHomeTemplate.launcher:
        return 'IBO — Grandes tuiles';
      case TvHomeTemplate.rails:
        return 'IBO — Rails';
      case TvHomeTemplate.tivimate:
        return 'TiviMate';
    }
  }

  /// Sous-titre explicatif dans le sélecteur.
  String get description {
    switch (this) {
      case TvHomeTemplate.classic:
        return 'Menu compact en haut, liste des chaînes en grand.';
      case TvHomeTemplate.launcher:
        return 'Grandes tuiles bordeaux façon IBO — simple et direct.';
      case TvHomeTemplate.rails:
        return 'Aperçu + rangée d\'icônes + rail de favoris (façon IBO rails).';
      case TvHomeTemplate.tivimate:
        return 'Liste des chaînes en panneau + aperçu EPG (façon TiviMate).';
    }
  }
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
