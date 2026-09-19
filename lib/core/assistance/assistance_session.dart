// =========================================================
//  assistance_session.dart — « entrer dans l'app pour lui montrer »
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026), en deux temps :
//
//    « Je veux dans le panel entrer dans le téléphone d'un client.
//      J'appuie sur mon ordinateur et ça s'appuie dans son téléphone.
//      Je lui montre : il faut appuyer comme ça. »
//
//    « Non, non, moi je veux entrer RÉELLEMENT. Un client me dit : sur
//      ma TV je ne trouve pas les favoris. Je lui dis : regarde ta
//      télé. Et j'appuie — chaîne, favoris, tout. Je lui montre tout. »
//
//  Puis, le 19/09/2026, après avoir essayé sur une vraie box et vu
//  trois « refusé » d'affilée parce que personne n'avait répondu à la
//  question posée sur la télé :
//
//    « Je veux que ça soit automatique. »
//
//  ---------------------------------------------------------
//  CE QUE « AUTOMATIQUE » A CHANGÉ, ET CE QUE ÇA N'A PAS CHANGÉ
//  ---------------------------------------------------------
//  AVANT : le support demandait, une question s'affichait sur la télé,
//  et RIEN ne partait tant que le client n'avait pas appuyé sur « Oui ».
//  Dans la vraie vie du support, ça ne marche pas : le client est au
//  téléphone, il tient son combiné, il ne regarde pas sa télécommande,
//  et il dit « oui oui vas-y » à l'oreille du support — pas à son
//  écran. Le support, lui, voit « refusé » et ne comprend pas.
//
//  MAINTENANT : la session s'ouvre TOUT DE SUITE. Le premier geste du
//  support l'ouvre, même s'il n'a rien cliqué avant.
//
//  CE QUI N'A PAS BOUGÉ D'UN MILLIMÈTRE, et ne bougera pas :
//
//   1. LE CLIENT VOIT. Dès la première seconde, un bandeau rouge
//      s'installe en haut de son écran, avec le NOM de qui le guide.
//      Il ne se réduit pas, il ne se range pas au bout de 5 secondes.
//      Supprimer la question était un choix de confort ; supprimer le
//      bandeau serait entrer chez quelqu'un en cachette, et c'est non.
//
//   2. LE CLIENT PEUT ARRÊTER, à la seconde, sans rien demander à
//      personne. Le bouton est DANS le bandeau, donc toujours là.
//
//   3. ÇA S'ARRÊTE TOUT SEUL. Un silence trop long ([inactiviteMax])
//      ou une durée totale atteinte ([dureeMax]) ferment la session,
//      que tout le monde ait oublié ou non.
//
//   4. UNE SEULE À LA FOIS. Deux supports ne conduisent pas la même
//      app : le client ne saurait plus qui le guide.
//
//  Autrement dit : on a retiré la PORTE, pas les FENÊTRES. Le mode
//  reste franc — ce qui rend une assistance honnête, ce n'est pas de
//  se retenir d'agir, c'est que la personne voie tout et puisse
//  couper. Un support qui agit sous les yeux du client, avec un
//  bandeau permanent et une sortie à portée de pouce, est franc. Un
//  support invisible ne le serait pas, même en faisant moins.
//
//  ---------------------------------------------------------
//  LES DEUX SEULES CHOSES QUE CE MODE N'AUTORISE PAS
//  ---------------------------------------------------------
//  Le support conduit l'app : il ouvre les écrans, met un favori,
//  montre du doigt. Tout ce que le client ferait lui-même.
//
//  Deux exceptions, et elles ne sont pas négociables :
//
//   • RIEN QUI ENGAGE DE L'ARGENT. Un paiement, un achat, un
//     renouvellement ne se valident pas à distance : ça se décide, ça
//     ne se montre pas.
//   • RIEN QUI CHANGE LES CLÉS DE LA MAISON — mot de passe, code
//     parental. Le support n'a pas à toucher ce avec quoi le client se
//     protège, y compris de nous.
//
//  Ces deux-là passent par les routes du panel, sous le nom du
//  revendeur, et laissent une trace. Tout le reste, oui.
//
//  ---------------------------------------------------------
//  CE FICHIER EST PUR
//  ---------------------------------------------------------
//  Pas de réseau, pas de Flutter, horloge injectée. C'est la machine à
//  états, et rien d'autre : les règles de temps ne doivent jamais
//  dépendre de l'humeur d'un écran.
// =========================================================

