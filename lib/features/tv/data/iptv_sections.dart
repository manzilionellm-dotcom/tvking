// =========================================================
//  iptv_sections.dart — Le menu latéral du Modèle B
// =========================================================
//  Le client veut « les 5 pays » en haut du menu, puis Sports, Films,
//  International et Favoris. Sa maquette les écrivait EN DUR (France,
//  Royaume-Uni, États-Unis, Allemagne, Espagne) — or son bouquet du soir
//  est belge : cinq sections vides. On DÉDUIT donc les pays du bouquet
//  réel, en gardant exactement sa structure de menu.
//
//  Méthode : les catégories d'un panel IPTV portent presque toujours le
//  pays dans leur nom (« TV || FRANCE HD », « BE| BELGIUM VIP », « UK |
//  SPORTS »). On repère le pays par mots-clés, on additionne les chaînes
//  par pays, et on garde les 5 plus fournis. Aucun réseau, aucune base :
//  fonction PURE, donc testable et instantanée.
// =========================================================
import '../../channels/domain/channel.dart';

/// Une entrée du menu latéral.
class IptvSection {
  const IptvSection({
    required this.id,
    required this.label,
    required this.emoji,
    this.count = 0,
  });

  /// Identifiant stable (`fr`, `sports`, `favoris`…).
  final String id;

  /// Libellé affiché (« France », « Sports »…).
  final String label;

  /// Drapeau ou pictogramme, comme dans la maquette du client.
  final String emoji;

  /// Nombre de chaînes (0 pour les sections calculées à la volée).
  final int count;
}

/// Pays reconnus : mots-clés qu'on cherche dans le nom de catégorie.
/// L'ordre compte peu ; les libellés sont en français.
const Map<String, ({String label, String emoji, List<String> keys})>
    kIptvCountries =
    <String, ({String label, String emoji, List<String> keys})>{
  'fr': (
    label: 'France',
    emoji: '🇫🇷',
    keys: <String>['FRANCE', 'FRENCH', 'FR|']
  ),
  'be': (label: 'Belgique', emoji: '🇧🇪', keys: <String>['BELGI', 'BE|']),
  'uk': (
    label: 'Royaume-Uni',
    emoji: '🇬🇧',
    keys: <String>['UNITED KINGDOM', 'UK|', 'UK ', 'BRITISH', 'IRELAND']
  ),
  'us': (
    label: 'États-Unis',
    emoji: '🇺🇸',
    keys: <String>['USA', 'UNITED STATES', 'US|', 'AMERICA']
  ),
  'de': (
    label: 'Allemagne',
    emoji: '🇩🇪',
    keys: <String>['GERMAN', 'DEUTSCH', 'DE|']
  ),
  'es': (
    label: 'Espagne',
    emoji: '🇪🇸',
    keys: <String>['SPAIN', 'SPANISH', 'ES|']
  ),
  'it': (
    label: 'Italie',
    emoji: '🇮🇹',
    keys: <String>['ITALY', 'ITALIA', 'IT|']
  ),
  'nl': (
    label: 'Pays-Bas',
    emoji: '🇳🇱',
    keys: <String>['NETHERLAND', 'DUTCH', 'NL|']
  ),
  'pt': (
    label: 'Portugal',
    emoji: '🇵🇹',
    keys: <String>['PORTUGAL', 'PORTUGUES', 'PT|']
  ),
  'ma': (
    label: 'Maroc',
    emoji: '🇲🇦',
    keys: <String>['MOROCCO', 'MAROC', 'MA|']
  ),
  'ar': (label: 'Monde arabe', emoji: '🌙', keys: <String>['ARABIC', 'ARAB']),
  'tr': (
    label: 'Turquie',
    emoji: '🇹🇷',
    keys: <String>['TURKEY', 'TURKISH', 'TR|']
  ),
};

/// Pays d'une catégorie, ou `null` si on ne reconnaît rien.
String? countryOfCategory(String category) {
  final String up = category.toUpperCase();
  for (final MapEntry<String,
          ({String label, String emoji, List<String> keys})> e
      in kIptvCountries.entries) {
    for (final String k in e.value.keys) {
      if (up.contains(k)) return e.key;
    }
  }
  return null;
}

