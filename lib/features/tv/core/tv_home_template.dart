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

/// ORDRE DE PRÉSENTATION (≠ ordre de déclaration de l'enum, qui est figé par
/// la persistance historique). Décision du propriétaire (15/08/2026) : le
/// modèle « grandes tuiles » est le plus présentable → il devient le
/// **Modèle A**, vitrine de l'app, et l'accueil des NOUVELLES installations ;
/// l'accueil historique devient le Modèle B. Cette liste pilote à la fois
/// l'ordre du sélecteur et les libellés A/B/C/D.
const List<TvHomeTemplate> kTemplateOrder = <TvHomeTemplate>[
  TvHomeTemplate.launcher, // A — vitrine
  TvHomeTemplate.classic, // B — historique
  TvHomeTemplate.rails, // C
  TvHomeTemplate.tivimate, // D
];

/// Accueil par défaut des installations NEUVES. Les installations
/// EXISTANTES ne sont jamais déplacées (cf. `initialize`).
const TvHomeTemplate kDefaultTemplate = TvHomeTemplate.launcher;

/// Accueil par défaut HISTORIQUE — conservé pour les box déjà en service.
const TvHomeTemplate kLegacyDefaultTemplate = TvHomeTemplate.classic;

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

  /// Lettre du modèle — DÉRIVÉE de [kTemplateOrder] : renommer/réordonner
  /// les modèles ne se fait donc qu'à UN seul endroit (plus de switch à
  /// tenir synchronisé, source classique de A/B incohérents entre écrans).
  String get letter {
    final int i = kTemplateOrder.indexOf(this);
    return i < 0 ? '?' : String.fromCharCode(0x41 + i); // A, B, C, D
  }

  /// Nom court affiché dans le sélecteur. Noms NEUTRES (lettres) — aucune
  /// marque concurrente (ni « IBO » ni « TiviMate ») : ce sont NOS modèles.
  /// Repli technique : l'écran localisé utilise les clés tvTemplateModelA…D.
  String get label => 'Modèle $letter';

  /// Sous-titre explicatif dans le sélecteur — décrit la DISPOSITION, sans
  /// jamais citer une app tierce.
  String get description {
    switch (this) {
      case TvHomeTemplate.classic:
        return 'Menu compact en haut, liste des chaînes en grand.';
      case TvHomeTemplate.launcher:
        return 'Grandes tuiles d\'accès rapide — simple et direct.';
      case TvHomeTemplate.rails:
        return 'Aperçu + rangée d\'icônes + rail de favoris en direct.';
      case TvHomeTemplate.tivimate:
        return 'Chaînes en panneau à gauche + aperçu et programme à droite.';
    }
  }
}

TvHomeTemplate? _templateFromId(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final TvHomeTemplate t in TvHomeTemplate.values) {
    if (t.id == id) return t;
  }
  return null; // id inconnu (downgrade) → l'appelant décide du repli
}

class TvHomeTemplateRepository extends ChangeNotifier {
  TvHomeTemplateRepository._();
  static final TvHomeTemplateRepository instance = TvHomeTemplateRepository._();

  static const String _kKey = 'tv.home.template.v1';

  TvHomeTemplate _template = kLegacyDefaultTemplate;
  TvHomeTemplate get template => _template;

  /// À appeler UNE fois au boot (avant le 1er rendu de la home).
  ///
  /// MIGRATION A↔B (15/08/2026) : le défaut des installations NEUVES passe
  /// au « grandes tuiles » (Modèle A). Une box DÉJÀ EN SERVICE ne doit
  /// JAMAIS changer d'accueil toute seule — d'autant que chaque univers a
  /// SES favoris (`favoritesScopeForTemplate`) : basculer d'office donnerait
  /// « mes favoris ont disparu » à des clients qui paient. On ne bascule
  /// donc que si les préférences sont VIERGES (vraie première ouverture) ;
  /// sinon on grave l'ancien défaut, ce qui rend le choix stable pour la
  /// suite. En cas de doute, le code penche du côté SÛR (on garde
  /// l'historique) : le pire cas est un nouvel arrivant sur le Modèle B,
  /// jamais un client existant dépossédé de ses favoris.
  Future<void> initialize() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final TvHomeTemplate? stored = _templateFromId(prefs.getString(_kKey));
      if (stored != null) {
        _template = stored; // choix explicite (ou déjà migré) : intouchable
      } else {
        final bool freshInstall = prefs.getKeys().isEmpty;
        _template = freshInstall ? kDefaultTemplate : kLegacyDefaultTemplate;
        await prefs.setString(_kKey, _template.id); // fige la décision
      }
    } catch (_) {
      _template = kLegacyDefaultTemplate;
    }
    // Chaque univers a ses favoris → on aligne la portée sur le template
    // actif. ISOLÉ dans son propre try : cet initialize est AWAITÉ au boot
    // (main_tv, avant le 1er rendu) et setScope ouvre la base SQLite. Une
    // base momentanément indisponible ou corrompue ne doit PAS empêcher
    // l'app de démarrer — au pire les favoris se rechargeront plus tard.
    try {
      await FavoritesRepository.instance
          .setScope(favoritesScopeForTemplate(_template));
    } catch (_) {
      // Boot prioritaire : on continue avec la disposition résolue.
    }
    notifyListeners();
  }

  /// Change le template : application IMMÉDIATE (notify) + persistance.
  Future<void> setTemplate(TvHomeTemplate t) async {
    if (t == _template) return;
    _template = t;
    // Bascule d'univers → bascule des favoris (chaque univers a les siens).
    // Protégé : si la base bronche, le CHANGEMENT DE DISPOSITION doit quand
    // même s'appliquer et se mémoriser (avant, une exception ici sautait le
    // notifyListeners ET l'écriture → le client voyait son choix « ne rien
    // faire », puis revenir à l'ancien modèle au redémarrage).
    try {
      await FavoritesRepository.instance.setScope(favoritesScopeForTemplate(t));
    } catch (_) {
      // Favoris rechargés au prochain accès ; la disposition, elle, passe.
    }
    notifyListeners();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, t.id);
    } catch (_) {
      // Best-effort : le choix reste actif en mémoire même si l'écriture rate.
    }
  }
}
