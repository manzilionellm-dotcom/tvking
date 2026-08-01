// =========================================================
//  tv_home_template.dart — Templates d'accueil TV (au choix du client)
// =========================================================
//  Chaque client choisit la DISPOSITION de sa home qui lui parle
//  (« facile pour moi », « comme à la maison »). Persisté par appareil
//  (SharedPreferences) + ChangeNotifier → la home se reconstruit à chaud
//  quand on change de template. Même modèle que LocaleRepository.
//
//  Extensible : pour ajouter un template, on ajoute une valeur à l'enum
//  + son rendu dans tv_app (sélection du widget de home).
// =========================================================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../playlists/data/favorites_repository.dart';

/// Portée des favoris. Les deux modèles PARTAGENT désormais la même liste
/// (portée `default`) : ce sont deux présentations du MÊME accueil, pas deux
/// univers. Séparer les favoris datait de l'époque à quatre templates —
/// avec le Modèle B en accueil principal, ça aurait fait disparaître les
/// cœurs déjà posés par le client. On garde la fonction (l'API est utilisée
/// au boot et à chaque bascule) mais elle renvoie toujours la même portée.
String favoritesScopeForTemplate(TvHomeTemplate t) =>
    FavoritesRepository.defaultScope;

/// LES DEUX MODÈLES D'ACCUEIL, dans l'ordre où le client veut les voir.
///
/// Décision client (2026-08-01, deuxième temps) : l'accueil à menu latéral
/// (`iptv`) devient l'accueil PRINCIPAL — le « Modèle A » — et l'ancien
/// accueil (`classic`) passe en second, « Modèle B ». On garde les
/// identifiants techniques d'origine pour ne pas invalider les choix déjà
/// enregistrés sur les appareils.
enum TvHomeTemplate {
  iptv, // Modèle A : menu latéral, recherche, cinéma, grille de chaînes
  classic, // Modèle B : menu compact en haut, liste des chaînes en grand
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
  /// INVERSION demandée par le client (2026-08-01) : « je veux que B soit
  /// l'app primordiale et A l'app secondaire ». L'accueil à menu latéral
  /// devient donc le **Modèle A** (et l'accueil par défaut), l'ancien
  /// devient le **Modèle B**. Les identifiants techniques (`classic`,
  /// `iptv`) ne changent PAS : les choix déjà enregistrés restent valides.
  String get label {
    switch (this) {
      case TvHomeTemplate.iptv:
        return 'Modèle A';
      case TvHomeTemplate.classic:
        return 'Modèle B';
    }
  }

  /// Sous-titre explicatif dans le sélecteur — décrit la DISPOSITION, sans
  /// jamais citer une app tierce.
  String get description {
    switch (this) {
      case TvHomeTemplate.iptv:
        return 'Menu latéral, recherche, cinéma et grille de chaînes.';
      case TvHomeTemplate.classic:
        return 'Menu compact en haut, liste des chaînes en grand.';
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
  // Repli SÛR = le Modèle A, c'est-à-dire l'accueil à menu latéral
  // (`iptv`) : c'est lui l'accueil principal depuis la décision client du
  // 2026-08-01. Un appareil qui n'a jamais choisi ouvre donc dessus.
  return TvHomeTemplate.iptv;
}

class TvHomeTemplateRepository extends ChangeNotifier {
  TvHomeTemplateRepository._();
  static final TvHomeTemplateRepository instance = TvHomeTemplateRepository._();

  static const String _kKey = 'tv.home.template.v1';

  TvHomeTemplate _template = TvHomeTemplate.iptv;
  TvHomeTemplate get template => _template;

  /// À appeler UNE fois au boot (avant le 1er rendu de la home).
  Future<void> initialize() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _template = _templateFromId(prefs.getString(_kKey));
    } catch (_) {
      _template = TvHomeTemplate.iptv;
    }
    // Portée des favoris (identique pour les deux modèles — cf. plus haut).
    await FavoritesRepository.instance
        .setScope(favoritesScopeForTemplate(_template));
    notifyListeners();
  }

  /// Change le template : application IMMÉDIATE (notify) + persistance.
  Future<void> setTemplate(TvHomeTemplate t) async {
    if (t == _template) return;
    _template = t;
    // Portée des favoris : la même dans les deux modèles (cf. plus haut).
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
