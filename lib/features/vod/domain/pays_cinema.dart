// =========================================================
//  pays_cinema.dart — ranger le Cinéma PAR PAYS, la France en tête
// =========================================================
//  DEMANDE DU PROPRIÉTAIRE (19/09/2026) : « les Turcs m'ont dit qu'ils
//  ne voient pas leurs séries, c'est mélangé. Il faut que chaque pays…
//  ça commence la France, et d'autres pays. Mais ne casse pas le
//  display Netflix. »
//
//  ---------------------------------------------------------
//  CE QUI SE PASSAIT
//  ---------------------------------------------------------
//  Les rangées du Cinéma suivaient l'ORDRE DU FOURNISSEUR : une par
//  catégorie, dans l'ordre où son panel les liste. Un fournisseur qui
//  vend à dix communautés range comme ça l'arrange — « FR| Action »,
//  puis « TR| Dizi », puis « AR| أفلام », puis « FR| Comédie »… Un client
//  turc devait descendre toute la page pour retrouver ses trois rangées,
//  éparpillées entre les autres. Il ne les « voyait pas ».
//
//  ---------------------------------------------------------
//  CE QU'ON FAIT — ET CE QU'ON NE TOUCHE PAS
//  ---------------------------------------------------------
//  On ne change que l'ORDRE des rangées. Les rangées elles-mêmes (une
//  par catégorie, affiches, focus, bannière) restent exactement ce
//  qu'elles sont : c'est le « display Netflix », et il ne bouge pas.
//
//    1. la FRANCE d'abord — la règle du propriétaire ;
//    2. puis les catégories SANS pays reconnu (« NETFLIX », « 4K »,
//       « Nouveautés ») : chez nos fournisseurs, c'est du contenu de la
//       langue principale, donc du français, ou du généraliste que tout
//       le monde veut voir. Les mettre en fin de page ferait descendre
//       un client français sous les rangées turques et arabes pour
//       trouver Netflix ;
//    3. puis CHAQUE AUTRE PAYS, ses rangées les unes derrière les
//       autres, dans l'ordre où le fournisseur l'a fait apparaître en
//       premier. Un Turc trouve ses trois rangées ensemble.
//
//  À l'intérieur d'un pays, l'ordre du fournisseur est conservé : il
//  connaît son catalogue mieux que nous.
//
//  ---------------------------------------------------------
//  COMMENT ON RECONNAÎT UN PAYS
//  ---------------------------------------------------------
//  Les fournisseurs écrivent le pays en préfixe, de vingt façons :
//  « FR| », « |FR| », « [FR] », « FR - », « FR: », « FRANCE ▶ »,
//  « FRENCH », « VF ». Et parfois seulement par un mot de la langue :
//  « Dizi » (série turque), « Bollywood ».
//
//  Deux règles, pour ne pas voir des pays partout :
//   • un CODE COURT (2-3 lettres : FR, TR, US, DE, IT…) n'est reconnu
//     qu'en TÊTE de libellé ou entre crochets / barres — « Series NO
//     Limit » n'est pas la Norvège, « Films IT » non plus ;
//   • un MOT ENTIER (4 lettres et plus : france, turkish, arabic…) est
//     reconnu où qu'il soit dans le libellé.
//
//  Fonctions PURES, sans Flutter : elles se testent à la ligne près sur
//  de vrais libellés de fournisseurs (cf. pays_cinema_test.dart).
// =========================================================

