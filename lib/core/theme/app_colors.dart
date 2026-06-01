// =========================================================
//  app_colors.dart — Facade Cinema Mode du système 7 MOTION
// =========================================================
//  IMPORTANT — Cette classe n'est PAS la source de vérité.
//  C'est une façade statique qui réplique le `LumiereColors.cinema`
//  pour permettre les `const Color(...)` dans le code existant.
//
//  Source canonique : `lumiere_tokens.dart` → `LumiereColors`.
//
//  - Composant qui DOIT s'adapter aux deux modes →
//    `LumiereColors.of(context).X`.
//  - Composant qui reste en Cinema Mode permanent (splash, lecteur
//    vidéo plein écran, mini-bar de cast) → `AppColors.X`.
//
//  Règle : aucun `Color(0xFF...)` ailleurs dans l'app.
// =========================================================

import 'package:flutter/material.dart';

import 'lumiere_tokens.dart';

abstract final class AppColors {
  // -------------------------------------------------------
  //  FONDS / SURFACES (Cinema Mode 7 MOTION)
  // -------------------------------------------------------

  /// Fond principal — charbon presque noir avec une trace de chaleur.
  static const Color background = Color(0xFF0A0A0C);

  /// Surface la plus profonde — splash, vidéo plein écran.
  static const Color voidSurface = Color(0xFF050507);

  /// Surface élevée (cards, panels, sheets).
  static const Color surface = Color(0xFF14141A);

  /// Glassmorphism — à combiner avec BackdropFilter.
  static const Color surfaceHigh = Color(0xFF1C1C24);

  /// Overlay le plus haut (modals, snackbars).
  static const Color surfaceOverlay = Color(0xFF28282F);

  /// Liseré subtil (textPrimary @ 8% alpha).
  static Color get border => const Color(0xFFF0EDE9).withValues(alpha: 0.08);

  // -------------------------------------------------------
  //  PALETTE CINÉMA — niveaux supplémentaires (Phase 1 redesign)
  // -------------------------------------------------------
  //  Surfaces étagées pour la profondeur "directed film scene".
  //  Le rythme va de obsidian (fond le plus profond) à ash
  //  (overlay le plus haut), avec des transitions chaudes-froides
  //  imperceptibles qui donnent la sensation de stratification.

  /// Niveau 0 — obsidian. Fond principal sur grandes surfaces
  /// cinéma (home, hero plein écran).
  static const Color obsidian = Color(0xFF0E0E12);

  /// Niveau 1 — midnight. Première élévation pour les rails.
  static const Color midnight = Color(0xFF16161C);

  /// Niveau 2 — slate. Cards posters, chips.
  static const Color slate = Color(0xFF1F1F26);

  /// Niveau 3 — ash. Overlays, sheets, modal headers.
  static const Color ash = Color(0xFF2A2A33);

  /// Voile glass — surface translucide pour BackdropFilter
  /// (dock flottant, app bars translucides).
  static Color get glassSurface =>
      const Color(0xFF14141A).withValues(alpha: 0.55);

  /// Liseré ultra-subtil pour les verres flottants.
  static Color get glassBorder =>
      const Color(0xFFF0EDE9).withValues(alpha: 0.06);

  // -------------------------------------------------------
  //  ACCENT EMBER (rouge braise 7 MOTION)
  // -------------------------------------------------------

  /// Accent principal — ember-red. Saturé mais profond, jamais Netflix-red.
  static const Color accent = Color(0xFFD63A30);

  /// Variante claire — ember glow, états focus / hover / brillance.
  static const Color accentBright = Color(0xFFFF5A4A);

  /// Variante deep — ember-blood, bordures actives, sélections passives.
  static const Color accentMuted = Color(0xFF8E1F1D);

  /// Halo ember — pour les glows champagne sur CTAs primaires.
  /// (Nom historique conservé pour compat — c'est le même rouge brillant.)
  static const Color brassGlow = Color(0xFFFF5A4A);

  /// Voile très léger d'accent — fond d'un état sélectionné.
  static Color get accentSurface =>
      const Color(0xFFD63A30).withValues(alpha: 0.14);