/// Les [max] pays les mieux fournis du bouquet, du plus gros au plus petit.
/// [countsByCategory] = nombre de chaînes par nom de catégorie.
List<IptvSection> topCountrySections(
  Map<String, int> countsByCategory, {
  int max = 5,
}) {
  final Map<String, int> perCountry = <String, int>{};
  countsByCategory.forEach((String cat, int n) {
    final String? c = countryOfCategory(cat);
    if (c != null) perCountry[c] = (perCountry[c] ?? 0) + n;
  });
  final List<MapEntry<String, int>> sorted = perCountry.entries.toList()
    ..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
      final int byCount = b.value.compareTo(a.value);
      // Départage stable par identifiant : deux pays à égalité gardent
      // toujours le même ordre d'un lancement à l'autre.
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return <IptvSection>[
    for (final MapEntry<String, int> e in sorted.take(max))
      IptvSection(
        id: e.key,
        label: kIptvCountries[e.key]!.label,
        emoji: kIptvCountries[e.key]!.emoji,
        count: e.value,
      ),
  ];
}

/// Sections FIXES du bas de menu, dans l'ordre voulu par le client.
const List<IptvSection> kIptvFixedSections = <IptvSection>[
  IptvSection(id: 'sports', label: 'Sports', emoji: '⚽'),
  IptvSection(id: 'films', label: 'Films', emoji: '🎬'),
  IptvSection(id: 'international', label: 'International', emoji: '🌍'),
  IptvSection(id: 'favoris', label: 'Favoris', emoji: '❤️'),
];

/// Rang de genre pour l'ordre voulu par le client dans une section : le
/// SPORT d'abord, puis l'INFO, puis le reste — l'adulte toujours en
/// dernier. Fonction pure : testable, aucun état.
int iptvGenreRank(ChannelGenre g) {
  switch (g) {
    case ChannelGenre.sports:
      return 0;
    case ChannelGenre.news:
      return 1;
    case ChannelGenre.movies:
      return 2;
    case ChannelGenre.series:
      return 3;
    case ChannelGenre.entertainment:
      return 4;
    case ChannelGenre.documentary:
      return 5;
    case ChannelGenre.kids:
      return 6;
    case ChannelGenre.music:
      return 7;
    case ChannelGenre.international:
    case ChannelGenre.other:
      return 8;
    case ChannelGenre.adult:
      return 9;
  }
}

/// Trie EN PLACE les chaînes d'une section : genre (ci-dessus), puis la
/// chaîne qui s'ouvre le mieux CHEZ CE FOYER (score de fiabilité n°38),
/// puis l'ordre alphabétique. Ce dernier critère rend le tri STABLE d'un
/// lancement à l'autre : la grille ne danse jamais.
///
/// [scoreOf] renvoie `null` quand la chaîne n'a pas assez d'essais pour
/// qu'on ait un avis honnête : on la place alors à 0,75 — devant une
/// chaîne dont on SAIT qu'elle échoue, derrière une valeur sûre.
void sortIptvChannels(
  List<Channel> list, {
  double? Function(String id)? scoreOf,
}) {
  list.sort((Channel a, Channel b) {
    final int byGenre =
        iptvGenreRank(a.genre).compareTo(iptvGenreRank(b.genre));
    if (byGenre != 0) return byGenre;
    final double sa = (scoreOf == null ? null : scoreOf(a.id)) ?? 0.75;
    final double sb = (scoreOf == null ? null : scoreOf(b.id)) ?? 0.75;
    final int byScore = sb.compareTo(sa);
    if (byScore != 0) return byScore;
    return a.cleanName.toLowerCase().compareTo(b.cleanName.toLowerCase());
  });
}

/// Mots-clés des sections thématiques.
const List<String> kSportsKeys = <String>[
  'SPORT',
  'FOOT',
  'LIGUE',
  'DAZN',
  'BEIN',
  'ESPN',
  'MOTOGP',
  'F1',
];
const List<String> kFilmsKeys = <String>[
  'CINEMA',
  'CINÉMA',
  'MOVIE',
  'FILM',
  'VOD',
];
