// =========================================================
//  assistance_controller.dart — le chef d'orchestre du mode assistance
// =========================================================
//  Il tient la session (cf. assistance_session.dart) et fait exécuter
//  les gestes. Il ne SAIT PAS ouvrir un écran : il le demande à un
//  exécuteur que l'application installe au démarrage.
//
//  POURQUOI CETTE SÉPARATION. Les règles de la session sont des règles
//  de maison, identiques partout. Les écrans, non : la box et le
//  téléphone n'ont pas les mêmes. Si ce fichier connaissait les écrans
//  TV, le cœur de l'app dépendrait d'une fonctionnalité — et le
//  téléphone hériterait d'un menu qu'il n'a pas.
//
//  ---------------------------------------------------------
//  LA PRISE AUTOMATIQUE (19/09/2026)
//  ---------------------------------------------------------
//  Le propriétaire a essayé sur une vraie box, a appuyé sur
//  « Chaînes », et a lu trois fois « refusé ». Il avait raison d'être
//  agacé : rien n'était cassé, mais rien ne marchait non plus. La
//  question posée sur la télé attendait une réponse que le client,
//  combiné à l'oreille, ne donnait jamais.
//
//    « Je veux que ça soit automatique. »
//
//  Donc : LE PREMIER GESTE OUVRE LA SESSION. Le support n'a plus à
//  cliquer « Prendre la main » avant — il peut, mais il n'a plus à.
//  C'est [executer] qui s'en charge, à une condition ferme : le geste
//  doit porter le NOM du support. Sans nom, pas de session, donc pas
//  de geste : un bandeau qui dirait « quelqu'un vous aide » serait
//  plus inquiétant qu'utile.
//
//  ---------------------------------------------------------
//  CE QUI NE PASSE JAMAIS PAR LA PORTE
//  ---------------------------------------------------------
//  [executer] reste LE POINT UNIQUE DE PASSAGE : aucun geste n'atteint
//  l'écran d'un client par un autre chemin. Ce qui a changé, c'est ce
//  qu'il fait quand la session est fermée — il l'ouvre au lieu de
//  refuser — pas le fait que tout passe par lui.
//
//  ---------------------------------------------------------
//  « REFUSÉ » N'EST PAS UNE RAISON
//  ---------------------------------------------------------
//  Avant le 19/09, tout échec de geste remontait au panel sous un seul
//  mot : `refuse_ou_echoue`. Le support lisait ça et ne savait pas
//  s'il fallait rappeler le client, redémarrer son app, ou changer de
//  bouton. C'est le défaut que ce dépôt traque depuis des mois : un
//  message qui affirme moins que ce qu'on a mesuré.
//
//  [executer] rend donc un [ResultatGeste] qui PORTE LA CAUSE, et
//  l'exécuteur de chaque plateforme fait pareil.
// =========================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../observability/structured_logger.dart';
import 'assistance_session.dart';

/// Ce qu'un geste a VRAIMENT donné.
///
///  `ok == true` veut dire : ça a eu lieu sur l'écran du client. Pas
///  « c'est parti », pas « ça devrait marcher ». Un support qui croit
///  avoir cliqué alors que rien n'a bougé appuie dix fois, et le client
///  voit son app partir dans tous les sens pendant qu'on lui explique
///  que c'est normal.
@immutable
class ResultatGeste {
  const ResultatGeste.fait()
      : ok = true,
        raison = null;

  /// [raison] est un IDENTIFIANT court et stable (`ecran_inconnu`,
  /// `app_en_arriere_plan`…), pas une phrase. Le panel le traduit pour
  /// l'humain qui lit ; l'app, elle, ne fabrique pas de français qui
  /// pourrait mentir une fois traduit.
  const ResultatGeste.refuse(this.raison) : ok = false;

  final bool ok;
  final String? raison;
}

/// Ce que l'application doit savoir faire pour être guidable.
///
///  Implémenté par chaque plateforme (`tv_assistance_executeur.dart`
///  pour la box).
///
///  CHAQUE MÉTHODE REND `null` SI LE GESTE A EU LIEU, sinon une RAISON
///  courte. C'est volontairement l'inverse d'un `bool` : un booléen
///  n'avait que deux valeurs, et « false » a fini par vouloir dire
///  sept choses différentes à la fois.
abstract class AssistanceExecuteur {
  /// Ouvre un écran désigné par un nom stable (« favoris »,
  /// « chaines », « reglages »…).
  Future<String?> ouvrirEcran(String nom);

