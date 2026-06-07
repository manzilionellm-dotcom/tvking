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
  s = s.replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ');

  // 2) Emojis drapeaux (paires d'indicateurs régionaux) + symboles divers.
  s = s.replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '');

  // 3) Lettres modificatrices "exposant/petites capitales" (ᴿᴬᵂ, etc.).
  s = s.replaceAll(RegExp(r'[ʰ-˿ᴬ-ᵪᵸᶻ]'), '');

  // 4) Découpe en mots et retire les tags bruit (comparaison normalisée).
  final List<String> kept = <String>[];
  for (final String w in s.split(RegExp(r'[\s:|/_\-]+'))) {
    if (w.isEmpty) continue;
    final String norm = w.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9+]'), '');
    if (norm.isEmpty) continue;
    if (_kNoiseTags.contains(norm)) continue;
    kept.add(w);
  }

  final String cleaned = kept.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? raw.trim() : cleaned;
}

/// Initiales pour la vignette de secours :
///   - 1 seul mot → 3 premières lettres ;
///   - sinon → initiales des 2 premiers mots.
String logoInitials(String name) {
  final List<String> words = cleanName(name)
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final String w = words.first;
    return (w.length >= 3 ? w.substring(0, 3) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
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
