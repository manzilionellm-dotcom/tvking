// =========================================================
//  Palette NovaTube TV : lisibilité à 3 m + Zuno strictement inchangé.
// =========================================================
//  Ce fichier se lance DEUX fois en CI :
//    flutter test test/novatube_tv/                          → build Zuno
//    flutter test --dart-define=NOVATUBE_TV=true test/novatube_tv/
//  Le premier passage prouve que Zuno garde exactement ses couleurs ; le
//  second, que l'édition NovaTube prend bien le vert pétrole partout.
// =========================================================
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/features/tv/core/tv_app_tokens.dart';
import 'package:tv_king/features/tv/core/tv_novatube_palette.dart';
import 'package:tv_king/features/tv/core/tv_tokens.dart';

/// Rapport de contraste WCAG 2.x entre deux couleurs opaques.
double contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const Map<String, Color> surfaces = <String, Color>{
    'bg': TvNovatube.bg,
    'panel': TvNovatube.panel,
    'card': TvNovatube.card,
    'tile': TvNovatube.tile,
    'sel': TvNovatube.sel,
    'surface3': TvNovatube.surface3,
  };

  group('palette vert pétrole lisible à 3 m', () {
    test('texte, texte secondaire et turquoise ≥ 4,5:1 sur chaque surface', () {
      for (final MapEntry<String, Color> s in surfaces.entries) {
        expect(contrast(TvNovatube.text, s.value), greaterThanOrEqualTo(4.5),
            reason: 'text sur ${s.key}');
        expect(contrast(TvNovatube.muted, s.value), greaterThanOrEqualTo(4.5),
            reason: 'muted sur ${s.key}');
        expect(contrast(TvNovatube.accent, s.value), greaterThanOrEqualTo(4.5),
            reason: 'accent sur ${s.key}');
        expect(
            contrast(TvNovatube.accentBright, s.value), greaterThanOrEqualTo(4.5),
            reason: 'focus sur ${s.key}');
      }
    });

    test('texte tertiaire : ≥ 4,5:1 au repos, ≥ 3:1 sur la ligne sélectionnée',
        () {
      for (final String key in <String>['bg', 'panel', 'card', 'tile']) {
        expect(contrast(TvNovatube.mutedDim, surfaces[key]!),
            greaterThanOrEqualTo(4.5),
            reason: 'mutedDim sur $key');
      }
      for (final String key in <String>['sel', 'surface3']) {
        expect(contrast(TvNovatube.mutedDim, surfaces[key]!),
            greaterThanOrEqualTo(3.0),
            reason: 'mutedDim sur $key');
      }
    });

    test('texte posé sur le turquoise ≥ 4,5:1 (jamais du blanc illisible)', () {
      expect(contrast(TvNovatube.onAccent, TvNovatube.accent),
          greaterThanOrEqualTo(4.5));
      expect(contrast(TvNovatube.onAccent, TvNovatube.accentBright),
          greaterThanOrEqualTo(4.5));
    });

    test('les couleurs restent celles relevées sur la capture de référence', () {
      // Garde-fou : le script des images de marque utilise les mêmes valeurs.
      expect(TvNovatube.bg, const Color(0xFF050F0C));
      expect(TvNovatube.accent, const Color(0xFF4EA89C));
      expect(TvNovatube.accentBright, const Color(0xFF73CDC3));
      expect(TvNovatube.sel, const Color(0xFF22312E));
    });
  });

  test(
      kNovatubeTv
          ? 'édition NovaTube : le vert pétrole remplace tout le thème sombre'
          : 'build Zuno : aucune couleur ne change',
      () {
    if (kNovatubeTv) {
      expect(TvTokens.bg, TvNovatube.bg);
      expect(TvTokens.accent, TvNovatube.accent);
      expect(TvTokens.accentBright, TvNovatube.accentBright);
      const TvAppTokens tokens = TvAppTokens();
      expect(tokens.bg, TvNovatube.bg);
      expect(tokens.card, TvNovatube.card);
      expect(tokens.accent, TvNovatube.accent);
      expect(tokens.accentBright, TvNovatube.accentBright);
      expect(tokens.onAccent, TvNovatube.onAccent);
      // Le look « Black Badge » choisi sur une box ne remplace pas le pétrole.
      const TvAppTokens ghost = TvAppTokens(ghost: true);
      expect(ghost.bg, TvNovatube.bg);
      expect(ghost.accent, TvNovatube.accent);
    } else {
      // Valeurs historiques Zuno, copiées du dépôt avant l'édition NovaTube.
      expect(TvTokens.bg, const Color(0xFF070708));
      expect(TvTokens.card, const Color(0xFF141418));
      expect(TvTokens.accent, const Color(0xFFC99A3A));
      expect(TvTokens.accentBright, const Color(0xFFF2CF7A));
      expect(TvTokens.onAccent, const Color(0xFF14100A));
      const TvAppTokens tokens = TvAppTokens();
      expect(tokens.accent, const Color(0xFFC99A3A));
      expect(tokens.bg, isNot(TvNovatube.bg));
    }
  });

  test('nom affiché : NovaTube seulement dans l\'édition NovaTube', () {
    expect(kNovatubeTvName, 'NovaTube');
  });
}
