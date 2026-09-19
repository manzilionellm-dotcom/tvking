// =========================================================
//  banc_essai.dart — noter un build sur ce qu'il a VRAIMENT vécu
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (18/09/2026) : « Fais l'excellence, et fais
//  un benchmark. »
//
//  ---------------------------------------------------------
//  LE PROBLÈME QU'IL FERME
//  ---------------------------------------------------------
//  Aujourd'hui, entre « le build est vert » et « un client appelle », il
//  n'y a RIEN. Toutes les pannes du 18/09 ont été trouvées par le
//  propriétaire, sur du vrai matériel, après coup : l'écran noir au bout
//  de 30 minutes, le bouton mort du panel, la liste qui ne partait plus.
//  Aucune n'a été vue par le code.
//
//  Et quand une amélioration arrive, on n'a même pas de quoi la prouver.
//  « La box tient maintenant 6 h 40 au lieu de 25 minutes » a été mesuré
//  à la main, une fois, sur une box. Ça ne se compare pas d'un build à
//  l'autre, donc ça ne se défend pas.
//
//  ---------------------------------------------------------
//  CE FICHIER NE MESURE RIEN. IL NOTE.
//  ---------------------------------------------------------
//  C'est le point important. La Boîte noire enregistre DÉJÀ tout ce qui
//  compte — crashs, purges mémoire, démarrages ratés, gels, verrou
//  d'écran. Ajouter des compteurs à côté aurait fabriqué une deuxième
//  vérité, qui aurait fini par contredire la première. Même raison que
//  ci/build_label.sh et cloudflare/stream_proxy.js.
//
//  On prend donc les lignes de la Boîte noire telles quelles et on en
//  tire une note comparable. Fonction PURE : pas de Flutter, pas
//  d'horloge, pas de disque. Elle se teste à la ligne près, et elle se
//  rejoue sur les journaux d'un client réel.
//
//  ---------------------------------------------------------
//  LA RÈGLE QUI REND CE BANC HONNÊTE
//  ---------------------------------------------------------
//  UNE COURTE SESSION NE REÇOIT AUCUNE NOTE.
//
//  Trois minutes sans crash ne prouvent rien : la panne qu'on cherche
//  met justement une demi-heure à se montrer. Un banc qui afficherait
//  « 100/100 » après trois minutes serait pire qu'inutile — il
//  donnerait confiance sans raison, et c'est exactement le piège du
//  « vert ne veut pas dire livré », en pire : un vert qui MENT.
//
//  En dessous de [dureeMinimale], la note vaut `null` et le résumé le
//  dit. Pas de note approximative, pas d'étoile de consolation.
// =========================================================

/// Ce que la Boîte noire a compté pendant une période d'observation.
///
/// Chaque champ correspond à un ÉVÉNEMENT RÉEL du journal, pas à une
/// catégorie inventée pour l'occasion — on peut retrouver chaque
/// chiffre dans les lignes brutes.
class BancMesure {
  const BancMesure({
    required this.duree,
    required this.crashs,
    required this.erreursNonRattrapees,
    required this.purgesMemoire,
    required this.demarragesRates,
    required this.erreursLecture,
    required this.gelsBudgetDepasse,
    required this.verrouRefuse,
    required this.verrouRetabli,
    this.premieresImagesMs = const <int>[],
  });

  /// `native / tv_player.first_frame`, ctx.ms — le temps entre « la
  /// chaîne s'ouvre » et « la première image est dessinée », pour CHAQUE
  /// ouverture de la période. C'est le « temps de chargement des
  /// chaînes » du banc de la famille (19/09/2026) : jusqu'ici il n'avait
  /// aucun chiffre terrain, seulement des échecs comptés.
  ///
  /// UNE LISTE, PAS UNE MOYENNE : un seul zap à 20 s (chaîne morte, puis
  /// secours) écraserait la moyenne d'une soirée de zaps à 1,5 s. La
  /// médiane, elle, dit ce que le client vit d'habitude.
  final List<int> premieresImagesMs;

  /// Nombre d'ouvertures mesurées sur la période.
  int get premieresImages => premieresImagesMs.length;

  /// Médiane du temps jusqu'à la première image, en ms. `null` = aucune
  /// ouverture mesurée (la box n'a rien lu, ou tourne un build d'avant).
  int? get premiereImageMedianeMs {
    if (premieresImagesMs.isEmpty) return null;
    final List<int> tri = List<int>.of(premieresImagesMs)..sort();
    final int milieu = tri.length ~/ 2;
    return tri.length.isOdd
        ? tri[milieu]
        : ((tri[milieu - 1] + tri[milieu]) / 2).round();
  }