  /// Entre dans une catégorie / une liste.
  Future<String?> ouvrirCategorie(String nom);

  /// Met une chaîne à l'écran.
  Future<String?> ouvrirChaine(String id);

  /// Ajoute ou retire un favori.
  Future<String?> basculerFavori(String id);

  /// Revient en arrière, comme la touche Retour.
  Future<String?> retour();

  /// Où en est le client, en clair (« Chaînes › Favoris »). Sert à ce
  /// que le support ne pilote pas à l'aveugle.
  String ecranCourant();
}

/// Ce que l'app montre à l'écran du client : un halo, une phrase, ou
/// les deux.
@immutable
class Designation {
  const Designation({
    required this.cible,
    required this.phrase,
    this.x,
    this.y,
  });

  /// Nom stable d'un élément à éclairer. Vide = rien d'éclairé par son
  /// nom (on peut quand même avoir un halo par coordonnées).
  final String cible;

  /// « C'est ici », « Appuie sur OK »…
  final String phrase;

  /// POSITION DU DOIGT DU SUPPORT, EN FRACTION DE L'ÉCRAN (0 → 1).
  ///
  ///  `null` = pas de halo, seulement la phrase. Des fractions et pas
  ///  des pixels : la maquette du panel et la télé du client n'ont ni
  ///  la même taille ni la même forme, et une session peut passer d'un
  ///  téléphone à une box. Voir [GesteGuidage.pointer].
  final double? x;
  final double? y;

  bool get aUnHalo => x != null && y != null;
}

/// Combien de temps le halo reste posé avant de s'effacer tout seul.
///
///  Un doigt ne reste pas pointé indéfiniment. Passé ce délai, le halo
///  ne montre plus rien d'utile — il montre où le support regardait il
///  y a une minute, ce qui est pire que rien : le client suivrait un
///  doigt qui n'est plus là. La phrase, elle, survit : elle reste vraie
///  plus longtemps (« appuie sur OK » ne se périme pas).
const Duration haloDuree = Duration(seconds: 12);

class AssistanceController extends ChangeNotifier {
  AssistanceController._();
  static final AssistanceController instance = AssistanceController._();

  final AssistanceSession _session = AssistanceSession();
  AssistanceExecuteur? _executeur;
  Designation? _designation;
  Timer? _effaceHalo;

  /// L'application installe son exécuteur au démarrage. Sans lui, les
  /// gestes de NAVIGATION échouent PROPREMENT (refusés avec la raison
  /// `plateforme_sans_executeur`), tandis que le halo et la phrase,
  /// eux, marchent quand même : ils ne touchent à aucun écran.
  void installerExecuteur(AssistanceExecuteur e) => _executeur = e;

  AssistanceSession get session => _session;
  Designation? get designation => _designation;

  EtatAssistance get etat {
    _session.rafraichir();
    // Le temps a pu fermer la session pendant qu'on ne regardait pas.
    // Si c'est le cas, le halo doit partir avec elle : un doigt posé
    // sans bandeau serait un guidage invisible.
    if (_session.etat == EtatAssistance.inactive && _designation != null) {
      _designation = null;
      _effaceHalo?.cancel();
      _effaceHalo = null;
    }
    return _session.etat;
  }

  String get support => _session.support;
  Duration? get tempsRestant => _session.tempsRestant;

  /// LE SUPPORT PREND LA MAIN, explicitement (bouton du panel).
  ///
  ///  Renvoie `false` si une session est déjà ouverte, ou si le nom est
  ///  vide. Ce n'est plus indispensable — [executer] ouvre la session
  ///  toute seule — mais le bouton reste utile : il pose le bandeau
  ///  chez le client AVANT qu'on touche à quoi que ce soit, ce qui est
  ///  la façon polie de commencer.
  bool prendreLaMain(String support) {
    final bool ok = _session.prendre(support);
    if (ok) {
      _journal('assist.prise', <String, Object?>{'support': support});
      notifyListeners();
    }
    return ok;
  }

  /// LE CLIENT COUPE. Toujours possible, à la seconde.
  void arreterParClient() {
    _session.arreterParClient();
    _effacerDesignation();
    _journal('assist.arretee_client', const <String, Object?>{});
    notifyListeners();
  }

