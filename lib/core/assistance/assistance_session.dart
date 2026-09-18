// =========================================================
//  assistance_session.dart — « entrer dans l'app pour lui montrer »
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026), en deux temps :
//
//    « Je veux dans le panel entrer dans le téléphone d'un client,
//      S'IL ME PERMET. J'appuie sur mon ordinateur et ça s'appuie dans
//      son téléphone. Je lui montre : il faut appuyer comme ça. »
//
//    « Relie ça comme Klarna : entrer dans l'app pour lui montrer des
//      trucs. »
//
//  Puis, quand j'avais compris trop étroit (« le support désigne, le
//  client appuie »), il a corrigé, et c'est SA correction qui fait foi :
//
//    « Non, non, moi je veux entrer RÉELLEMENT. Un client me dit : sur
//      ma TV je ne trouve pas les favoris. Je lui dis : regarde ta
//      télé. Et j'appuie — chaîne, favoris, tout. Je lui montre tout. »
//
//  Donc le support CONDUIT l'app du client, et le client regarde son
//  propre écran bouger. Ce n'est pas une recopie d'écran (personne ne
//  filme son téléphone) : c'est SON application qui reçoit les mêmes
//  ordres que s'il appuyait lui-même.
//
//  CE QUI REND ÇA ACCEPTABLE N'EST PAS DE SE RETENIR D'AGIR — c'est
//  que le client VOIT tout, sur son propre écran, et qu'il peut couper
//  à la seconde. Un support qui agit sous les yeux du client, avec un
//  bandeau permanent et un bouton d'arrêt, est franc. Un support qui
//  agirait en douce ne le serait pas, même en faisant moins.
//
//  ---------------------------------------------------------
//  « S'IL ME PERMET » — CE FICHIER NE FAIT QUE ÇA
//  ---------------------------------------------------------
//  Le propriétaire l'a dit lui-même, et c'est la bonne façon de le
//  construire : rien ne commence sans que le client ait dit oui.
//
//  Ce fichier est la machine à états du consentement, et RIEN
//  D'AUTRE : pas de réseau, pas de Flutter, horloge injectée. Il tient
//  les règles qui ne doivent jamais dépendre de l'humeur d'un écran :
//
//   1. AUCUNE SESSION SANS UN OUI EXPLICITE. Jamais un « qui ne dit
//      rien consent » : une demande sans réponse EXPIRE, elle ne
//      s'accepte pas toute seule.
//
//   2. LE CLIENT PEUT TOUJOURS ARRÊTER, à la seconde, sans rien
//      demander à personne. Il n'existe aucun état d'où il ne peut pas
//      sortir.
//
//   3. LA SESSION EXPIRE D'ELLE-MÊME. Une assistance oubliée ouverte
//      est une assistance qui regarde. Deux limites : un silence trop
//      long ([inactiviteMax]) et une durée totale ([dureeMax]) que rien
//      ne prolonge — même un support très actif finit par être coupé.
//
//   4. UNE SEULE À LA FOIS. Une deuxième demande pendant une session
//      est refusée, pas empilée : le client saurait plus qui le guide.
//
//  ---------------------------------------------------------
//  LES DEUX SEULES CHOSES QUE CE MODE N'AUTORISE PAS
//  ---------------------------------------------------------
//  Le support conduit l'app : il ouvre les écrans, met un favori, entre
//  dans une catégorie, choisit une chaîne. Tout ce que le client ferait
//  lui-même, et le client le voit se faire.
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
//  revendeur, et laissent une trace. Tout le reste, oui : c'est ce que
//  le propriétaire a demandé, et c'est son produit.
// =========================================================

/// Où en est l'assistance sur CET appareil.
enum EtatAssistance {
  /// Rien en cours. L'état normal, et celui vers lequel tout retombe.
  inactive,

  /// Le support a demandé ; le client n'a pas encore répondu. L'app
  /// affiche la question. Sans réponse, ça expire — voir [attenteMax].
  demandee,

  /// Le client a dit OUI. Le guidage est possible, et un bandeau reste
  /// affiché pendant tout ce temps.
  active,
}

/// Pourquoi une session s'est terminée. Sert à DIRE au client ce qui
/// s'est passé — « ça s'est arrêté tout seul » sans raison inquiète.
enum FinAssistance {
  /// Le client a refusé la demande.
  refusee,

  /// Le client a arrêté la session en cours.
  arreteeParClient,

  /// Le support a rendu la main.
  arreteeParSupport,

  /// Personne n'a répondu à la demande.
  demandeExpiree,

  /// Trop longtemps sans rien faire.
  silence,

  /// Durée maximale atteinte.
  tempsEcoule,
}

/// Combien de temps une demande reste affichée avant de s'effacer.
///
///  Assez pour que le client pose son café et lise ; assez court pour
///  qu'une demande oubliée à l'écran ne serve pas de « oui » plus tard,
///  quand il aura oublié qui la lui avait posée.
const Duration attenteMax = Duration(seconds: 90);

