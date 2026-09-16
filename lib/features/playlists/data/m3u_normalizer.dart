// =========================================================
//  m3u_normalizer.dart — la playlist est-elle exploitable ?
// =========================================================
//  POURQUOI CE FICHIER EXISTE (16/09/2026).
//
//  Le revendeur colle un M3U depuis son panel. Chez le client, deux
//  choses seulement peuvent arriver : ça joue, ou ça ne joue pas. Quand
//  ça ne jouait pas, l'app ne disait RIEN — elle restait sur son fond
//  dégradé et re-sondait toutes les 6 secondes, indéfiniment. Ni le
//  client, ni le revendeur ne pouvaient savoir pourquoi.
//
//  Or la cause est presque toujours banale et NOMMABLE : un BOM Windows
//  devant le `#EXTM3U`, des fins de ligne `\r\n`, un `#EXTM3U` absent,
//  ou — le cas le plus fréquent — le serveur qui renvoie une page HTML
//  d'erreur (« ligne expirée », « trop de connexions ») avec un code 200
//  bien vert. Un parseur qui avale ça produit zéro chaîne et une
//  exception générique.
//
//  Ce module regarde la playlist AVANT de la parser et rend un verdict
//  qui se dit à voix haute au support.
//
//  ---------------------------------------------------------
//  IL NE RECOPIE PAS LE FICHIER, ET C'EST ESSENTIEL
//  ---------------------------------------------------------
//  La tentation est d'écrire trois lignes :
//
//      contenu = contenu.replaceAll('\r\n', '\n').trimLeft();
//
//  C'est EXACTEMENT ce que le parseur a supprimé le 05/09/2026, après
//  avoir mesuré 486 Mo d'allocations sur un M3U d'un million d'entrées —
//  avant même la première chaîne produite. Sur une box à 512 Mo, c'est
//  l'app qui meurt.
//
//  Donc on ne normalise pas EN RECOPIANT : on rend un OFFSET. Le
//  parseur commence sa lecture à [VerdictM3u.offset], et son découpage
//  paresseux de lignes (+ le `trim()` de chaque ligne) absorbe déjà les
//  `\r`, les `\r\n` et les espaces parasites, une ligne à la fois.
//  L'en-tête `#EXTM3U` manquant est « forcé » LOGIQUEMENT : le parseur
//  sait qu'il peut commencer sans lui, et le verdict le signale.
//
//  On n'inspecte donc que la TÊTE du contenu ([_fenetre] caractères) :
//  assez pour reconnaître une page HTML ou trouver le premier `#EXTINF`,
//  jamais assez pour coûter quoi que ce soit.
//
//  ---------------------------------------------------------
//  LES DEUX FAÇONS DE SE TROMPER NE COÛTENT PAS PAREIL
//  ---------------------------------------------------------
//  Déclarer INVALIDE une playlist qui marchait = on prive un client
//  payant de sa télé pour un faux positif. Déclarer VALIDE une playlist
//  cassée = le parseur rend zéro chaîne, et l'appelant dira lui-même
//  « 0 chaîne » — c'est-à-dire la vérité, juste moins précise.
//
//  Dans le doute, donc, on laisse passer. Les seuls verdicts d'invalidité
//  ci-dessous portent sur des contenus dont on est SÛR qu'aucune chaîne
//  n'en sortira : rien du tout, ou un document qui n'est pas une
//  playlist (HTML, JSON, XML).
//
//  Fonctions PURES, aucun import Flutter : testables à la milliseconde.
// =========================================================

/// Pourquoi une playlist ne donnera aucune chaîne — dit en français, pour
/// être lu à voix haute au téléphone par le support.
enum RaisonM3uInvalide {
  /// Rien, ou uniquement des blancs / un BOM tout seul.
  vide,

  /// Le serveur a renvoyé une page web, pas une playlist. C'est le cas
  /// terrain n°1 : « ligne expirée » / « max connections » servi en HTML
  /// avec un code HTTP 200 parfaitement vert.
  pageWeb,

  /// Réponse JSON ou XML — typiquement une erreur d'API du panneau.
  reponseApi,

  /// Du texte, mais aucune trace de playlist : ni `#EXTM3U`, ni
  /// `#EXTINF`, ni la moindre URL.
  pasUnePlaylist,
}

/// Message prêt à afficher au client ET à lire au support.
String messageM3uInvalide(RaisonM3uInvalide raison) {
  switch (raison) {
    case RaisonM3uInvalide.vide:
      return 'Le serveur a répondu, mais la liste est vide. '
          'Vérifie le lien M3U dans le panneau.';
    case RaisonM3uInvalide.pageWeb:
      return 'Le serveur a renvoyé une page web au lieu de la liste — '
          'en général « ligne expirée » ou « trop de connexions ». '
          'Vérifie l\'abonnement chez le fournisseur.';
    case RaisonM3uInvalide.reponseApi:
      return 'Le serveur a renvoyé un message d\'erreur au lieu de la '
          'liste. Vérifie les identifiants dans le panneau.';
    case RaisonM3uInvalide.pasUnePlaylist:
      return 'Le lien ne pointe pas vers une liste de chaînes '
          '(aucun #EXTM3U ni #EXTINF trouvé). Vérifie le lien M3U.';
  }
}

/// Ce que l'examen a trouvé.
class VerdictM3u {
  const VerdictM3u({
    required this.offset,
    required this.entete,
    required this.corrections,
    this.raison,
  });

  /// Index du premier caractère à parser : après le BOM et les blancs de
  /// tête. Le parseur démarre là — AUCUNE recopie du contenu.
  final int offset;