  /// Le support rend la main.
  void arreterParSupport() {
    _session.arreterParSupport();
    _effacerDesignation();
    _journal('assist.arretee_support', const <String, Object?>{});
    notifyListeners();
  }

  /// LE POINT UNIQUE DE PASSAGE. Aucun geste n'atteint l'écran d'un
  /// client sans traverser cette méthode.
  ///
  ///  [support] sert à OUVRIR la session si elle ne l'est pas encore
  ///  (la prise automatique du 19/09). Vide + session fermée = refus
  ///  net, avec la raison `sans_nom_de_support` : on ne guide pas
  ///  masqué.
  Future<ResultatGeste> executer(
    GesteGuidage geste,
    Map<String, Object?> args, {
    String support = '',
  }) async {
    //  UNE SESSION OUVERTE N'EST PAS UNE SESSION OUVERTE À TOUT LE
    //  MONDE (trou trouvé par les tests le 19/09/2026).
    //
    //  `noterOrdre()` répond « oui, une session est en cours » — il ne
    //  regarde pas QUI. Sans la garde ci-dessous, un second revendeur
    //  pouvait conduire l'app pendant que le bandeau du client affichait
    //  le nom du premier. Le client aurait vu son écran bouger au nom
    //  de quelqu'un qui n'y était plus pour rien.
    //
    //  UN GESTE SANS NOM PASSE QUAND MÊME, et c'est délibéré : les
    //  panels d'avant le 19/09 n'envoyaient le nom qu'à l'ouverture.
    //  Les refuser couperait le support à tout panel pas encore
    //  rechargé. Ce qu'on bloque, c'est le geste qui se présente sous
    //  un AUTRE nom — le cas réel, deux revendeurs sur la même box.
    final String qui = support.trim();
    if (_session.guidagePermis &&
        qui.isNotEmpty &&
        qui != _session.support) {
      _journal('assist.ordre_autre_support', <String, Object?>{
        'geste': geste.name,
        'demande_par': qui,
        'en_cours_pour': _session.support,
      });
      return const ResultatGeste.refuse('autre_session_en_cours');
    }

    if (!_session.noterOrdre()) {
      //  LA SESSION N'ÉTAIT PAS OUVERTE — on l'ouvre, c'est ça
      //  « automatique ». Le bandeau rouge apparaît chez le client
      //  dans la même seconde que le geste : il ne découvre jamais un
      //  écran qui bouge tout seul sans explication.
      final String nom = support.trim();
      if (nom.isEmpty) {
        _journal('assist.ordre_sans_nom', <String, Object?>{
          'geste': geste.name,
        });
        return const ResultatGeste.refuse('sans_nom_de_support');
      }
      if (!_session.prendre(nom)) {
        //  DEUX CAS RESTANTS, ET IL FAUT LES DISTINGUER : le client
        //  vient de couper (son non tient deux minutes), ou une session
        //  est ouverte au nom de quelqu'un d'autre. Le support doit
        //  savoir lequel — dans un cas il rappelle le client, dans
        //  l'autre il attend son collègue.
        final String raison = _session.clientARefuse
            ? 'client_a_coupe'
            : 'autre_session_en_cours';
        _journal('assist.ordre_refuse', <String, Object?>{
          'geste': geste.name,
          'etat': _session.etat.name,
          'raison': raison,
        });
        return ResultatGeste.refuse(raison);
      }
      _journal('assist.prise_auto', <String, Object?>{
        'support': nom,
        'geste': geste.name,
      });
      _session.noterOrdre();
      notifyListeners();
    }

    //  MONTRER NE TOUCHE À RIEN. Le halo et la phrase n'ouvrent aucun
    //  écran : ils marchent donc même sur une plateforme qui n'a pas
    //  installé d'exécuteur (le téléphone, aujourd'hui).
    if (geste == GesteGuidage.pointer) {
      return _poserHalo(args);
    }
    if (geste == GesteGuidage.designer) {
      _designation = Designation(
        cible: '${args['cible'] ?? ''}',
        phrase: '${args['phrase'] ?? ''}',
        // On garde le halo en place s'il y en avait un : afficher une
        // phrase ne doit pas effacer le doigt qu'on vient de poser.
        x: _designation?.x,
        y: _designation?.y,
      );
      notifyListeners();
      _journal('assist.designe', <String, Object?>{
        'cible': _designation!.cible,
      });
      return const ResultatGeste.fait();
    }
    if (geste == GesteGuidage.effacer) {
      _effacerDesignation();
      notifyListeners();
      return const ResultatGeste.fait();
    }

    final AssistanceExecuteur? e = _executeur;
    if (e == null) {
      _journal('assist.sans_executeur', <String, Object?>{'geste': geste.name});
      return const ResultatGeste.refuse('plateforme_sans_executeur');
    }

    String? raison;
    try {
      switch (geste) {
        case GesteGuidage.ouvrirEcran:
          raison = await e.ouvrirEcran('${args['nom'] ?? ''}');
          break;
        case GesteGuidage.ouvrirCategorie:
          raison = await e.ouvrirCategorie('${args['nom'] ?? ''}');
          break;
        case GesteGuidage.ouvrirChaine:
          raison = await e.ouvrirChaine('${args['id'] ?? ''}');
          break;
        case GesteGuidage.basculerFavori:
          raison = await e.basculerFavori('${args['id'] ?? ''}');
          break;
        case GesteGuidage.retour:
          raison = await e.retour();
          break;
        case GesteGuidage.pointer:
        case GesteGuidage.designer:
        case GesteGuidage.effacer:
          // Traités plus haut — ils ne descendent jamais jusqu'ici.
          raison = null;
          break;
      }
    } catch (err) {
      //  UN GESTE QUI JETTE NE DOIT PAS TUER LA SESSION. Le client
      //  verrait l'app se figer pendant qu'on l'aide : c'est le pire
      //  moment pour planter.
      raison = 'exception';
      _journal('assist.geste_echoue', <String, Object?>{
        'geste': geste.name,
        'err': err.toString(),
      });
    }
    _journal('assist.geste', <String, Object?>{
      'geste': geste.name,
      'ok': raison == null,
      if (raison != null) 'raison': raison,
    });
    return raison == null
        ? const ResultatGeste.fait()
        : ResultatGeste.refuse(raison);
  }