/// Silence au-delà duquel on coupe. Un support qui ne fait plus rien
/// n'a plus de raison d'avoir la main.
const Duration inactiviteMax = Duration(minutes: 10);

/// Durée totale, que RIEN ne prolonge. Une assistance qui dure une
/// demi-heure n'est plus une assistance.
const Duration dureeMax = Duration(minutes: 30);

/// La machine à états du consentement. Pure, horloge injectée.
class AssistanceSession {
  AssistanceSession({DateTime Function()? horloge})
      : _horloge = horloge ?? DateTime.now;

  final DateTime Function() _horloge;

  EtatAssistance _etat = EtatAssistance.inactive;
  DateTime? _demandeeA;
  DateTime? _accepteeA;
  DateTime? _dernierOrdre;
  String _support = '';
  FinAssistance? _derniereFin;

  EtatAssistance get etat => _etat;

  /// Qui demande / guide, tel qu'on l'affiche au client. Vide hors
  /// session. On ne montre JAMAIS une session anonyme : « quelqu'un
  /// veut prendre la main » n'est pas une question à laquelle on peut
  /// répondre.
  String get support => _support;

  /// Pourquoi la dernière session s'est terminée. `null` si aucune.
  FinAssistance? get derniereFin => _derniereFin;

  /// Le guidage est-il permis à cet instant ? C'est la SEULE question
  /// que le reste de l'app doit poser.
  bool get guidagePermis => _etat == EtatAssistance.active;

  /// LE SUPPORT DEMANDE. Renvoie `false` si on ne peut pas — déjà une
  /// demande en cours, ou déjà une session : on ne fait pas la queue.
  bool demander(String support) {
    _expirerSiNecessaire();
    if (_etat != EtatAssistance.inactive) return false;
    final String nom = support.trim();
    // Une demande sans nom ne se pose pas : le client doit savoir QUI.
    if (nom.isEmpty) return false;
    _support = nom;
    _demandeeA = _horloge();
    _etat = EtatAssistance.demandee;
    return true;
  }

  /// LE CLIENT DIT OUI. Renvoie `false` s'il n'y avait rien à accepter
  /// (demande expirée entre-temps, par exemple) — et dans ce cas AUCUNE
  /// session ne démarre. Un « oui » qui arrive après l'expiration ne
  /// rattrape rien : c'est une réponse à une question qui n'est plus
  /// posée.
  bool accepter() {
    _expirerSiNecessaire();
    if (_etat != EtatAssistance.demandee) return false;
    final DateTime t = _horloge();
    _accepteeA = t;
    _dernierOrdre = t;
    _etat = EtatAssistance.active;
    _derniereFin = null;
    return true;
  }

  /// LE CLIENT DIT NON.
  void refuser() => _terminer(FinAssistance.refusee);

  /// LE CLIENT ARRÊTE une session en cours. Toujours possible : c'est
  /// la règle n°2, et elle n'a pas d'exception.
  void arreterParClient() => _terminer(FinAssistance.arreteeParClient);

  /// LE SUPPORT rend la main.
  void arreterParSupport() => _terminer(FinAssistance.arreteeParSupport);

  /// Un ordre de guidage vient d'arriver. Renvoie `false` si le guidage
  /// n'est PAS permis — l'appelant doit alors ignorer l'ordre, pas
  /// demander une confirmation ni « essayer quand même ».
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
    final Duration parDuree = dureeMax - t.difference(_accepteeA!);
    final Duration parSilence = inactiviteMax - t.difference(_dernierOrdre!);
    final Duration restant =
        parDuree < parSilence ? parDuree : parSilence;
    return restant.isNegative ? Duration.zero : restant;
  }

  void _terminer(FinAssistance raison) {
    if (_etat == EtatAssistance.inactive) return;
    _etat = EtatAssistance.inactive;
    _derniereFin = raison;
    _demandeeA = null;
    _accepteeA = null;
    _dernierOrdre = null;
    _support = '';
  }

  /// Le temps fait son travail, sans que personne n'ait à y penser.
  void _expirerSiNecessaire() {
    final DateTime t = _horloge();
    if (_etat == EtatAssistance.demandee) {
      if (t.difference(_demandeeA!) >= attenteMax) {
        _terminer(FinAssistance.demandeExpiree);
      }
      return;
    }
    if (_etat == EtatAssistance.active) {
      if (t.difference(_accepteeA!) >= dureeMax) {
        _terminer(FinAssistance.tempsEcoule);
        return;
      }
      if (t.difference(_dernierOrdre!) >= inactiviteMax) {
        _terminer(FinAssistance.silence);
      }
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

  /// Éclaire un élément et affiche une phrase (« c'est ici »). Utile
  /// APRÈS avoir montré : le client refait tout seul.
  designer,

  /// Efface la désignation en cours.
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
    case 'designer':
      return GesteGuidage.designer;
    case 'effacer':
      return GesteGuidage.effacer;
    default:
      return null;
  }
}