  /// Durée observée. C'est LE chiffre que le propriétaire lit en
  /// premier : « la box a tenu combien de temps ? »
  final Duration duree;

  /// `lvl = fatal` — l'application est morte.
  final int crashs;

  /// `domain = crash`, `lvl = err` — exceptions arrivées au filet
  /// global. L'app survit, mais quelque chose s'est mal passé.
  final int erreursNonRattrapees;

  /// `memoire / pressure.purge` — Android a prévenu qu'il manquait de
  /// mémoire et on a vidé le cache pour rester en vie. Fréquent = la
  /// box vit au bord de l'OOM.
  final int purgesMemoire;

  /// `native / tv_player.startup_timeout` — une chaîne n'a JAMAIS
  /// démarré. C'est la panne la plus visible pour un client.
  final int demarragesRates;

  /// `native / tv_player.error` — erreur remontée par le lecteur natif.
  final int erreursLecture;

  /// `native / tv_player.rebuffer_budget_exceeded` — l'image a gelé
  /// au-delà du budget. Le client voit la roue tourner.
  final int gelsBudgetDepasse;

  /// `ecran / verrou.refuse` — la box a refusé de garder l'écran
  /// allumé. Une seule fois suffit : l'écran s'éteindra.
  final int verrouRefuse;

  /// `ecran / verrou.retabli` — la box avait relâché le verrou, on l'a
  /// remis à temps. Le client n'a rien vu, mais c'est un signal.
  final int verrouRetabli;

  /// Toutes les pannes confondues — pratique pour un coup d'œil.
  int get incidents =>
      crashs +
      erreursNonRattrapees +
      purgesMemoire +
      demarragesRates +
      erreursLecture +
      gelsBudgetDepasse +
      verrouRefuse +
      verrouRetabli;

  /// Heures observées, en décimal. Sert à ramener chaque compteur à un
  /// TAUX HORAIRE : sans ça, une session de 24 h paraîtrait pire qu'une
  /// de 10 minutes simplement parce qu'elle a duré plus longtemps.
  double get heures => duree.inMilliseconds / 3600000.0;
}

/// La note d'un build, et surtout ce qui la justifie.
class BancVerdict {
  const BancVerdict({
    required this.mesure,
    required this.note,
    required this.resume,
    required this.reproches,
    required this.nonMesure,
  });

  final BancMesure mesure;

  /// 0 à 100. `null` = la session est TROP COURTE pour juger. Ce n'est
  /// pas « 0 » : c'est « je ne sais pas », et il faut le lire ainsi.
  final int? note;

  /// Une phrase, celle qu'on lit au téléphone.
  final String resume;

  /// Ce qui a coûté des points, avec les chiffres. Vide = rien à
  /// reprocher.
  final List<String> reproches;

  /// CE QUE CE BANC NE PROUVE PAS. Toujours rempli, même à 100/100 :
  /// une note sans ses limites est une note qui ment par omission, et
  /// c'est le défaut qui revient le plus souvent dans ce dépôt.
  final List<String> nonMesure;

  /// `true` seulement si on a osé donner une note ET qu'elle est bonne.
  bool get bon => note != null && note! >= 80;

  /// Le verdict, prêt à voyager dans le heartbeat.
  ///
  ///  COMPACT ET SANS PHRASES : les textes français se refabriquent
  ///  côté panel à partir des mêmes chiffres. Les envoyer 200 fois par
  ///  jour depuis chaque box, pour les réécrire à l'identique, serait
  ///  de la donnée payée pour rien — et deux rédactions à tenir.
  ///
  ///  AUCUNE INFORMATION SUR CE QUE LE CLIENT REGARDE. Uniquement des
  ///  compteurs de nos propres pannes. C'est ce qui rend ce paquet
  ///  acceptable à envoyer ; le jour où on aurait envie d'y glisser un
  ///  nom de chaîne, la réponse est non.
  Map<String, Object?> toJson() => <String, Object?>{
        'note': note,
        'minutes': mesure.duree.inMinutes,
        'crashs': mesure.crashs,
        'err': mesure.erreursNonRattrapees,
        'mem': mesure.purgesMemoire,
        'nostart': mesure.demarragesRates,
        'lecture': mesure.erreursLecture,
        'gels': mesure.gelsBudgetDepasse,
        'verrou_ko': mesure.verrouRefuse,
        'verrou_ok': mesure.verrouRetabli,
        // Temps jusqu'à la 1re image : la MÉDIANE de la box et le nombre
        // d'ouvertures derrière. Le serveur fera la médiane des box par
        // build ; envoyer la liste entière ne servirait qu'à remplir la
        // base. `null` quand rien n'a été lu — ce n'est pas « 0 ms ».
        'ttff_med': mesure.premiereImageMedianeMs,
        'ttff_n': mesure.premieresImages,
      };
}

