// =========================================================
//  voice_query.dart — Comprendre une phrase dite au micro
// =========================================================
//  Pas d'IA ici. On range la phrase dans deux cases, sur la box :
//
//    • « ce soir »  → l'assistant lit le guide des programmes (EPG)
//      déjà téléchargé. Aucun service payant, aucun réseau.
//    • tout le reste → recherche dans la playlist (chaînes, films,
//      séries) par les mots du titre.
//
//  La fonction ne lance rien : pas de micro, pas de base, pas de
//  lecteur. Elle ne peut pas bloquer une chaîne. Les tests l'appellent
//  avec des phrases toutes faites.
// =========================================================

import '../../cinema/domain/cinema_language.dart';

/// Ce que la phrase demande.
enum VoiceIntentKind {
  /// Rien d'utilisable (silence, espaces).
  empty,

  /// « Qu'est-ce qu'il y a ce soir ? »
  tonight,

  /// Un titre ou des mots à chercher dans la playlist.
  catalog,
}

/// Résultat de [interpretVoice]. Immuable.
class VoiceIntent {
  const VoiceIntent._(this.kind, this.catalogQuery);

  final VoiceIntentKind kind;

  /// Mots à chercher quand [kind] est [VoiceIntentKind.catalog].
  /// Vide sinon.
  final String catalogQuery;

  static const VoiceIntent empty = VoiceIntent._(VoiceIntentKind.empty, '');

  static const VoiceIntent tonight = VoiceIntent._(VoiceIntentKind.tonight, '');

  const VoiceIntent.catalog(String query)
      : kind = VoiceIntentKind.catalog,
        catalogQuery = query;
}

/// Mots qui ne sont pas un titre : ordres (« cherche »), formules
/// (« qu'est-ce qu'il y a ») et petits mots (« le », « un »).
const Set<String> _kStopwords = <String>{
  'qu', 'est', 'ce', 'il', 'y', 'a', 'au', 'aux', 'quoi', 'que', 'qui',
  'regarder', 'voir', 'passe', 'passer', 'diffuse', 'diffusion',
  'programme', 'programmes', 'emission', 'emissions',
  'tv', 'tele', 'television', 'guide', 'soir', 'soiree', 'evening',
  'tonight', 'today', 'horaire', 'horaires',
  'what', 'whats', 'is', 'on', 'there', 'this', 'the', 'something',
  'anything', 'please', 'show', 'me', 'for',
  'esta', 'noche', 'hay', 'heute', 'abend', 'vanavond', 'stasera',
  'hoje', 'noite',
  'dis', 'moi', 'pour', 'de', 'du', 'des', 'la', 'le', 'les',
  'un', 'une', 'an', 'of', 'stp', 's',
  'cherche', 'chercher', 'recherche', 'rechercher', 'trouve', 'trouver',
  'mets', 'met', 'joue', 'jouer', 'lance', 'lancer', 'ouvre', 'ouvrir',
  'montre', 'montrer', 'search', 'find', 'play', 'put',
  // « un film ce soir » = la question du soir, pas un titre « film ».
  'film', 'films', 'movie', 'movies', 'serie', 'series', 'cinema',
};

/// Formules qui veulent le guide du soir (les plus longues d'abord,
/// pour ne pas couper « what is on » en laissant « what is »).
const List<String> _kTonightMarkers = <String>[
  'qu est ce qu il y a',
  'what is on',
  'what s on',
  'whats on',
  'ce soir',
  'tonight',
  'this evening',
  'esta noche',
  'heute abend',
  'vanavond',
  'hoje a noite',
  'au programme',
  'a la tele',
  'a la television',
];

/// Phrases entières = guide du soir, même sans le marqueur « ce soir ».
const Set<String> _kTonightPhrases = <String>{
  'quoi a la tele',
  'que regarder',
  'whats on',
  'what s on',
  'what is on',
  'was lauft heute',
  'was lauft',
};

/// Petits mots retirés d'une recherche (« cherche un film » → « film »),
/// seulement s'il reste un vrai mot après.
const Set<String> _kLightWords = <String>{
  'le', 'la', 'les', 'un', 'une', 'des', 'de', 'du', 'the', 'a', 'an', 'of',
  'd', 'l',
};