/// Où en est l'assistance sur CET appareil.
///
///  DEUX ÉTATS, PAS TROIS. L'état « demandée » (la question posée, la
///  réponse attendue) a été retiré le 19/09/2026 — voir l'en-tête. Le
///  guidage ne connaît plus que deux situations : personne, ou
///  quelqu'un, et le client le voit dans les deux cas.
enum EtatAssistance {
  /// Rien en cours. L'état normal, et celui vers lequel tout retombe.
  inactive,

  /// Un support conduit l'app. Un bandeau reste affiché pendant tout
  /// ce temps, et le client peut couper à la seconde.
  active,
}

/// Pourquoi une session s'est terminée. Sert à DIRE au client ce qui
/// s'est passé — « ça s'est arrêté tout seul » sans raison inquiète.
enum FinAssistance {
  /// Le client a arrêté la session en cours.
  arreteeParClient,

  /// Le support a rendu la main.
  arreteeParSupport,

  /// Trop longtemps sans rien faire.
  silence,

  /// Durée maximale atteinte.
  tempsEcoule,
}

/// Silence au-delà duquel on coupe. Un support qui ne fait plus rien
/// n'a plus de raison d'avoir la main.
const Duration inactiviteMax = Duration(minutes: 10);

/// Durée totale, que RIEN ne prolonge. Une assistance qui dure une
/// demi-heure n'est plus une assistance.
const Duration dureeMax = Duration(minutes: 30);

/// Combien de temps le NON du client tient, après qu'il a appuyé sur
/// « Arrêter ».
///
///  ---------------------------------------------------------
///  POURQUOI CE DÉLAI EXISTE (19/09/2026)
///  ---------------------------------------------------------
///  Tant que la session commençait par une question, « Arrêter »
///  suffisait : pour revenir, il fallait reposer la question, et le
///  client pouvait dire non.
///
///  Depuis que la prise est automatique, ce n'est plus vrai. Sans ce
///  délai, le client appuie sur « Arrêter », le support reclique une
///  seconde plus tard, et le bandeau revient. Le bouton serait décoratif
///  — et un bouton d'arrêt décoratif est pire que pas de bouton du tout,
///  parce qu'il fait croire à une sortie qui n'existe pas.
///
///  Deux minutes : assez pour que le NON compte et se remarque,
///  assez court pour qu'un client qui a coupé par erreur ne reste pas
///  bloqué pendant que le support l'a au téléphone.
///
///  CE DÉLAI NE S'APPLIQUE QU'AU NON DU CLIENT. Quand c'est le SUPPORT
///  qui rend la main, il peut reprendre tout de suite : il ne s'est
///  rien refusé à lui-même.
const Duration repitApresArret = Duration(minutes: 2);

/// La machine à états de l'assistance. Pure, horloge injectée.
class AssistanceSession {
  AssistanceSession({DateTime Function()? horloge})
      : _horloge = horloge ?? DateTime.now;

  final DateTime Function() _horloge;

  EtatAssistance _etat = EtatAssistance.inactive;
  DateTime? _ouverteA;
  DateTime? _dernierOrdre;
  String _support = '';
  FinAssistance? _derniereFin;

  /// Jusqu'à quand le NON du client tient. Voir [repitApresArret].
  DateTime? _repitJusqua;

  EtatAssistance get etat => _etat;