/// Codes courts, reconnus SEULEMENT en tête ou entre crochets/barres.
const Map<String, String> _codesCourts = <String, String>{
  'fr': 'FR', 'fra': 'FR', 'vf': 'FR', 'vff': 'FR',
  'be': 'BE', 'bel': 'BE',
  'tr': 'TR', 'tur': 'TR',
  'ar': 'AR', 'ara': 'AR',
  'ma': 'MA', 'mar': 'MA', 'dz': 'DZ', 'alg': 'DZ', 'tn': 'TN', 'tun': 'TN',
  'eg': 'EG', 'egy': 'EG', 'sa': 'SA', 'ksa': 'SA', 'lb': 'LB',
  'en': 'EN', 'eng': 'EN', 'uk': 'UK', 'gb': 'UK', 'us': 'US', 'usa': 'US',
  'ca': 'CA', 'can': 'CA',
  'es': 'ES', 'esp': 'ES', 'lat': 'LAT',
  'de': 'DE', 'ger': 'DE', 'it': 'IT', 'ita': 'IT',
  'pt': 'PT', 'por': 'PT', 'br': 'BR', 'bra': 'BR',
  'nl': 'NL', 'pl': 'PL', 'pol': 'PL', 'ro': 'RO', 'rou': 'RO',
  'ru': 'RU', 'rus': 'RU', 'in': 'IN', 'ind': 'IN', 'pk': 'PK',
  'gr': 'GR', 'gre': 'GR', 'al': 'AL', 'alb': 'AL', 'ku': 'KU', 'kur': 'KU',
  'se': 'SE', 'swe': 'SE', 'no': 'NO', 'nor': 'NO', 'dk': 'DK', 'dan': 'DK',
  'fi': 'FI', 'fin': 'FI', 'af': 'AF', 'afr': 'AF',
  'cn': 'CN', 'chn': 'CN', 'jp': 'JP', 'jpn': 'JP', 'kr': 'KR', 'kor': 'KR',
};

/// Mots entiers (≥ 4 lettres), reconnus n'importe où dans le libellé.
const Map<String, String> _motsEntiers = <String, String>{
  'france': 'FR', 'french': 'FR', 'français': 'FR', 'francais': 'FR',
  'francaise': 'FR', 'française': 'FR', 'vostfr': 'FR',
  'belgique': 'BE', 'belgium': 'BE', 'belge': 'BE',
  'turk': 'TR', 'turkish': 'TR', 'türk': 'TR', 'turkce': 'TR', 'türkçe': 'TR',
  'turquie': 'TR', 'turkey': 'TR', 'turkiye': 'TR', 'türkiye': 'TR',
  'dizi': 'TR', 'diziler': 'TR', 'yerli': 'TR',
  'arab': 'AR', 'arabe': 'AR', 'arabic': 'AR', 'arabes': 'AR', 'arabia': 'AR',
  'عربي': 'AR', 'عربية': 'AR', 'عربى': 'AR',
  'maroc': 'MA', 'morocco': 'MA', 'marocain': 'MA', 'maghreb': 'MA',
  'algerie': 'DZ', 'algérie': 'DZ', 'algeria': 'DZ', 'algerien': 'DZ',
  'tunisie': 'TN', 'tunisia': 'TN', 'tunisien': 'TN',
  'egypt': 'EG', 'egypte': 'EG', 'égypte': 'EG', 'egyptian': 'EG',
  'saudi': 'SA', 'lebanon': 'LB', 'liban': 'LB', 'libanais': 'LB',
  'english': 'EN', 'anglais': 'EN',
  'british': 'UK', 'england': 'UK', 'angleterre': 'UK',
  'america': 'US', 'american': 'US', 'americain': 'US', 'américain': 'US',
  'hollywood': 'US',
  'canada': 'CA', 'quebec': 'CA', 'québec': 'CA',
  'spain': 'ES', 'espagne': 'ES', 'spanish': 'ES', 'español': 'ES',
  'espanol': 'ES', 'espagnol': 'ES', 'castellano': 'ES',
  'latino': 'LAT', 'latin': 'LAT', 'latam': 'LAT',
  'german': 'DE', 'deutsch': 'DE', 'allemagne': 'DE', 'germany': 'DE',
  'allemand': 'DE',
  'italian': 'IT', 'italiano': 'IT', 'italie': 'IT', 'italy': 'IT',
  'italien': 'IT',
  'portugal': 'PT', 'portuguese': 'PT', 'português': 'PT', 'portugais': 'PT',
  'brasil': 'BR', 'brazil': 'BR', 'brésil': 'BR', 'bresil': 'BR',
  'dutch': 'NL', 'nederland': 'NL', 'netherlands': 'NL', 'holland': 'NL',
  'polish': 'PL', 'polska': 'PL', 'poland': 'PL', 'pologne': 'PL',
  'romania': 'RO', 'roumanie': 'RO', 'romanian': 'RO',
  'russia': 'RU', 'russian': 'RU', 'russie': 'RU', 'russe': 'RU',
  'india': 'IN', 'indian': 'IN', 'hindi': 'IN', 'bollywood': 'IN',
  'tamil': 'IN', 'telugu': 'IN', 'punjabi': 'IN',
  'pakistan': 'PK', 'urdu': 'PK',
  'greece': 'GR', 'greek': 'GR', 'grece': 'GR', 'grèce': 'GR',
  'albania': 'AL', 'shqip': 'AL', 'albanie': 'AL', 'albanian': 'AL',
  'kurd': 'KU', 'kurdish': 'KU', 'kurde': 'KU',
  'sweden': 'SE', 'swedish': 'SE', 'svensk': 'SE', 'svenska': 'SE',
  'suede': 'SE', 'suède': 'SE',
  'norway': 'NO', 'norsk': 'NO', 'norwegian': 'NO', 'norvege': 'NO',
  'norvège': 'NO',
  'danmark': 'DK', 'danish': 'DK', 'dansk': 'DK', 'denmark': 'DK',
  'danemark': 'DK',
  'finland': 'FI', 'suomi': 'FI', 'finnish': 'FI', 'finlande': 'FI',
  'afrique': 'AF', 'africa': 'AF', 'african': 'AF', 'africain': 'AF',
  'nollywood': 'AF', 'swahili': 'AF',
  'china': 'CN', 'chinese': 'CN', 'chine': 'CN', 'chinois': 'CN',
  'japan': 'JP', 'japanese': 'JP', 'japon': 'JP', 'anime': 'JP',
  'korea': 'KR', 'korean': 'KR', 'corée': 'KR', 'coree': 'KR', 'kdrama': 'KR',
};

