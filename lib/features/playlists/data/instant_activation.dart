// =========================================================
//  instant_activation.dart — « le panel a poussé, ça DOIT jouer »
// =========================================================
//  POURQUOI CE FICHIER EXISTE (16/09/2026).
//
//  La chaîne complète existait déjà et marchait, bout par bout : le panel
//  pousse le M3U, le Worker réveille l'appareil par WebSocket
//  (`sync` → `sources`), l'app télécharge, parse, insère, et bascule la
//  playlist en active. Puis… elle affichait la grille des catégories et
//  attendait.
//
//  Le client devait donc encore choisir une catégorie, puis une chaîne.
//  Trois gestes à la télécommande, après une activation qu'on lui avait
//  vendue comme automatique. Pour quelqu'un qui vient de payer et à qui
//  on a dit « ça se fait tout seul », c'est une promesse cassée — et le
//  revendeur, lui, ne peut pas savoir si ça a marché.
//
//  Ce module est le maillon manquant, et rien d'autre : il dit QUELLE
//  chaîne lancer, et prévient l'écran qui est à l'affiche.
//
//  ---------------------------------------------------------
//  IL NE LANCE RIEN LUI-MÊME, ET C'EST VOULU
//  ---------------------------------------------------------
//  Téléphone et TV n'ouvrent pas le lecteur de la même façon
//  (`playChannel` d'un côté, `TvPlayerScreen` de l'autre), et seul
//  l'écran monté connaît son `BuildContext`. Ce fichier ne porte donc
//  que la DÉCISION ; chaque accueil garde son ouverture à lui.
//
//  C'est la même raison qu'ailleurs dans la maison : une seule
//  implémentation de la règle, autant d'appelants qu'on veut. Le jour où
//  une copie décide autrement, le téléphone et la box lancent deux
//  chaînes différentes pour la même activation.
//
//  ---------------------------------------------------------
//  CE QU'IL NE FAIT JAMAIS
//  ---------------------------------------------------------
//  * Interrompre une lecture en cours. Si le client regarde déjà quelque
//    chose, un push du panel ne lui arrache pas l'écran — le revendeur
//    qui ajoute une 2e source ne doit pas zapper son client de force.
//    Cette garde n'est PAS ici : elle est posée à la source, dans
//    `RemoteSourceRepository.applySources`, qui ne dépose une demande que
//    si l'appareil n'avait AUCUNE chaîne avant l'import. Un seul endroit
//    juge, sinon les deux écrans finissent par juger différemment.
//  * Se déclencher deux fois pour la même activation. Un `sync all` suivi
//    d'un `sync sources` arrive couramment en rafale ; sans le jeton
//    consommé une seule fois, le lecteur s'ouvrirait en double.
//  * Choisir une chaîne adulte. Elle est légitime dans la liste, mais la
//    première image d'une activation, parfois devant toute la famille,
//    n'est pas celle-là.
// =========================================================

import 'package:flutter/foundation.dart';

import '../../channels/domain/channel.dart';

/// Ce qu'il y a à faire, une fois, dès que l'écran peut le faire.
@immutable
class DemandeLectureInstantanee {
  const DemandeLectureInstantanee({
    required this.chaine,
    required this.liste,
  });

  /// La chaîne à lancer.
  final Channel chaine;

  /// La liste complète — elle donne le zapping ⏮ / ⏭ dès la première
  /// seconde, sans quoi le client atterrit sur une chaîne dont il ne peut
  /// pas sortir autrement qu'en revenant en arrière.
  final List<Channel> liste;
}

/// Le point de rendez-vous entre l'import distant et l'écran à l'affiche.
abstract final class InstantActivation {
  /// Levé quand une source POUSSÉE PAR LE PANEL vient de charger des
  /// chaînes. Les accueils (téléphone et TV) l'écoutent.
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static DemandeLectureInstantanee? _enAttente;

  /// Dépose une demande et réveille l'écran. Appelé par
  /// `RemoteSourceRepository` après un import réussi.
  static void demander(DemandeLectureInstantanee d) {
    _enAttente = d;
    tick.value++;
  }

  /// Retire la demande — UNE SEULE FOIS. Le second appelant (rafale
  /// `sync all` + `sync sources`, ou téléphone qui a deux écrans montés)
  /// reçoit `null` et n'ouvre pas un deuxième lecteur.
  static DemandeLectureInstantanee? consommer() {
    final DemandeLectureInstantanee? d = _enAttente;
    _enAttente = null;
    return d;
  }

  /// Y a-t-il quelque chose à jouer ?
  static bool get enAttente => _enAttente != null;

  @visibleForTesting
  static void reinitialiserPourTest() {
    _enAttente = null;
    tick.value = 0;
  }
}

/// QUELLE chaîne lancer — fonction PURE, donc testable sans écran.
///
///  [demandee] est l'identifiant éventuellement désigné par le panel
///  (champ `start_channel`). S'il est fourni ET présent dans la liste, il
///  gagne : le revendeur a le dernier mot, c'est lui qui connaît son
///  client.
///
///  Sinon on prend la première chaîne NON adulte. Et si la liste n'est
///  faite que de ça — cas d'un bouquet spécialisé, qui existe — on prend
///  quand même la première : refuser de jouer serait pire que jouer ce
///  que le client a effectivement acheté.
Channel? chaineADemarrer(List<Channel> chaines, {String? demandee}) {
  if (chaines.isEmpty) return null;

  if (demandee != null && demandee.trim().isNotEmpty) {
    final String cible = demandee.trim();
    for (final Channel c in chaines) {
      if (c.id == cible) return c;
    }
    // Deuxième chance par le NOM : le panel affiche des noms, pas des
    // identifiants internes, et un revendeur tape ce qu'il voit.
    final String cibleMaj = cible.toUpperCase();
    for (final Channel c in chaines) {
      if (c.name.toUpperCase() == cibleMaj) return c;
    }
    // Introuvable → on ne bloque pas, on retombe sur la règle générale.
  }

  for (final Channel c in chaines) {
    if (c.genre != ChannelGenre.adult) return c;
  }
  return chaines.first;
}