  /// Qui guide, tel qu'on l'affiche au client. Vide hors session.
  ///
  ///  ON NE GUIDE JAMAIS ANONYMEMENT. Un bandeau qui dirait « quelqu'un
  ///  vous aide » est plus inquiétant qu'utile : le client ne peut ni
  ///  reconnaître la personne qu'il a au téléphone, ni se plaindre de
  ///  celle qu'il n'a pas appelée. C'est pourquoi [prendre] refuse un
  ///  nom vide.
  String get support => _support;

  /// Pourquoi la dernière session s'est terminée. `null` si aucune.
  FinAssistance? get derniereFin => _derniereFin;

  /// Le guidage est-il permis à cet instant ? C'est la SEULE question
  /// que le reste de l'app doit poser.
  bool get guidagePermis => _etat == EtatAssistance.active;

  /// Le client vient-il de couper ? Pendant [repitApresArret], son NON
  /// tient et aucune session ne peut s'ouvrir. Sert au panel, pour dire
  /// au support pourquoi son bouton ne répond pas — sinon il croit à
  /// une panne et appuie dix fois.
  bool get clientARefuse {
    final DateTime? fin = _repitJusqua;
    return fin != null && _horloge().isBefore(fin);
  }

  /// LE SUPPORT PREND LA MAIN — tout de suite, sans question posée.
  ///
  ///  Renvoie `false` dans deux cas seulement :
  ///   • une session est DÉJÀ ouverte (règle n°4 : une seule à la fois,
  ///     on ne fait pas la queue et on ne double pas le pilote) ;
  ///   • le nom est vide (voir [support] : on ne guide pas masqué).
  ///
  ///  Appeler [prendre] pendant sa PROPRE session renvoie aussi
  ///  `false` — et c'est sans conséquence : la session continue, rien
  ///  n'est réinitialisé. Un support qui reclique sur « Prendre la
  ///  main » ne doit pas remettre le compteur de 30 minutes à zéro,
  ///  sinon la limite totale ne serait plus une limite.
  bool prendre(String support) {
    _expirerSiNecessaire();
    if (_etat != EtatAssistance.inactive) return false;
    // LE NON DU CLIENT TIENT. Voir [repitApresArret] : sans ça, son
    // bouton « Arrêter » ne serait qu'une pause d'une seconde.
    if (clientARefuse) return false;
    final String nom = support.trim();
    if (nom.isEmpty) return false;
    final DateTime t = _horloge();
    _support = nom;
    _ouverteA = t;
    _dernierOrdre = t;
    _etat = EtatAssistance.active;
    _derniereFin = null;
    return true;
  }

  /// LE CLIENT ARRÊTE. Toujours possible : c'est la règle n°2, et elle
  /// n'a pas d'exception.
  ///
  ///  Son NON tient ensuite pendant [repitApresArret], MÊME s'il n'y
  ///  avait pas de session ouverte à ce moment-là. C'est voulu : un
  ///  client qui appuie sur « Arrêter » pendant que le bandeau
  ///  disparaît tout seul a quand même dit non, et son geste doit
  ///  compter autant.
  void arreterParClient() {
    _repitJusqua = _horloge().add(repitApresArret);
    _terminer(FinAssistance.arreteeParClient);
  }

  /// LE SUPPORT rend la main.
  void arreterParSupport() => _terminer(FinAssistance.arreteeParSupport);

  /// Un ordre de guidage vient d'arriver. Renvoie `false` si le guidage
  /// n'est PAS permis — l'appelant doit alors ignorer l'ordre, pas
  /// « essayer quand même ».
  bool noterOrdre() {
    _expirerSiNecessaire();
    if (_etat != EtatAssistance.active) return false;
    _dernierOrdre = _horloge();
    return true;
  }

  /// À appeler avant toute lecture d'état par l'interface (un widget se
  /// reconstruit souvent ; c'est le moment le plus sûr pour vérifier
  /// que le temps n'a pas déjà tout terminé).
  void rafraichir() => _expirerSiNecessaire();

