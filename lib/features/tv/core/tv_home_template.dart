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

enum TvHomeTemplate {
  classic, // home historique : menu compact en haut + contenu plein écran
  launcher, // grandes tuiles façon lanceur (IBO « grille »), simple et direct
}

extension TvHomeTemplateInfo on TvHomeTemplate {
  String get id {
    switch (this) {
      case TvHomeTemplate.classic:
        return 'classic';
      case TvHomeTemplate.launcher:
        return 'launcher';
    }
  }

  /// Nom court affiché dans le sélecteur.
  String get label {
    switch (this) {
      case TvHomeTemplate.classic:
        return 'Classique';
      case TvHomeTemplate.launcher:
        return 'IBO — Grandes tuiles';
    }
  }

  /// Sous-titre explicatif dans le sélecteur.
  String get description {
    switch (this) {
      case TvHomeTemplate.classic:
        return 'Menu compact en haut, liste des chaînes en grand.';
      case TvHomeTemplate.launcher:
        return 'Grandes tuiles bordeaux façon IBO — simple et direct.';
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
    notifyListeners();
  }

  /// Change le template : application IMMÉDIATE (notify) + persistance.
  Future<void> setTemplate(TvHomeTemplate t) async {
    if (t == _template) return;
    _template = t;
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, t.id);
    } catch (_) {
      // Best-effort : le choix reste actif en mémoire même si l'écriture rate.
    }
  }
}
