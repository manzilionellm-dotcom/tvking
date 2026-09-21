// =========================================================
//  tv_event_priority.dart — « Le match commence dans 30 minutes »
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026), mot pour mot :
//
//    « Il faut ajouter les notifications des grands événements, les
//      matchs, comme France 24 te signale le nouveau journal. »
//
//  Les rappels existaient déjà (`tv_program_reminders.dart`), mais ils
//  traitaient TOUT pareil : un documentaire de 3 h du matin et la
//  finale de la Coupe avaient exactement la même annonce, dans la même
//  fenêtre de dix minutes.
//
//  Or ces deux-là ne se préviennent pas de la même façon. Dix minutes
//  avant un match, le client est déjà devant sa télé ou il a raté le
//  coup d'envoi. Une demi-heure, ça laisse le temps d'appeler un ami.
//
//  ---------------------------------------------------------
//  CE FICHIER NE FAIT QU'UNE CHOSE : CLASSER UN TITRE
//  ---------------------------------------------------------
//  Une fonction PURE, sans Flutter, sans réseau, sans état. Elle prend
//  un titre d'émission et répond « match », « journal » ou « ordinaire ».
//  Rien d'autre. C'est ce qui la rend testable sans box, sans EPG et
//  sans attendre 20 h 45.
//
//  Le reste — quand balayer, quoi afficher, combien de temps — reste
//  où il était. On n'a pas déplacé la mécanique, on lui a ajouté un
//  jugement.
//
//  ---------------------------------------------------------
//  POURQUOI DES MOTS ET PAS UNE VRAIE BASE SPORTIVE
//  ---------------------------------------------------------
//  Parce que le seul texte dont on dispose à coup sûr, sur TOUS les
//  fournisseurs, c'est le titre du guide. Pas de catégorie fiable, pas
//  d'identifiant de compétition, pas d'API. Un fournisseur écrit
//  « FOOT : PSG - OM », un autre « Ligue 1 · PSG/OM », un troisième
//  « LIVE PSG vs OM ».
//
//  On reste donc volontairement SIMPLE et PRUDENT :
//   • on ne se trompe jamais en silence — au pire on classe « ordinaire »
//     et le client reçoit le rappel normal, comme avant ;
//   • on ne crie jamais pour rien : un mot trop vague (« sport »,
//     « live ») annoncerait un match toutes les heures, et une
//     notification qu'on ignore par réflexe ne vaut plus rien.
//
//  Ajouter un mot ici est sans danger. En retirer un aussi. C'est le
//  seul endroit à toucher — pas quinze `if` éparpillés dans l'écran.
// =========================================================

/// Ce que vaut une émission pour une notification.
enum TypeEvenement {
  /// Un match, une finale, un grand direct sportif.
  match,

  /// Un GRAND ÉVÉNEMENT hors sport (21/09/2026) : soirée électorale,
  /// allocution, cérémonie, Eurovision… Prévenu comme un match (30 min
  /// puis dernier appel), toutes chaînes confondues.
  evenement,

  /// Un journal, une édition d'information.
  journal,

  /// Tout le reste : le rappel normal, celui d'avant.
  ordinaire,
}

/// Mots qui désignent un MATCH, quelle que soit la façon d'écrire du
/// fournisseur. Comparaison faite sur un titre déjà mis en minuscules et
/// débarrassé de ses accents (voir [_aplatir]).
const List<String> _motsMatch = <String>[
  //  AJOUTÉS APRÈS ÉCHEC DES TESTS (18/09/2026). Ma première liste ne
  //  reconnaissait NI « FOOT : PSG - OM » NI « LIVE PSG vs OM » — les
  //  deux graphies les plus courantes des guides IPTV francophones.
  //  J'avais listé les compétitions et oublié la façon dont les gens
  //  écrivent réellement un match.
  //
  //  `'foot '` avec l'espace, jamais `'foot'` seul : « foot : » passe
  //  (l'espace précède les deux-points une fois le titre normalisé),
  //  mais « footloose » et « footing » ne passent pas.
  'football',
  'foot ',
  //  ` vs ` : dans un guide TV, c'est du sport dans l'immense majorité
  //  des cas. EXCEPTION CONNUE ET ASSUMÉE : « Kramer vs Kramer » sera
  //  annoncé comme un match. On l'accepte — rater le coup d'envoi coûte
  //  plus cher au client qu'une bannière de trop devant un vieux film,
  //  et le libellé reste juste sur le fond (« ça commence bientôt »).
  ' vs ',
  ' vs. ',
  'match',
  'finale',
  'demi-finale',
  'demi finale',
  'quart de finale',
  'coupe du monde',
  'ligue des champions',
  'champions league',
  'premier league',
  'ligue 1',
  'liga',
  'serie a',
  'bundesliga',
  'can ',           // Coupe d'Afrique des Nations — l'espace évite « canal »
  'caf ',
  'uefa',
  'fifa',
  'nba',
  'roland-garros',
  'roland garros',
  'grand prix',
  'formule 1',
  'tour de france',
  'six nations',
  'tournoi',
  'derby',
];