/// En dessous de ça, on refuse de noter. Une demi-heure est le délai au
/// bout duquel les pannes connues de ce parc se montrent (écran noir,
/// pression mémoire) ; on exige le double pour être tranquille.
const Duration dureeMinimale = Duration(hours: 1);

/// Pénalités, exprimées PAR HEURE sauf mention contraire.
///
///  Les poids ne sont pas décoratifs : ils reproduisent ce que chaque
///  panne coûte VRAIMENT au propriétaire, en appels et en abonnements
///  perdus.
///
///   • un crash vide le salon : c'est éliminatoire, pas un malus ;
///   • une chaîne qui ne démarre jamais est la panne que le client
///     appelle pour signaler ;
///   • un verrou refusé garantit un écran noir : une seule occurrence
///     suffit à plomber la note, elle n'est donc PAS ramenée à l'heure ;
///   • une purge mémoire n'est pas visible tout de suite, mais c'est
///     l'antichambre de l'OOM.
const int _malusCrash = 40; // par crash, non ramené à l'heure
const int _malusVerrouRefuse = 25; // par occurrence, non ramené à l'heure
const double _malusDemarrageRate = 8;
const double _malusGel = 6;
const double _malusErreurLecture = 4;
const double _malusPurgeMemoire = 3;
const double _malusVerrouRetabli = 2;
const double _malusErreurNonRattrapee = 2;

/// Compte les pannes d'une période à partir des lignes DÉJÀ écrites par
/// la Boîte noire.
///
///  [entrees] = les enregistrements JSON décodés (`lvl`, `domain`,
///  `event`, `ctx`). Une entrée illisible est ignorée sans faire tomber
///  le comptage : un journal abîmé ne doit pas priver le propriétaire de
///  son verdict.
BancMesure mesurerBanc(
  Iterable<Map<String, Object?>> entrees, {
  required Duration duree,
}) {
  int crashs = 0;
  int erreursNonRattrapees = 0;
  int purges = 0;
  int demarrages = 0;
  int erreurs = 0;
  int gels = 0;
  int verrouRefuse = 0;
  int verrouRetabli = 0;
  final List<int> premieresImages = <int>[];

  for (final Map<String, Object?> e in entrees) {
    final String lvl = '${e['lvl'] ?? ''}';
    final String domaine = '${e['domain'] ?? ''}';
    final String evenement = '${e['event'] ?? ''}';

    if (lvl == 'fatal') {
      crashs++;
      continue;
    }
    if (domaine == 'crash' && lvl == 'err') {
      erreursNonRattrapees++;
      continue;
    }
    if (domaine == 'memoire' && evenement == 'pressure.purge') {
      purges++;
      continue;
    }
    if (domaine == 'native') {
      switch (evenement) {
        case 'tv_player.startup_timeout':
          demarrages++;
          continue;
        case 'tv_player.error':
          erreurs++;
          continue;
        case 'tv_player.rebuffer_budget_exceeded':
          gels++;
          continue;
        case 'tv_player.first_frame':
          // Une mesure, pas une panne : on la garde telle quelle. Un
          // `ms` absent ou négatif (ligne abîmée) est ignoré sans bruit.
          final Object? ctx = e['ctx'];
          final Object? ms = ctx is Map<String, Object?> ? ctx['ms'] : null;
          if (ms is num && ms >= 0) premieresImages.add(ms.toInt());
          continue;
      }
    }
    if (domaine == 'ecran') {
      switch (evenement) {
        case 'verrou.refuse':
          verrouRefuse++;
          continue;
        case 'verrou.retabli':
          verrouRetabli++;
          continue;
      }
    }
  }

  return BancMesure(
    duree: duree,
    crashs: crashs,
    erreursNonRattrapees: erreursNonRattrapees,
    purgesMemoire: purges,
    demarragesRates: demarrages,
    erreursLecture: erreurs,
    gelsBudgetDepasse: gels,
    verrouRefuse: verrouRefuse,
    verrouRetabli: verrouRetabli,
    premieresImagesMs: premieresImages,
  );
}