/// Le pays reconnu dans un libellé de catégorie, ou `null`.
///
/// Codes ISO à deux lettres pour les pays, plus trois regroupements qui
/// ne sont pas des pays mais que les fournisseurs utilisent comme tels :
/// `AR` (contenu arabe sans pays précis), `LAT` (latino), `AF` (Afrique).
String? paysDeCategorie(String categorie) {
  final String bas = categorie.trim().toLowerCase();
  if (bas.isEmpty) return null;

  // 1) CODE COURT EN TÊTE : « fr| », « fr - », « fr: », « fr ▶ », « fr »
  //    suivi d'un séparateur ou de la fin. On saute d'abord toute
  //    ponctuation d'ouverture (« |fr| », « [fr] », « (fr) », « ▶ fr »).
  final RegExpMatch? tete = RegExp(
    r'^[^\p{L}\p{N}]*([\p{L}]{2,3})(?=[^\p{L}\p{N}]|$)',
    unicode: true,
  ).firstMatch(bas);
  if (tete != null) {
    final String? p = _codesCourts[tete.group(1)!];
    if (p != null) return p;
  }

  // 2) CODE COURT ENTRE CROCHETS / BARRES, n'importe où : « films [tr] »,
  //    « netflix |ar| ».
  for (final RegExpMatch m in RegExp(
    r'[\[\|\(\{]\s*([\p{L}]{2,3})\s*[\]\|\)\}]',
    unicode: true,
  ).allMatches(bas)) {
    final String? p = _codesCourts[m.group(1)!];
    if (p != null) return p;
  }

  // 3) MOT ENTIER, n'importe où : on découpe sur tout ce qui n'est ni une
  //    lettre ni un chiffre, puis on cherche chaque mot tel quel.
  for (final String mot in bas.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))) {
    if (mot.length < 4) continue;
    final String? p = _motsEntiers[mot];
    if (p != null) return p;
  }
  return null;
}

/// Les catégories, réordonnées par pays : [premier] en tête, puis celles
/// sans pays, puis chaque autre pays groupé, dans l'ordre de première
/// apparition. L'ordre du fournisseur est conservé à l'intérieur de
/// chaque groupe. Ne perd ni ne duplique aucune catégorie.
List<String> ordonnerParPays(List<String> categories, {String premier = 'FR'}) {
  final List<String> enTete = <String>[];
  final List<String> sansPays = <String>[];
  // LinkedHashMap : l'ordre d'insertion est l'ordre de première apparition.
  final Map<String, List<String>> autres = <String, List<String>>{};
  for (final String c in categories) {
    final String? p = paysDeCategorie(c);
    if (p == null) {
      sansPays.add(c);
    } else if (p == premier) {
      enTete.add(c);
    } else {
      (autres[p] ??= <String>[]).add(c);
    }
  }
  return <String>[
    ...enTete,
    ...sansPays,
    for (final List<String> groupe in autres.values) ...groupe,
  ];
}
