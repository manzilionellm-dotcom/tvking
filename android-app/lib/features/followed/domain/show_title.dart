// =========================================================
//  show_title.dart — Même émission, titres un peu différents
// =========================================================
//  Le guide écrit parfois « Plus belle la vie S02E05 » et
//  parfois « Plus belle la vie ». Pour l'app, c'est la même
//  série. On compare une clé simple :
//    • minuscules, sans accent ;
//    • sans le numéro d'épisode (S01E02, 1x03, épisode 4) ;
//    • espaces collés.
//  Une clé trop courte (une lettre) ne compte pas : elle
//  matcherait n'importe quoi.
// =========================================================

/// Au moins deux lettres, sinon on ignore le titre.
const int kShowKeyMin = 2;

final RegExp _episodeMark = RegExp(
  r'\b('
  r's\d{1,2}\s*e\d{1,3}'
  r'|saison\s*\d+'
  r'|episode\s*\d+'
  r'|ep\s*\d+'
  r'|\d{1,2}x\d{1,3}'
  r')\b',
);

const Map<String, String> _fold = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'œ': 'oe',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

/// Clé de comparaison. Vide si le titre ne veut rien dire.
String showKey(String raw) {
  String s = raw.toLowerCase().trim();
  if (s.isEmpty) return '';
  final StringBuffer buf = StringBuffer();
  for (final int rune in s.runes) {
    final String ch = String.fromCharCode(rune);
    buf.write(_fold[ch] ?? ch);
  }
  s = buf.toString();
  s = s.replaceAll(_episodeMark, ' ');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length < kShowKeyMin) return '';
  return s;
}
