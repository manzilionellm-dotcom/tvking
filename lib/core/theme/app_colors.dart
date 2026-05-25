// =========================================================
//  app_colors.dart — Facade Cinema Mode du système LUMIÈRE
// =========================================================
//  IMPORTANT — Cette classe n'est PAS la source de vérité.
//  C'est une façade statique qui réplique le `LumiereColors.cinema`
//  pour permettre les `const Color(...)` dans le code existant
//  (les `const` constructors ne peuvent pas lire `Theme.of(context)`).
//
//  Source canonique : `lumiere_tokens.dart` → `LumiereColors`.
//
//  - Pour un composant qui DOIT s'adapter aux deux modes
//    (Cinema / Daylight) → utiliser `LumiereColors.of(context).X`.
//  - Pour un composant qui reste en Cinema Mode permanent
//    (splash, lecteur vidéo plein écran, mini-bar de cast) →
//    utiliser `AppColors.X` (raccourci const).
//
//  Règle absolue : aucun `Color(0xFF...)` ailleurs dans l'app.
// =========================================================

import 'package:flutter/material.dart';

import 'lumiere_tokens.dart';

abstract final class AppColors {
  // -------------------------------------------------------
  //  FONDS / SURFACES (Cinema Mode)
  // -------------------------------------------------------

  /// Fond principal de l'app — `surface.canvas` LUMIÈRE.
  static const Color background = Color(0xFF0E0B14);

  /// Surface "vide" la plus profonde — `surface.void`. Splash,
  /// lecteur vidéo plein écran. Jamais le noir pur — toujours
  /// teinté aubergine pour rester soft sur OLED.
  static const Color voidSurface = Color(0xFF0A0810);

  /// Surface élevée (cards, panels, sheets) — `surface.elevated`.
  static const Color surface = Color(0xFF16121C);

  /// Glassmorphism — `surface.glass`. À combiner avec BackdropFilter.
  static const Color surfaceHigh = Color(0xFF1C1826);

  /// Overlay le plus haut — `surface.overcast`. Modals, snackbars.
  static const Color surfaceOverlay = Color(0xFF221D2D);

  /// Liseré subtil (text.primary @ 8% alpha).
  static Color get border => const Color(0xFFF4EDE4).withValues(alpha: 0.08);

  // -------------------------------------------------------
  //  ACCENT CHAMPAGNE
  // -------------------------------------------------------

  /// Accent principal — champagne chaud LUMIÈRE.
  static const Color accent = Color(0xFFD4B483);

  /// Variante claire — états focus / hover / brillance.
  static const Color accentBright = Color(0xFFE8C896);

  /// Variante deep — bordures actives, états sélectionnés passifs.
  static const Color accentMuted = Color(0xFF9C8359);

  /// Halo cuivré — utilisé pour les glows champagne sur CTAs primaires.
  static const Color brassGlow = Color(0xFFB8965E);

  /// Voile très léger d'accent — fond d'un état sélectionné.
  static Color get accentSurface =>
      const Color(0xFFD4B483).withValues(alpha: 0.12);

  // -------------------------------------------------------
  //  TEXTE
  // -------------------------------------------------------

  /// Texte principal — `text.primary`. Ivoire chaud, jamais blanc pur.
  static const Color textPrimary = Color(0xFFF4EDE4);

  /// Sous-titres, métadonnées importantes.
  static const Color textSecondary = Color(0xFFC8BFB2);

  /// Niveau intermédiaire — métadonnées discrètes.
  static const Color textTertiary = Color(0xFF8A8278);

  /// Texte estompé — hints, timestamps, états désactivés.
  static const Color textMuted = Color(0xFF5C564E);

  // -------------------------------------------------------
  //  STATUTS SÉMANTIQUES
  // -------------------------------------------------------

  /// Vert apaisé — confirmations, OK. Jamais néon.
  static const Color success = Color(0xFF7FB890);

  /// Ambre champagne — buffering, attentions douces.
  static const Color warning = Color(0xFFD4A574);

  /// Rouge bordeaux — erreurs critiques + badge LIVE. Volontairement
  /// pas Netflix red ni un rouge saturé : un bordeaux chaud qui
  /// alerte sans agresser.
  static const Color live = Color(0xFFC97064);

  /// Bleu cendre froid — info neutre.
  static const Color info = Color(0xFF8FA8C4);

  // -------------------------------------------------------
  //  GRADIENTS RÉUTILISÉS
  // -------------------------------------------------------

  /// Dégradé de fond global de l'app — très subtil pour donner
  /// de la profondeur sans détourner le regard du contenu.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF14101D),
      Color(0xFF0E0B14),
      Color(0xFF09070D),
    ],
  );

  /// Voile de lecture sur images / vignettes pour rendre le texte
  /// blanc lisible par-dessus. À appliquer en `Positioned.fill`.
  static const LinearGradient cardScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0x000A0810),
      Color(0x000A0810),
      Color(0xCC0A0810),
    ],
    stops: <double>[0.0, 0.4, 1.0],
  );

  /// Halo champagne — pour les ombres lumineuses sur CTAs primaires.
  static List<BoxShadow> get champagneGlow => <BoxShadow>[
        BoxShadow(
          color: const Color(0xFFB8965E).withValues(alpha: 0.28),
          blurRadius: 28,
          spreadRadius: 1,
        ),
      ];

  // -------------------------------------------------------
  //  ALIAS DÉPRÉCIÉS (compatibilité historique)
  // -------------------------------------------------------
  //  L'ancienne identité utilisait or et rose/cyan. Les noms sont
  //  conservés pour ne pas casser l'existant, mais redirigent
  //  désormais vers la palette LUMIÈRE champagne.
  // -------------------------------------------------------

  @Deprecated('Use AppColors.accent (champagne)')
  static const Color accentPink = accent;

  @Deprecated('Use AppColors.textSecondary or AppColors.brassGlow')
  static const Color accentCyan = textSecondary;

  @Deprecated('Use AppColors.accent (champagne)')
  static const Color gold = accent;

  /// Dégradé premium (champagne → champagne deep) — pour les CTAs
  /// principaux et les badges "Premium".
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[accent, accentMuted],
  );

  /// Helper pour accéder à la palette context-aware (les deux modes).
  /// Sucre syntaxique sur `LumiereColors.of(context)`.
  static LumiereColors lumiere(BuildContext context) =>
      LumiereColors.of(context);
}