// ---------------------------------------------------------
//  « QUE TOUS LES GRANDS ÉVÉNEMENTS NE MANQUENT PAS » (21/09/2026)
// ---------------------------------------------------------
//  Jusqu'ici on ne regardait que les chaînes suivies (favoris + regardées
//  récemment), douze au plus. Une finale sur une chaîne qu'on n'a jamais
//  ouverte passait sans un mot. Désormais on balaie TOUT le guide, en
//  une requête — mais pas pour n'importe quoi : un client avec un bouquet
//  sport verrait sinon une bannière toutes les cinq minutes pour des
//  matchs de deuxième division qu'il ne regardera jamais. Pour les
//  chaînes qu'on ne suit pas, seuls les GRANDS événements passent :
//  finales, Coupe du monde, Ligue des champions, JO, Clásico, derby…
//  et les grands rendez-vous hors sport ci-dessous.
//
//  Deux listes, deux sévérités. `_motsMatch` reste la porte large (pour
//  les chaînes suivies) ; `_motsGrandEvenement` est la porte étroite
//  (pour toutes les autres). Un mot n'entre dans la seconde que si, sur
//  un guide TV, il désigne presque toujours un rendez-vous qu'on ne veut
//  pas rater.
// ---------------------------------------------------------

/// Mots d'un GRAND ÉVÉNEMENT sportif — sous-ensemble strict de
/// [_motsMatch], pour le balayage de toutes les chaînes.
const List<String> _motsGrandMatch = <String>[
  'finale', // couvre demi-finale, quart de finale
  'coupe du monde',
  'world cup',
  'mondial 20',
  'ligue des champions',
  'champions league',
  'europa league',
  'ligue europa',
  'euro 20',
  'jeux olympiques',
  'olympi',
  'super bowl',
  'clasico',
  'derby',
  'grand prix',
  'roland-garros',
  'roland garros',
  'wimbledon',
  'tour de france',
  'can 20',
  'afcon',
  'copa america',
  'coupe de france',
  'coupe d\'afrique',
  'six nations',
  'ballon d\'or',
];

/// Mots d'un GRAND ÉVÉNEMENT hors sport. Prudents : « concert » ou
/// « spécial » seuls déclencheraient sur les chaînes musicales toutes
/// les heures.
const List<String> _motsEvenement = <String>[
  'soiree electorale',
  'election presidentielle',
  'presidentielle 20',
  'resultats des elections',
  'allocution',
  'discours du president',
  'debat presidentiel',
  'ceremonie d\'ouverture',
  'ceremonie de cloture',
  'eurovision',
  'oscars',
  'les cesar',
  'ceremonie des cesar',
  'miss france',
  'miss univers',
  'nouvel an',
  'reveillon',
  'feu d\'artifice',
  'coronation',
  'couronnement',
];

/// Cette émission est-elle un GRAND événement — celui qu'on annonce même
/// sur une chaîne que le client ne suit pas ?
bool estGrandEvenement(String titre) {
  final String t = _aplatir(titre);
  if (t.isEmpty) return false;
  for (final String m in _motsGrandMatch) {
    if (t.contains(m)) return true;
  }
  for (final String m in _motsEvenement) {
    if (t.contains(m)) return true;
  }
  return false;
}

/// Mots qui désignent un JOURNAL / une édition d'information.
///
/// « info » et « news » SEULS sont trop vagues (« infos pratiques »,
/// « news de la mode ») : on exige des formes qui annoncent vraiment un
/// rendez-vous d'information.
const List<String> _motsJournal = <String>[
  'journal',
  'le 20h',
  'le 13h',
  'jt ',
  'edition speciale',
  'flash info',
  'info du jour',
  'les titres',
  'grand direct',
];

/// Minuscules + sans accents + espaces normalisés.
///
/// Sans ça, « Édition spéciale » et « edition speciale » seraient deux
/// choses différentes — et les guides IPTV écrivent les deux.
String _aplatir(String s) => aplatirTitre(s);