  /// Combien de temps il reste à la session. `null` hors session.
  /// Sert au bandeau : le client voit que ça va s'arrêter tout seul,
  /// ce qui est rassurant et vrai.
  Duration? get tempsRestant {
    _expirerSiNecessaire();
    if (_etat != EtatAssistance.active) return null;
    final DateTime t = _horloge();
    final Duration parDuree = dureeMax - t.difference(_ouverteA!);
    final Duration parSilence = inactiviteMax - t.difference(_dernierOrdre!);
    final Duration restant = parDuree < parSilence ? parDuree : parSilence;
    return restant.isNegative ? Duration.zero : restant;
  }

  /// Remet la session à neuf — Y COMPRIS le répit du client.
  ///
  ///  Réservé aux tests. `arreterParClient()` ne suffirait pas : il
  ///  pose justement le répit de deux minutes, et le test suivant ne
  ///  pourrait plus rien ouvrir. Un test qui échoue pour une raison
  ///  qui n'a rien à voir avec lui fait perdre plus de temps que le
  ///  bug qu'il cherchait.
  void reinitialiser() {
    _etat = EtatAssistance.inactive;
    _derniereFin = null;
    _ouverteA = null;
    _dernierOrdre = null;
    _support = '';
    _repitJusqua = null;
  }

  void _terminer(FinAssistance raison) {
    if (_etat == EtatAssistance.inactive) return;
    _etat = EtatAssistance.inactive;
    _derniereFin = raison;
    _ouverteA = null;
    _dernierOrdre = null;
    _support = '';
  }

  /// Le temps fait son travail, sans que personne n'ait à y penser.
  void _expirerSiNecessaire() {
    if (_etat != EtatAssistance.active) return;
    final DateTime t = _horloge();
    if (t.difference(_ouverteA!) >= dureeMax) {
      _terminer(FinAssistance.tempsEcoule);
      return;
    }
    if (t.difference(_dernierOrdre!) >= inactiviteMax) {
      _terminer(FinAssistance.silence);
    }
  }
}

/// Ce que le support peut faire faire à l'app pendant une session.
///
///  LISTE FERMÉE, ET C'EST VOULU — mais large : c'est bien de CONDUIRE
///  l'app qu'il s'agit. « Je lui montre les favoris » veut dire ouvrir
///  l'écran des chaînes, aller dans Favoris, et mettre un favori sous
///  ses yeux.
///
///  Ce qui n'y est PAS, et n'y sera pas : payer, renouveler, changer
///  un mot de passe ou un code parental. Voir l'en-tête.
enum GesteGuidage {
  /// Ouvre un écran de l'app (chaînes, favoris, réglages, aide…). Le
  /// client voit l'écran s'ouvrir, comme s'il avait appuyé lui-même.
  ouvrirEcran,

  /// Entre dans une catégorie ou une liste précise.
  ouvrirCategorie,

  /// Met une chaîne sur l'écran du client.
  ouvrirChaine,

  /// Ajoute ou retire un favori — le geste exact de l'exemple du
  /// propriétaire.
  basculerFavori,

  /// Revient en arrière, comme la touche Retour.
  retour,

  /// REDÉMARRE L'APPLICATION (19/09/2026 au soir).
  ///
  ///  Demande du propriétaire : régler « ça marche pas » depuis le
  ///  panel, sans toucher à la box. Le redémarrage de l'app remonte les
  ///  trois quarts des blocages (lecteur figé, écran resté sur une
  ///  vieille liste) sans que le client ait à débrancher quoi que ce
  ///  soit.
  ///
  ///  C'EST L'APP QU'ON RELANCE, PAS LA BOX. Une app Android n'a pas le
  ///  droit de redémarrer l'appareil — seul le constructeur l'a. On
  ///  remet donc l'application à son écran de départ, ce qui suffit
  ///  presque toujours et ne fait perdre au client que deux secondes.
  redemarrer,

  /// RESYNCHRONISE : re-télécharge la licence et les listes.
  ///
  ///  Le geste pour « je ne vois pas la liste que tu viens de me
  ///  pousser ». Au lieu d'attendre la synchro automatique, on la
  ///  force tout de suite.
  resynchroniser,