/// Transforme une mesure en NOTE et en phrases lisibles.
BancVerdict noterBanc(BancMesure m) {
  // ----- Ce que ce banc ne prouve pas, dit à chaque fois -----
  //
  //  Une note sans ses limites ment par omission. Celles-ci sont
  //  structurelles : elles ne disparaîtront pas en améliorant l'app.
  final List<String> nonMesure = <String>[
    'La qualité d\'image et le son ne sont pas notés : ce banc lit le '
        'journal, il ne regarde pas l\'écran.',
    'Une panne du FOURNISSEUR compte ici comme une erreur de lecture. '
        'Une mauvaise note peut donc venir de sa ligne, pas de l\'app.',
    'Une seule box ne représente pas le parc : un modèle qui va bien '
        'ne dit rien des box à faible mémoire.',
  ];

  // ----- Trop court pour juger : on le DIT, on n'invente pas -----
  if (m.duree < dureeMinimale) {
    return BancVerdict(
      mesure: m,
      note: null,
      resume: 'Trop court pour juger : ${_duree(m.duree)} observées, il en '
          'faut au moins ${dureeMinimale.inHours} h. Les pannes qu\'on '
          'cherche mettent une demi-heure à se montrer.',
      reproches: const <String>[],
      nonMesure: nonMesure,
    );
  }

  final double h = m.heures;
  final List<String> reproches = <String>[];
  double malus = 0;

  void compter(
    int n,
    double poidsParHeure,
    String Function(int n, double parHeure) phrase,
  ) {
    if (n <= 0) return;
    final double parHeure = n / h;
    malus += parHeure * poidsParHeure;
    reproches.add(phrase(n, parHeure));
  }

  // Les deux éliminatoires : comptés à l'unité, pas au taux horaire.
  if (m.crashs > 0) {
    malus += m.crashs * _malusCrash;
    reproches.add('${m.crashs} crash${m.crashs > 1 ? 's' : ''} — '
        'l\'application est morte, le salon s\'est éteint.');
  }
  if (m.verrouRefuse > 0) {
    malus += m.verrouRefuse * _malusVerrouRefuse;
    reproches.add('${m.verrouRefuse} refus du verrou d\'écran — cette box '
        'finira par afficher un écran noir.');
  }

  compter(m.demarragesRates, _malusDemarrageRate,
      (int n, double ph) => '$n chaîne${n > 1 ? 's' : ''} n\'a jamais '
          'démarré (${_taux(ph)}/h) — c\'est la panne que le client '
          'appelle pour signaler.');
  compter(m.gelsBudgetDepasse, _malusGel,
      (int n, double ph) => '$n gel${n > 1 ? 's' : ''} au-delà du budget '
          '(${_taux(ph)}/h) — la roue qui tourne.');
  compter(m.erreursLecture, _malusErreurLecture,
      (int n, double ph) => '$n erreur${n > 1 ? 's' : ''} de lecture '
          '(${_taux(ph)}/h) — à recouper avec l\'état du fournisseur.');
  compter(m.purgesMemoire, _malusPurgeMemoire,
      (int n, double ph) => '$n purge${n > 1 ? 's' : ''} mémoire '
          '(${_taux(ph)}/h) — la box vit au bord de la rupture.');
  compter(m.verrouRetabli, _malusVerrouRetabli,
      (int n, double ph) => '$n fois où la box a lâché le verrou d\'écran '
          '(${_taux(ph)}/h) — remis à temps, le client n\'a rien vu.');
  compter(m.erreursNonRattrapees, _malusErreurNonRattrapee,
      (int n, double ph) => '$n erreur${n > 1 ? 's' : ''} non rattrapée '
          '(${_taux(ph)}/h) — l\'app a survécu, mais quelque chose a '
          'dérapé.');

  final int note = (100 - malus).round().clamp(0, 100);

  final String resume;
  if (note >= 90) {
    resume = '${_duree(m.duree)} sans rien à signaler. $note/100.';
  } else if (note >= 80) {
    resume = '${_duree(m.duree)} tenues, quelques accrocs. $note/100.';
  } else if (note >= 50) {
    resume = '${_duree(m.duree)} tenues, mais ça accroche pour de bon. '
        '$note/100.';
  } else {
    resume = 'Ce build ne tient pas : $note/100 sur ${_duree(m.duree)}.';
  }

  return BancVerdict(
    mesure: m,
    note: note,
    resume: resume,
    reproches: reproches,
    nonMesure: nonMesure,
  );
}

/// « 6 h 40 », « 45 min » — comme le propriétaire le dit à voix haute,
/// jamais « 24012 s ».
String _duree(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final int h = d.inHours;
  final int min = d.inMinutes % 60;
  return min == 0 ? '$h h' : '$h h $min';
}

/// Un taux horaire lisible : « 0,4 », « 12 ».
String _taux(double parHeure) {
  if (parHeure >= 10) return parHeure.round().toString();
  return parHeure.toStringAsFixed(1).replaceAll('.', ',');
}