/// Passe la phrase en minuscules, sans accents, sans ponctuation.
/// On borne la longueur : une reco vocale folle ne doit pas nous
/// faire travailler sur un roman.
String voiceFold(String raw) {
  final String clipped = raw.length > 300 ? raw.substring(0, 300) : raw;
  final String spaced = clipped
      .replaceAll(RegExp("[’'`´]"), ' ')
      .replaceAll(RegExp(r'[-–—_/]+'), ' ');
  final String key = CinemaLanguage.searchKey(spaced);
  return key
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Range [raw] dans « vide », « ce soir » ou « recherche ».
VoiceIntent interpretVoice(String raw) {
  final String folded = voiceFold(raw);
  if (folded.isEmpty) return VoiceIntent.empty;
  if (_kTonightPhrases.contains(folded)) return VoiceIntent.tonight;

  final _MarkerCut cut = _cutTonightMarker(folded);
  if (cut.hit) {
    final String leftover = _withoutStopwords(cut.text);
    if (leftover.isEmpty) return VoiceIntent.tonight;
    // « TF1 ce soir » : on cherche TF1, on n'ouvre pas tout le guide.
    return VoiceIntent.catalog(leftover);
  }

  final String query = _catalogQuery(folded);
  if (query.isEmpty) return VoiceIntent.empty;
  return VoiceIntent.catalog(query);
}

/// Mots du catalogue (déjà normalisés) pour la recherche.
List<String> voiceWords(String catalogQuery) => catalogQuery
    .split(' ')
    .where((String w) => w.isNotEmpty)
    .toList(growable: false);

class _MarkerCut {
  const _MarkerCut(this.text, this.hit);
  final String text;
  final bool hit;
}

_MarkerCut _cutTonightMarker(String folded) {
  String text = folded;
  bool hit = false;
  for (final String marker in _kTonightMarkers) {
    final int i = _indexAsWord(text, marker);
    if (i < 0) continue;
    final int end = i + marker.length;
    text = '${text.substring(0, i)} ${text.substring(end)}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    hit = true;
  }
  return _MarkerCut(text, hit);
}

/// [needle] doit être un mot ou un groupe de mots entier, pas un
/// morceau au milieu d'un autre mot (« soir » dans « soirée » est
/// déjà géré parce qu'on compare des mots séparés par des espaces).
int _indexAsWord(String hay, String needle) {
  int from = 0;
  while (from <= hay.length) {
    final int i = hay.indexOf(needle, from);
    if (i < 0) return -1;
    final bool left = i == 0 || hay[i - 1] == ' ';
    final int end = i + needle.length;
    final bool right = end == hay.length || hay[end] == ' ';
    if (left && right) return i;
    from = i + 1;
  }
  return -1;
}

String _withoutStopwords(String folded) {
  final List<String> keep = <String>[];
  for (final String w in folded.split(' ')) {
    if (w.isEmpty || _kStopwords.contains(w)) continue;
    keep.add(w);
  }
  return keep.join(' ');
}

String _catalogQuery(String folded) {
  final List<String> parts =
      folded.split(' ').where((String w) => w.isNotEmpty).toList();
  int i = 0;
  while (i < parts.length && _kStopwords.contains(parts[i]) && _isCommand(parts[i])) {
    i++;
  }
  // Que des ordres (« cherche ») : on garde la phrase, la recherche
  // ne trouvera rien plutôt que d'effacer ce que la personne a dit.
  if (i == parts.length) return folded;
  final List<String> rest = parts.sublist(i);
  final List<String> content =
      rest.where((String w) => !_kLightWords.contains(w)).toList();
  if (content.isEmpty) return rest.join(' ');
  return content.join(' ');
}

const Set<String> _kCommands = <String>{
  'cherche', 'chercher', 'recherche', 'rechercher', 'trouve', 'trouver',
  'mets', 'met', 'joue', 'jouer', 'lance', 'lancer', 'ouvre', 'ouvrir',
  'montre', 'montrer', 'search', 'find', 'play', 'put', 'dis',
};

bool _isCommand(String w) => _kCommands.contains(w);