  /// Pose le doigt du support à l'endroit qu'il a touché dans le panel.
  ResultatGeste _poserHalo(Map<String, Object?> args) {
    final double? x = _fraction(args['x']);
    final double? y = _fraction(args['y']);
    if (x == null || y == null) {
      //  ON NE DEVINE PAS UN ENDROIT. Un halo posé au hasard (au
      //  centre, en 0,0…) montrerait du doigt quelque chose que
      //  personne n'a désigné, et le client irait regarder là.
      return const ResultatGeste.refuse('position_invalide');
    }
    final String phrase = '${args['phrase'] ?? ''}';
    _designation = Designation(
      cible: '',
      // Une phrase vide n'efface pas celle d'avant : le support pose
      // souvent « c'est ici » une fois, puis déplace son doigt.
      phrase: phrase.isNotEmpty ? phrase : (_designation?.phrase ?? ''),
      x: x,
      y: y,
    );
    _armerEffacementHalo();
    notifyListeners();
    _journal('assist.pointe', <String, Object?>{'x': x, 'y': y});
    return const ResultatGeste.fait();
  }

  /// Lit une fraction d'écran. Refuse tout ce qui n'est pas dans
  /// `[0, 1]` — y compris `NaN`, que les comparaisons laisseraient
  /// passer si on écrivait la garde à l'envers.
  static double? _fraction(Object? brut) {
    final double? v = brut is num
        ? brut.toDouble()
        : double.tryParse('${brut ?? ''}');
    if (v == null || !(v >= 0 && v <= 1)) return null;
    return v;
  }

  void _armerEffacementHalo() {
    _effaceHalo?.cancel();
    _effaceHalo = Timer(haloDuree, () {
      final Designation? d = _designation;
      if (d == null || !d.aUnHalo) return;
      // Le doigt s'en va, la phrase reste — voir [haloDuree].
      _designation = d.phrase.isEmpty
          ? null
          : Designation(cible: d.cible, phrase: d.phrase);
      notifyListeners();
    });
  }

  void _effacerDesignation() {
    _effaceHalo?.cancel();
    _effaceHalo = null;
    _designation = null;
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
    // `reinitialiser()` et pas `arreterParClient()` : ce dernier pose
    // le répit de deux minutes, et le test suivant ne pourrait plus
    // rien ouvrir. Voir AssistanceSession.reinitialiser().
    _session.reinitialiser();
    _effacerDesignation();
    _executeur = null;
  }
}