  /// LE DOIGT DU SUPPORT, POSÉ SUR L'ÉCRAN DU CLIENT (19/09/2026).
  ///
  ///  Demande du propriétaire, mot pour mot : « il va y avoir un
  ///  simulateur de TV ou de téléphone ; où je touche, il voit où je
  ///  touche ».
  ///
  ///  Le support touche une maquette d'écran dans le panel ; un halo
  ///  apparaît au MÊME ENDROIT, en proportion, sur l'écran du client.
  ///  Les coordonnées sont donc des FRACTIONS (0 → 1), jamais des
  ///  pixels : la maquette du panel fait quelques centaines de points,
  ///  la télé du client quelques milliers, et une session peut sauter
  ///  d'un téléphone à une box. Des pixels pointeraient à côté.
  pointer,

  /// UN VRAI CLIC, PAS UN POINTAGE (19/09/2026 au soir).
  ///
  ///  Demande du propriétaire, après trois heures : « si j'appuie, ça
  ///  ne s'appuie pas, ça pointe seulement. Il faut faire comme un
  ///  professionnel. » Montrer du doigt ne suffit pas — il veut appuyer
  ///  À SA PLACE.
  ///
  ///  L'app synthétise un vrai appui (bas + haut) à la position visée,
  ///  via le moteur de gestes de Flutter : le widget sous ce point le
  ///  reçoit EXACTEMENT comme si le client avait touché l'écran. Pas de
  ///  privilège système — on injecte dans NOTRE propre arbre, là où on
  ///  a le droit.
  taper,

  /// LA TÉLÉCOMMANDE : haut / bas / gauche / droite / OK (19/09/2026).
  ///
  ///  Demande du propriétaire, en voyant l'écran de sa box dans le panel :
  ///  « je dois avoir un bouton pour descendre ou monter ». Sur une box,
  ///  on ne fait pas défiler avec le doigt, on DÉPLACE LE FOCUS avec les
  ///  flèches — c'est exactement ce que fait ce geste, par le mécanisme
  ///  de Flutter (`focusInDirection`). OK appuie sur l'élément qui a le
  ///  focus. Sur un téléphone, où les listes n'ont pas de focus, haut et
  ///  bas font DÉFILER (un glissement injecté).
  ///
  ///  Argument `dir` : `haut`, `bas`, `gauche`, `droite`, `ok`.
  naviguer,

  /// Affiche une phrase (« c'est ici ») dans le bandeau. Utile APRÈS
  /// avoir montré : le client refait tout seul.
  designer,

  /// Efface le halo et la phrase en cours.
  effacer,
}

/// Lit le nom d'un geste venu du réseau. Renvoie `null` si inconnu.
///
///  UN PANEL PLUS RÉCENT QUE L'APP NE DOIT RIEN LUI FAIRE FAIRE
///  D'APPROXIMATIF. Devant un mot qu'elle ne connaît pas, l'app ne
///  tente pas « le geste le plus proche » : elle ne fait rien, et le
///  support voit son ordre refusé. Deviner reviendrait à appuyer au
///  hasard sur l'écran d'un client.
GesteGuidage? lireGeste(String? nom) {
  switch (nom) {
    case 'ouvrir':
      return GesteGuidage.ouvrirEcran;
    case 'categorie':
      return GesteGuidage.ouvrirCategorie;
    case 'chaine':
      return GesteGuidage.ouvrirChaine;
    case 'favori':
      return GesteGuidage.basculerFavori;
    case 'retour':
      return GesteGuidage.retour;
    case 'redemarrer':
      return GesteGuidage.redemarrer;
    case 'resync':
      return GesteGuidage.resynchroniser;
    case 'pointeur':
      return GesteGuidage.pointer;
    case 'taper':
      return GesteGuidage.taper;
    case 'naviguer':
      return GesteGuidage.naviguer;
    case 'designer':
      return GesteGuidage.designer;
    case 'effacer':
      return GesteGuidage.effacer;
    default:
      return null;
  }
}