  /// `#EXTM3U` était présent. Sinon le parseur commence quand même :
  /// l'en-tête est « forcé » logiquement, jamais réécrit en mémoire.
  final bool entete;

  /// Ce qu'on a réparé, en clair. Alimente les avertissements du parseur
  /// (visibles dans le détail d'import), jamais un blocage.
  final List<String> corrections;

  /// `null` = exploitable. Sinon, la raison à afficher.
  final RaisonM3uInvalide? raison;

  bool get exploitable => raison == null;
}

/// Taille de la tête inspectée. 8 Ko : largement plus qu'un en-tête HTML
/// ou que les premières entrées d'une playlist, et négligeable même sur
/// une box à 512 Mo.
const int _fenetre = 8192;

/// Caractère BOM (UTF-8 décodé, ou UTF-16 natif).
const int _bom = 0xFEFF;

/// Examine [contenu] et dit s'il donnera des chaînes — sans le recopier.
VerdictM3u examinerM3u(String contenu) {
  final List<String> corrections = <String>[];

  // ---------------------------------------------------------
  //  1. BOM(s) et blancs de tête → on avance un curseur.
  // ---------------------------------------------------------
  //  Certains exports empilent DEUX BOM (fichier déjà converti une fois),
  //  d'autres mettent des lignes vides avant le `#EXTM3U`. On avale les
  //  deux dans la même boucle : un `while` coûte quelques comparaisons,
  //  là où un `trimLeft()` recopierait tout le fichier.
  int i = 0;
  bool bomVu = false;
  bool blancVu = false;
  while (i < contenu.length) {
    final int u = contenu.codeUnitAt(i);
    if (u == _bom) {
      bomVu = true;
      i++;
    } else if (u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0D) {
      blancVu = true;
      i++;
    } else {
      break;
    }
  }
  if (bomVu) corrections.add('BOM retiré (export Windows).');
  if (blancVu) corrections.add('Blancs de tête retirés.');

  if (i >= contenu.length) {
    return VerdictM3u(
      offset: i,
      entete: false,
      corrections: corrections,
      raison: RaisonM3uInvalide.vide,
    );
  }

  // ---------------------------------------------------------
  //  2. La tête — assez pour reconnaître, jamais assez pour coûter.
  // ---------------------------------------------------------
  final int fin = (i + _fenetre) < contenu.length ? i + _fenetre : contenu.length;
  final String tete = contenu.substring(i, fin);
  final String teteMaj = tete.toUpperCase();

  // ---------------------------------------------------------
  //  3. Est-ce seulement une playlist ?
  // ---------------------------------------------------------
  //  ORDRE VOULU : on cherche les marqueurs de playlist AVANT de crier
  //  « page web ». Une playlist peut légitimement contenir un `<` (un nom
  //  de chaîne « TF1 <HD> » est rare mais réel) ; un document HTML, lui,
  //  n'a jamais de `#EXTINF`. Chercher la playlist d'abord rend donc le
  //  faux positif impossible — et c'est lui qui coûte cher.
  final bool aExtm3u = teteMaj.contains('#EXTM3U');
  final bool aExtinf = teteMaj.contains('#EXTINF');

  if (aExtm3u || aExtinf) {
    if (!aExtm3u) {
      // Toléré et signalé : beaucoup de panneaux servent la liste sans
      // en-tête. On ne réécrit rien — le parseur sait démarrer sans.
      corrections.add('En-tête #EXTM3U absent — ajouté implicitement.');
    }
    return VerdictM3u(offset: i, entete: aExtm3u, corrections: corrections);
  }

  // Pas de marqueur de playlist : là, un document est un document.
  if (_ressembleAHtml(teteMaj)) {
    return VerdictM3u(
      offset: i,
      entete: false,
      corrections: corrections,
      raison: RaisonM3uInvalide.pageWeb,
    );
  }
  final int premier = tete.codeUnitAt(0);
  if (premier == 0x7B || premier == 0x5B) {
    // `{` ou `[` — réponse JSON d'API.
    return VerdictM3u(
      offset: i,
      entete: false,
      corrections: corrections,
      raison: RaisonM3uInvalide.reponseApi,
    );
  }
  if (teteMaj.startsWith('<?XML')) {
    return VerdictM3u(
      offset: i,
      entete: false,
      corrections: corrections,
      raison: RaisonM3uInvalide.reponseApi,
    );
  }

  // ---------------------------------------------------------
  //  4. Dernière chance : une playlist « nue » (que des URLs).
  // ---------------------------------------------------------
  //  Format rare mais parfaitement valide, et le parseur le gère. Le
  //  refuser priverait un client d'une liste qui marche.
  if (teteMaj.contains('HTTP://') ||
      teteMaj.contains('HTTPS://') ||
      teteMaj.contains('RTMP://') ||
      teteMaj.contains('RTSP://')) {
    corrections.add('Liste sans #EXTM3U ni #EXTINF (URLs nues) — acceptée.');
    return VerdictM3u(offset: i, entete: false, corrections: corrections);
  }

  return VerdictM3u(
    offset: i,
    entete: false,
    corrections: corrections,
    raison: RaisonM3uInvalide.pasUnePlaylist,
  );
}

/// Reconnaît un document HTML. Volontairement STRICT : on ne se fie qu'à
/// des balises de structure en tout début de document, pas à la présence
/// d'un `<` quelque part.
bool _ressembleAHtml(String teteMaj) {
  final String debut = teteMaj.trimLeft();
  return debut.startsWith('<!DOCTYPE') ||
      debut.startsWith('<HTML') ||
      debut.startsWith('<HEAD') ||
      debut.startsWith('<BODY') ||
      debut.startsWith('<SCRIPT') ||
      debut.startsWith('<META');
}
