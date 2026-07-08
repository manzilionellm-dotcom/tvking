// =========================================================
//  app_colors.dart — Facade Cinema Mode du système The Few
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

import 'accent_controller.dart';
import 'lumiere_tokens.dart';

abstract final class AppColors {
  // -------------------------------------------------------
  //  FONDS / SURFACES (Cinema Mode The Few)
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
  //  ACCENT EMBER (rouge braise The Few)
  // -------------------------------------------------------

  //  --- ACCENT DYNAMIQUE (thème choisi par le client) ---
  //  Ces couleurs ne sont PLUS `const` : elles lisent le thème courant
  //  via AccentController. Changer de thème (bouton « Thème ») recolore
  //  toute l'app instantanément (la racine se reconstruit). Défaut =
  //  braise (#D63A30) → identique à avant tant que rien n'est choisi.

  /// Accent principal — couleur du thème actif (braise par défaut).
  static Color get accent => AccentController.instance.current.accent;

  /// Variante claire — glow, états focus / hover / brillance.
  static Color get accentBright => AccentController.instance.current.bright;

  /// Variante deep — bordures actives, sélections passives.
  static Color get accentMuted => AccentController.instance.current.muted;

  /// Halo — pour les glows sur CTAs primaires (= variante claire).
  static Color get emberHalo => AccentController.instance.current.bright;

  /// Voile très léger d'accent — fond d'un état sélectionné.
  static Color get accentSurface => accent.withValues(alpha: 0.14);

  // -------------------------------------------------------
  //  CRÈME ÉDITORIAL — accent non-critique (Phase 1 redesign)
  // -------------------------------------------------------
  //  Le brief design dit : réduire l'usage du rouge de 60-70 %.
  //  Le rouge (ember) ne sert PLUS qu'au critique (LIVE, focus
  //  actif, CTA primaire, sélection navigation). Pour tous les
  //  autres accents (eyebrows, badges éditoriaux, "VEDETTE",
  //  séparateurs de catégorie, citations…) on utilise un crème
  //  chaud désaturé (#E8D9C0) qui donne la sensation premium
  //  calme d'Apple TV+ ou de Criterion Channel.
  //
  //  NB : ce crème est DISTINCT de l'accent ember (`accent`).
  //  Anciennement nommé `champagne` — renommé `editorialCream`
  //  pour lever l'ambiguïté avec les tokens ember.

  /// Crème éditorial — accent principal non-critique (eyebrows,
  /// badges "À LA UNE", "RECOMMANDÉ", "NOUVEAU"). Ni or jaune
  /// agressif ni rouge — un crème chaud très tamisé.
  static const Color editorialCream = Color(0xFFE8D9C0);

  /// Crème éditorial profond — bordures fines et hovers
  /// non-critiques. Encore plus discret que `editorialCream`.
  static const Color editorialCreamDeep = Color(0xFFB39B7C);

  /// Voile crème — fond des chips éditoriaux.
  static Color get editorialCreamSurface =>
      const Color(0xFFE8D9C0).withValues(alpha: 0.10);

  /// Or royal Maison Noir — réservé aux actions « premium » ponctuelles
  /// (baguette « Optimiser la source », badges VIP). Plus soutenu que
  /// `editorialCream`, jamais utilisé pour du critique.
  static const Color royalGold = Color(0xFFCCB089);

  /// Voile or — fond mat des surfaces « premium » (boutons Optimiser).
  static Color get royalGoldSurface =>
      const Color(0xFFCCB089).withValues(alpha: 0.14);

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
  //  MAISON NOIR / BLACK7 — palette dédiée à l'accueil refondu
  //  (country_home). Charte Black7 : noir vrai OLED + ROUGE de marque
  //  (#E4202E), AUCUN or. Fixe (non pilotée par l'AccentController) pour
  //  une identité premium cohérente. Centralisée ici → jamais de
  //  Color(0xFF…) dans l'UI.
  // -------------------------------------------------------
  /// Fond noir vrai (économie batterie OLED). Charte Black7 #08080A.
  static const Color maisonBg = Color(0xFF08080A);
  /// Surface de carte.
  static const Color maisonSurface = Color(0xFF15151B);
  /// Surface surélevée (hover / hero).
  static const Color maisonSurfaceHigh = Color(0xFF1D1D25);
  /// Texte quasi-blanc (contraste fort seniors).
  static const Color maisonInk = Color(0xFFF7F7F5);
  /// ROUGE de marque Black7 (accent principal — remplace l'or).
  static const Color black7Red = Color(0xFFE4202E);
  /// Rouge foncé Black7 (dégradés, états).
  static const Color black7RedDeep = Color(0xFF8F1019);
  /// Rouge réservé au badge LIVE (Maison Noir / Black7).
  static const Color liveRed = Color(0xFFFF4D4F);
  /// Bordure subtile (blanc 8 %).
  static const Color maisonBorder = Color(0x14FFFFFF);

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

  /// Halo — pour les ombres d'accent sur CTAs primaires (suit le thème).
  static List<BoxShadow> get emberGlowShadow => <BoxShadow>[
        BoxShadow(
          color: accentBright.withValues(alpha: 0.32),
          blurRadius: 28,
          spreadRadius: 1,
        ),
      ];

  // -------------------------------------------------------
  //  ALIAS DÉPRÉCIÉS (compatibilité historique)
  // -------------------------------------------------------

  @Deprecated('Use AppColors.accent (ember)')
  static Color get accentPink => accent;

  @Deprecated('Use AppColors.textSecondary or AppColors.emberHalo')
  static const Color accentCyan = textSecondary;

  @Deprecated('Use AppColors.accent (ember)')
  static Color get gold => accent;

  /// Dégradé premium (accent → accent profond) — pour les CTAs
  /// principaux et les badges "Premium". Suit le thème courant.
  static LinearGradient get premiumGradient => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[accent, accentMuted],
      );

  /// Helper context-aware (les deux modes).
  static LumiereColors lumiere(BuildContext context) =>
      LumiereColors.of(context);
}
