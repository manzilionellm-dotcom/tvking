// =========================================================
//  assistance_controller.dart — le chef d'orchestre du mode assistance
// =========================================================
//  Il tient la session (le consentement, cf. assistance_session.dart)
//  et fait exécuter les gestes. Il ne SAIT PAS ouvrir un écran : il le
//  demande à un exécuteur que l'application installe au démarrage.
//
//  POURQUOI CETTE SÉPARATION. Le consentement est une règle de maison,
//  identique partout. Les écrans, non : la box et le téléphone n'ont
//  pas les mêmes. Si ce fichier connaissait les écrans TV, le cœur de
//  l'app dépendrait d'une fonctionnalité — et le téléphone hériterait
//  d'un menu qu'il n'a pas.
//
//  ---------------------------------------------------------
//  CE QUI NE PASSE JAMAIS PAR LA PORTE
//  ---------------------------------------------------------
//  [executer] commence par demander à la session si le guidage est
//  permis. Tant que le client n'a pas dit oui, tant que la session a
//  expiré, tant qu'il a coupé — l'ordre est REFUSÉ, et le support le
//  voit refusé. C'est le point unique de passage : aucun geste ne peut
//  atteindre l'écran d'un client par un autre chemin.
// =========================================================

import 'package:flutter/foundation.dart';

import '../observability/structured_logger.dart';
import 'assistance_session.dart';

/// Ce que l'application doit savoir faire pour être guidable.
///
///  Implémenté par chaque plateforme (`tv_assistance_executeur.dart`
///  pour la box). Chaque méthode rend `true` si le geste a VRAIMENT été
///  exécuté — jamais « à peu près » : le support doit savoir si son
///  clic a eu lieu, sinon il appuie deux fois et le client voit l'app
///  partir dans tous les sens.
abstract class AssistanceExecuteur {
  /// Ouvre un écran désigné par un nom stable (« favoris »,
  /// « chaines », « reglages »…). `false` si le nom est inconnu.
  Future<bool> ouvrirEcran(String nom);

  /// Entre dans une catégorie / une liste.
  Future<bool> ouvrirCategorie(String nom);

  /// Met une chaîne à l'écran.
  Future<bool> ouvrirChaine(String id);

  /// Ajoute ou retire un favori.
  Future<bool> basculerFavori(String id);

  /// Revient en arrière, comme la touche Retour.
  Future<bool> retour();

  /// Où en est le client, en clair (« Chaînes › Favoris »). Sert à ce
  /// que le support ne pilote pas à l'aveugle.
  String ecranCourant();
}

/// Ce que l'app éclaire à l'écran du client, avec une phrase.
@immutable
class Designation {
  const Designation({required this.cible, required this.phrase});

  /// Nom stable de l'élément à éclairer (le widget correspondant
  /// s'illumine). Vide = plus rien d'éclairé.
  final String cible;

  /// « C'est ici », « Appuie sur OK »…
  final String phrase;
}

class AssistanceController extends ChangeNotifier {
  AssistanceController._();
  static final AssistanceController instance = AssistanceController._();

  final AssistanceSession _session = AssistanceSession();
  AssistanceExecuteur? _executeur;
  Designation? _designation;

  /// L'application installe son exécuteur au démarrage. Sans lui, les
  /// gestes de navigation échouent PROPREMENT (refusés, pas ignorés) :
  /// un support qui clique dans le vide doit le voir.
  void installerExecuteur(AssistanceExecuteur e) => _executeur = e;

  AssistanceSession get session => _session;
  Designation? get designation => _designation;

  EtatAssistance get etat {
    _session.rafraichir();
    return _session.etat;
  }

  String get support => _session.support;
  Duration? get tempsRestant => _session.tempsRestant;

  /// Le support demande la main. Renvoie `false` si une demande ou une
  /// session est déjà en cours.
  bool demandeRecue(String support) {
    final bool ok = _session.demander(support);
    if (ok) {
      _journal('assist.demande', <String, Object?>{'support': support});
      notifyListeners();
    }
    return ok;
  }

  /// LE CLIENT accepte.
  bool accepter() {
    final bool ok = _session.accepter();
    if (ok) {
      _journal('assist.acceptee', const <String, Object?>{});
      notifyListeners();
    }
    return ok;
  }

  /// LE CLIENT refuse.
  void refuser() {
    _session.refuser();
    _designation = null;
    _journal('assist.refusee', const <String, Object?>{});
    notifyListeners();
  }