/// La même normalisation, exposée : sert de clé pour reconnaître le MÊME
/// événement diffusé sur plusieurs chaînes (tv_program_reminders.dart).
String aplatirTitre(String s) {
  const String avec = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const String sans = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final StringBuffer b = StringBuffer();
  for (final int u in s.toLowerCase().runes) {
    final String c = String.fromCharCode(u);
    final int i = avec.indexOf(c);
    b.write(i >= 0 ? sans[i] : c);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Classe [titre]. Un titre vide vaut [TypeEvenement.ordinaire] —
/// jamais une exception : un guide mal rempli ne doit pas faire tomber
/// l'écran d'accueil d'un client.
///
/// LE MATCH L'EMPORTE sur le journal : « Journal des sports · finale »
/// est d'abord une finale.
TypeEvenement classerEvenement(String titre) {
  final String t = _aplatir(titre);
  if (t.isEmpty) return TypeEvenement.ordinaire;
  for (final String m in _motsMatch) {
    if (t.contains(m)) return TypeEvenement.match;
  }
  // Le grand événement hors sport passe AVANT le journal : « Soirée
  // électorale — édition spéciale » est d'abord une soirée électorale.
  for (final String m in _motsEvenement) {
    if (t.contains(m)) return TypeEvenement.evenement;
  }
  for (final String m in _motsJournal) {
    if (t.contains(m)) return TypeEvenement.journal;
  }
  return TypeEvenement.ordinaire;
}

/// Combien de temps À L'AVANCE on prévient, selon le type.
///
///  • MATCH : 30 minutes. Le propriétaire l'a demandé au mot près, et
///    c'est le seul délai qui laisse le temps de s'installer ou
///    d'appeler quelqu'un.
///  • GRAND ÉVÉNEMENT : 30 minutes, même raison.
///  • JOURNAL : 10 minutes. Un rendez-vous quotidien, court ; prévenir
///    une demi-heure avant serait du bruit.
///  • ORDINAIRE : 10 minutes — exactement le comportement d'avant.
///    Ce fichier n'enlève rien, il ajoute.
Duration fenetreAnnonce(TypeEvenement type) {
  switch (type) {
    case TypeEvenement.match:
    case TypeEvenement.evenement:
      return const Duration(minutes: 30);
    case TypeEvenement.journal:
    case TypeEvenement.ordinaire:
      return const Duration(minutes: 10);
  }
}

/// Ordre de passage quand plusieurs émissions commencent en même temps.
/// Plus le nombre est grand, plus ça passe devant.
int prioriteEvenement(TypeEvenement type) {
  switch (type) {
    case TypeEvenement.match:
      return 3;
    case TypeEvenement.evenement:
      return 2;
    case TypeEvenement.journal:
      return 1;
    case TypeEvenement.ordinaire:
      return 0;
  }
}

// ---------------------------------------------------------
//  LE DERNIER APPEL À 5 MINUTES (21/09/2026)
// ---------------------------------------------------------
//  Demande du propriétaire : « active des petites notifications dans
//  5 min : le journal et d'autres matchs importants ».
//
//  Le rappel de 30 minutes (match) ou 10 minutes (journal) prévient
//  TÔT : on a le temps de s'installer. Mais il passe une fois, douze
//  secondes, et une demi-heure plus tard on a oublié. D'où un SECOND
//  rappel, court, à cinq minutes du début : le dernier appel. Seulement
//  pour ce qui compte — un match, un journal. Une émission ordinaire
//  garde son unique rappel de 10 minutes : deux bannières pour un
//  documentaire, ce serait du bruit, et le bruit tue les rappels.
//
//  Chaque étape s'annonce UNE fois par émission : la clé de
//  déduplication porte l'étape (voir tv_program_reminders.dart).
// ---------------------------------------------------------

/// Les deux étapes d'un rappel.
enum EtapeRappel {
  /// Le rappel d'avance : 30 min (match) ou 10 min (journal, ordinaire).
  tot,

  /// Le dernier appel, 5 minutes avant. Match et journal seulement.
  dernierAppel,
}

/// À combien de minutes du début part le dernier appel.
const Duration fenetreDernierAppel = Duration(minutes: 5);

/// Un type a-t-il droit au dernier appel ? Match, grand événement et
/// journal — pas l'ordinaire.
bool aDroitAuDernierAppel(TypeEvenement type) =>
    type == TypeEvenement.match ||
    type == TypeEvenement.evenement ||
    type == TypeEvenement.journal;

/// Quelle étape annoncer MAINTENANT pour une émission qui commence dans
/// [dansCombien], sachant ce qui a déjà été annoncé — ou `null` si rien.
///
/// Le dernier appel passe devant le rappel tôt quand les deux sont dus
/// (l'app était fermée, on rouvre à 4 minutes du match) : on ne dit pas
/// « dans 30 min » à quelqu'un qui a 4 minutes. Une émission déjà
/// commencée ([dansCombien] négatif) n'est plus annoncée.
EtapeRappel? etapeAAnnoncer(
  TypeEvenement type,
  Duration dansCombien, {
  required bool totDejaAnnonce,
  required bool dernierAppelDejaAnnonce,
}) {
  if (dansCombien.isNegative) return null;
  if (aDroitAuDernierAppel(type) &&
      !dernierAppelDejaAnnonce &&
      dansCombien <= fenetreDernierAppel) {
    return EtapeRappel.dernierAppel;
  }
  if (!totDejaAnnonce && dansCombien <= fenetreAnnonce(type)) {
    return EtapeRappel.tot;
  }
  return null;
}

/// Ordre de passage d'un rappel, étape comprise : un dernier appel (ça
/// commence dans 5 min) passe devant N'IMPORTE QUEL rappel tôt, et à
/// étape égale c'est [prioriteEvenement] qui tranche. Le maximum vaut
/// [rangMaximal] : au-delà, inutile de chercher mieux.
int rangRappel(TypeEvenement type, EtapeRappel etape) =>
    prioriteEvenement(type) + (etape == EtapeRappel.dernierAppel ? 3 : 0);

/// Le rang qu'aucun rappel ne dépasse (dernier appel d'un match).
final int rangMaximal = rangRappel(TypeEvenement.match, EtapeRappel.dernierAppel);
