// =========================================================
//  channel_curation.dart — Nettoyage & curation d'affichage
// =========================================================
//  Fonctions PURES (sans Flutter sauf Color), faciles à tester :
//    - cleanName()          : nom propre pour seniors (sans bruit).
//    - logoInitials()       : initiales pour la vignette de secours.
//    - logoFallbackColor()  : couleur déterministe (hash du nom).
//  Aucune dépendance au cast.
// =========================================================

import 'dart:ui' show Color;

/// Tags "bruit" retirés quand ils apparaissent comme MOT entier.
const Set<String> _kNoiseTags = <String>{
  'RAW', 'HD', 'FHD', 'UHD', '4K', '8K', 'SD', 'VIP', 'HQ', 'HEVC',
  'US', 'USA', 'UK', 'FHDP', 'H265', 'H264',
};

// PERF (audit fluidité 2026-07-31) : ces fonctions tournent pour CHAQUE
// vignette de CHAQUE ligne pendant le défilement — recompiler 5+ RegExp
// par appel coûtait cher sur petit matériel. Compilées UNE fois ici.
final RegExp _reBrackets = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]');
final RegExp _reFlags = RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true);
final RegExp _reSuperscript = RegExp(r'[ʰ-˿ᴬ-ᵪᵸᶻ]');
final RegExp _reWordSplit = RegExp(r'[\s:|/_\-]+');
final RegExp _reNonAlnum = RegExp(r'[^A-Z0-9+]');
final RegExp _reSpaces = RegExp(r'\s+');

/// Mémo des initiales par nom : lu à chaque frame de scroll pour les
/// vignettes de secours — borné (evict simple au-delà de 4 000 entrées).
final Map<String, String> _initialsMemo = <String, String>{};

/// Nettoie un nom de chaîne pour l'affichage :
///   - retire les emojis drapeaux (indicateurs régionaux) ;
///   - retire les lettres "exposant" (ex. ᴿᴬᵂ) ;
///   - retire le contenu entre ( ), [ ], { } (ex. "(flsp 516)") ;
///   - retire les tags bruit (RAW, HD, 4K, VIP, US…) ;
///   - réduit les espaces multiples.
/// Si tout est retiré, on retombe sur le nom d'origine (jamais vide).
String cleanName(String raw) {
  String s = raw;

  // 1) Contenu entre parenthèses/crochets/accolades → espace.
  s = s.replaceAll(_reBrackets, ' ');

  // 2) Emojis drapeaux (paires d'indicateurs régionaux) + symboles divers.
  s = s.replaceAll(_reFlags, '');

  // 3) Lettres modificatrices "exposant/petites capitales" (ᴿᴬᵂ, etc.).
  s = s.replaceAll(_reSuperscript, '');

  // 4) Découpe en mots et retire les tags bruit (comparaison normalisée).
  final List<String> kept = <String>[];
  for (final String w in s.split(_reWordSplit)) {
    if (w.isEmpty) continue;
    final String norm = w.toUpperCase().replaceAll(_reNonAlnum, '');
    if (norm.isEmpty) continue;
    if (_kNoiseTags.contains(norm)) continue;
    kept.add(w);
  }

  final String cleaned = kept.join(' ').replaceAll(_reSpaces, ' ').trim();
  return cleaned.isEmpty ? raw.trim() : cleaned;
}

/// Initiales pour la vignette de secours :
///   - 1 seul mot → 3 premières lettres ;
///   - sinon → initiales des 2 premiers mots.
/// Mémoïsé par nom (appelé à chaque frame de scroll).
String logoInitials(String name) {
  final String? memo = _initialsMemo[name];
  if (memo != null) return memo;

  final List<String> words = cleanName(name)
      .split(_reSpaces)
      .where((String w) => w.isNotEmpty)
      .toList();
  final String out;
  if (words.isEmpty) {
    out = '?';
  } else if (words.length == 1) {
    final String w = words.first;
    out = (w.length >= 3 ? w.substring(0, 3) : w).toUpperCase();
  } else {
    out = (words[0][0] + words[1][0]).toUpperCase();
  }
  // Garde-fou mémoire : playlist géante → on repart d'un cache vide
  // plutôt que de grossir sans borne.
  if (_initialsMemo.length > 4000) _initialsMemo.clear();
  _initialsMemo[name] = out;
  return out;
}

/// Couleur de fond déterministe (même nom → même couleur). Teinte issue
/// d'un hash du nom, saturation douce + luminosité basse → fond sombre
/// premium sur lequel le texte clair ressort (contraste fort seniors).
Color logoFallbackColor(String name) {
  int hash = 0;
  for (final int c in name.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  final double hue = (hash % 360).toDouble();
  return _hsl(hue, 0.32, 0.26);
}

/// HSL → Color (sans dépendance Material : on convertit à la main).
Color _hsl(double h, double s, double l) {
  final double c = (1 - (2 * l - 1).abs()) * s;
  final double x = c * (1 - (((h / 60) % 2) - 1).abs());
  final double m = l - c / 2;
  double r = 0, g = 0, b = 0;
  if (h < 60) {
    r = c; g = x;
  } else if (h < 120) {
    r = x; g = c;
  } else if (h < 180) {
    g = c; b = x;
  } else if (h < 240) {
    g = x; b = c;
  } else if (h < 300) {
    r = x; b = c;
  } else {
    r = c; b = x;
  }
  int to(double v) => ((v + m) * 255).round().clamp(0, 255);
  return Color.fromARGB(255, to(r), to(g), to(b));
}