  // -------------------------------------------------------
  //  CHAMPAGNE — accent non-critique (Phase 1 redesign)
  // -------------------------------------------------------
  //  Le brief design dit : réduire l'usage du rouge de 60-70 %.
  //  Le rouge ne sert PLUS qu'au critique (LIVE, focus actif,
  //  CTA primaire, sélection navigation). Pour tous les autres
  //  accents (eyebrows, badges éditoriaux, "VEDETTE",
  //  séparateurs de catégorie, citations…) on utilise un
  //  champagne désaturé qui donne la sensation premium calme
  //  d'Apple TV+ ou de Criterion Channel.

  /// Champagne — accent éditorial principal (eyebrows, badges
  /// "À LA UNE", "RECOMMANDÉ", "NOUVEAU"). Ni or jaune
  /// agressif ni rouge — un crème chaud très tamisé.
  static const Color champagne = Color(0xFFE8D9C0);

  /// Champagne profond — pour les bordures fines et les hovers
  /// non-critiques. Encore plus discret que `champagne`.
  static const Color champagneDeep = Color(0xFFB39B7C);

  /// Voile champagne — fond des chips éditoriaux.
  static Color get champagneSurface =>
      const Color(0xFFE8D9C0).withValues(alpha: 0.10);

  // -------------------------------------------------------
  //  TEXTE
  // -------------------------------------------------------

  /// Texte principal — ivoire chaud, jamais blanc pur.
  static const Color textPrimary = Color(0xFFF0EDE9);

  /// Sous-titres, métadonnées importantes.
  static const Color textSecondary = Color(0xFFB6B0A8);

  /// Niveau intermédiaire — métadonnées discrètes.
  static const Color textTertiary = Color(0xFF7E7872);

  /// Texte estompé — hints, timestamps, états désactivés.
  static const Color textMuted = Color(0xFF4E4A45);

  // -------------------------------------------------------
  //  STATUTS SÉMANTIQUES
  // -------------------------------------------------------

  /// Vert apaisé — confirmations, OK. Jamais néon.
  static const Color success = Color(0xFF5FA975);

  /// Ambre / orange — buffering, attentions douces.
  static const Color warning = Color(0xFFD69847);

  /// Erreur critique + badge LIVE — ember-glow (légèrement plus
  /// orangé que l'accent principal pour se distinguer en alerte).
  static const Color live = Color(0xFFE84A3E);

  /// Bleu cendre froid — info neutre.
  static const Color info = Color(0xFF6A8DB0);

  // -------------------------------------------------------
  //  GRADIENTS RÉUTILISÉS
  // -------------------------------------------------------

  /// Dégradé de fond global — très subtil, donne la profondeur sans
  /// distraire du contenu.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF101012),
      Color(0xFF0A0A0C),
      Color(0xFF050507),
    ],
  );

  /// Voile de lecture sur images / vignettes.
  static const LinearGradient cardScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0x00050507),
      Color(0x00050507),
      Color(0xCC050507),
    ],
    stops: <double>[0.0, 0.4, 1.0],
  );

  /// Halo ember — pour les ombres rouge braise sur CTAs primaires.
  static List<BoxShadow> get champagneGlow => <BoxShadow>[
        BoxShadow(
          color: const Color(0xFFFF5A4A).withValues(alpha: 0.32),
          blurRadius: 28,
          spreadRadius: 1,
        ),
      ];

  // -------------------------------------------------------
  //  ALIAS DÉPRÉCIÉS (compatibilité historique)
  // -------------------------------------------------------

  @Deprecated('Use AppColors.accent (ember)')
  static const Color accentPink = accent;

  @Deprecated('Use AppColors.textSecondary or AppColors.brassGlow')
  static const Color accentCyan = textSecondary;

  @Deprecated('Use AppColors.accent (ember)')
  static const Color gold = accent;

  /// Dégradé premium (ember → ember deep) — pour les CTAs principaux
  /// et les badges "Premium".
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[accent, accentMuted],
  );

  /// Helper context-aware (les deux modes).
  static LumiereColors lumiere(BuildContext context) =>
      LumiereColors.of(context);
}