  /// LE CLIENT coupe. Toujours possible, à la seconde.
  void arreterParClient() {
    _session.arreterParClient();
    _designation = null;
    _journal('assist.arretee_client', const <String, Object?>{});
    notifyListeners();
  }

  /// Le support rend la main.
  void arreterParSupport() {
    _session.arreterParSupport();
    _designation = null;
    _journal('assist.arretee_support', const <String, Object?>{});
    notifyListeners();
  }

  /// LE POINT UNIQUE DE PASSAGE. Aucun geste n'atteint l'écran du
  /// client sans traverser ces trois lignes.
  ///
  ///  Renvoie `true` seulement si le geste a été exécuté pour de bon.
  ///  Tout le reste — session absente, geste inconnu, exécuteur pas
  ///  installé, écran introuvable — renvoie `false`, et le panel
  ///  affiche « refusé ». Un support qui croit avoir cliqué alors que
  ///  rien n'a bougé finit par cliquer dix fois.
  Future<bool> executer(GesteGuidage geste, Map<String, Object?> args) async {
    if (!_session.noterOrdre()) {
      _journal('assist.ordre_refuse', <String, Object?>{
        'geste': geste.name,
        'etat': _session.etat.name,
      });
      return false;
    }

    // La DÉSIGNATION ne touche à rien : elle éclaire et elle écrit.
    // Elle n'a donc pas besoin de l'exécuteur, et marche même sur une
    // plateforme qui n'en a pas installé.
    if (geste == GesteGuidage.designer) {
      _designation = Designation(
        cible: '${args['cible'] ?? ''}',
        phrase: '${args['phrase'] ?? ''}',
      );
      notifyListeners();
      _journal('assist.designe', <String, Object?>{'cible': _designation!.cible});
      return true;
    }
    if (geste == GesteGuidage.effacer) {
      _designation = null;
      notifyListeners();
      return true;
    }

    final AssistanceExecuteur? e = _executeur;
    if (e == null) {
      _journal('assist.sans_executeur', <String, Object?>{'geste': geste.name});
      return false;
    }

    bool ok = false;
    try {
      switch (geste) {
        case GesteGuidage.ouvrirEcran:
          ok = await e.ouvrirEcran('${args['nom'] ?? ''}');
          break;
        case GesteGuidage.ouvrirCategorie:
          ok = await e.ouvrirCategorie('${args['nom'] ?? ''}');
          break;
        case GesteGuidage.ouvrirChaine:
          ok = await e.ouvrirChaine('${args['id'] ?? ''}');
          break;
        case GesteGuidage.basculerFavori:
          ok = await e.basculerFavori('${args['id'] ?? ''}');
          break;
        case GesteGuidage.retour:
          ok = await e.retour();
          break;
        case GesteGuidage.designer:
        case GesteGuidage.effacer:
          // Traités plus haut — ils ne descendent jamais jusqu'ici.
          ok = true;
          break;
      }
    } catch (err) {
      //  UN GESTE QUI JETTE NE DOIT PAS TUER LA SESSION. Le client
      //  verrait l'app se figer pendant qu'on l'aide : c'est le pire
      //  moment pour planter.
      ok = false;
      _journal('assist.geste_echoue', <String, Object?>{
        'geste': geste.name,
        'err': err.toString(),
      });
    }
    _journal('assist.geste', <String, Object?>{'geste': geste.name, 'ok': ok});
    return ok;
  }

  /// Où en est le client, pour que le support ne pilote pas à
  /// l'aveugle. Vide si aucun exécuteur.
  String ecranCourant() => _executeur?.ecranCourant() ?? '';

  /// TOUT CE QUE FAIT L'ASSISTANCE EST ÉCRIT dans la boîte noire.
  ///
  ///  Pas pour nous : pour LE CLIENT. Le jour où il demande « qu'est-ce
  ///  que vous avez fait sur mon appareil ? », la réponse existe, datée,
  ///  et elle ne dépend pas de la mémoire du support.
  void _journal(String evenement, Map<String, Object?> ctx) {
    StructuredLogger.instance.info(
      domain: 'assistance',
      event: evenement,
      ctx: ctx,
    );
  }

  @visibleForTesting
  void reinitialiserPourTest() {
    _session.arreterParClient();
    _designation = null;
    _executeur = null;
  }
}
