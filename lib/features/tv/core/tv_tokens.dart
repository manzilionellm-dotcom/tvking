// =========================================================
//  tv_tokens.dart — Design System « Maison Noir » (The Few)
// =========================================================
//  Source de vérité UNIQUE des couleurs, rayons, dégradés et styles de
//  texte de DeFew TV. AUCUNE couleur en dur dans les écrans : tout passe
//  par ici. ADN : club privé, noir profond, or discret.
// =========================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TvTokens {
  TvTokens._();

  // ---- Couleurs — système de SURFACES en couches (la profondeur naît de
  //  l'empilement, pas des bordures). Refonte « quiet luxury » : noir CHAUD
  //  (jamais #000 → pas de banding OLED), accent champagne. ----
  static const Color bg = Color(0xFF08080A); // Surface 0 — noir chaud
  static const Color panel = Color(0xFF0E0E11); // sidebar (proche du fond)
  static const Color card = Color(0xFF141418); // Surface 1 — carte au repos
  static const Color tile = Color(0xFF1A1712); // fond des vignettes de chaînes
  static const Color tileBorder =
      Color(0x0DFFFFFF); // bordure vignette (blanc 5 %)
  static const Color badgeBg = Color(0x1F4ECDC4); // fond badge (accent ~12 %)
  static const Color sel = Color(0xFF1E1B16); // Surface 2 — focus / élevé
  static const Color surface3 = Color(0xFF242019); // overlay / menu déployé
  static const Color line = Color(0xFF2A2620); // hairline / bordure subtile
  static const Color lineSoft = Color(0xFF211D17); // bordures discrètes (repos)
  static const Color text = Color(0xFFECE6DA); // texte principal
  static const Color muted = Color(0xFF8A8A90); // texte secondaire
  static const Color mutedDim = Color(0xFF54545B); // texte tertiaire / hints
  // ---- ACCENT UNIQUE (décision client 2026-08-02) ----
  //  Le client voyait trois accents cohabiter à l'écran : le champagne des
  //  chaînes, le rouge braise du cinéma, et le turquoise de l'accueil à menu
  //  latéral (devenu le Modèle A, l'accueil principal). Sa demande, photos à
  //  l'appui : « il faut que tout ça se ressemble ». On unifie donc TOUT sur
  //  le turquoise du Modèle A — boutons, focus, badges, cercles de
  //  chargement, cinéma.
  //
  //  Les NOMS de tokens (gold, ember) restent : ils sont cités à ~60
  //  endroits, et les renommer n'aurait rien changé à l'écran tout en
  //  rendant la revue illisible. Seules les VALEURS changent — un retour en
  //  arrière tient en trois lignes ici.
  static const Color gold = Color(0xFF4ECDC4); // ACCENT (turquoise Modèle A)
  // Texte/icônes posés SUR une surface or (boutons pleins). Token créé à la
  // revue de code du 2026-07-16 : ce brun-noir était dupliqué en dur dans
  // les écrans (0xFF1A1206) — désormais une seule source de vérité.
  static const Color onGold = Color(0xFF04231F);
  static const Color goldBright = Color(0xFF7FE9E1); // FOCUS (texte + lueur)
  static const Color goldDeep = Color(0xFF2E9A93); // accent sombre : dégradés
  static const Color live =
      Color(0xFFD8453F); // pastille EN DIRECT (rouge vif sobre)

  // ----- CINÉMA : accent ROUGE BRAISE immersif (terrain 2026-07-17) -----
  // Demande client : côté Films & Séries, un rouge profond façon salle de
  // cinéma — moins lumineux que l'or, il « atténue le regard » dans le noir.
  // C'est le rouge ember de la marque 7 MOTION (#D63A30), décliné : accent,
  // variante focus (plus claire), variante sombre (dégradés), texte posé
  // dessus, et fond de badge translucide. Le LIVE garde l'or : deux mondes,
  // deux ambiances — même obsidienne.
  //  ALIGNÉ sur l'accent unique (2026-08-02) : le rouge braise tranchait
  //  trop avec l'accueil. Le bouton « Regarder », les pourcentages « pour
  //  vous » et les cercles du cinéma prennent le même turquoise.
  static const Color ember = Color(0xFF4ECDC4); // ACCENT Cinéma (aligné)
  static const Color emberBright = Color(0xFF7FE9E1); // focus / texte accent
  static const Color emberDeep = Color(0xFF2E9A93); // dégradés, ombres
  static const Color onEmber = Color(0xFF04231F); // texte sur bouton accent
  static const Color emberBadgeBg = Color(0x1F4ECDC4); // fond badge (12 %)

  /// Dégradé des accents Cinéma (barres de progression, bouton REGARDER…) —
  /// l'équivalent rouge du ctaGradient or.
  static const Gradient cineGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[emberBright, ember],
  );
  static const Color success = Color(0xFF5FA975); // ✓ copié

  // ---- Rayons ----
  static const double rCard = 14;
  static const double rButton = 14;
  static const double rMenuItem = 12;
  static const double rSmall = 8;
  static const double rGlass = 16; // rail verre (§3)
  // Hairline OR (gold 18%) — bordure premium (rail verre, badges, filets).
  static const Color hairline = Color(0x2ECCB089);

  // ---- Fond global « cathédrale » : lumière d'or qui tombe du haut,
  //  s'éteint en noir chaud puis se referme vers le bas. Trois arrêts au
  //  lieu de deux → la profondeur d'une salle de cinéma, pas un aplat. ----
  static const Gradient bgGradient = RadialGradient(
    center: Alignment(0.56, -0.40), // 78% / 30%
    radius: 1.45,
    colors: <Color>[Color(0xFF191510), Color(0xFF0D0C0D), bg],
    stops: <double>[0.0, 0.52, 0.95],
  );

  // ---- VIGNETTAGE cinéma : assombrit très légèrement les bords de l'écran.
  //  Trois effets d'un seul dégradé : (1) le regard est guidé vers le centre,
  //  (2) moins d'éblouissement dans un salon sombre (confort des yeux),
  //  (3) la profondeur « projection » des salles. Discret (≤ 14 %) pour ne
  //  jamais manger le contenu des bords. Posé en foregroundDecoration du
  //  TvShell → aucun widget de plus dans l'arbre. ----
  static const Gradient vignette = RadialGradient(
    center: Alignment.center,
    radius: 1.25,
    colors: <Color>[Color(0x00000000), Color(0x00000000), Color(0x24000000)],
    stops: <double>[0.0, 0.72, 1.0],
  );

  // ---- Halo chaud discret derrière le branding (coin haut-gauche) ----
  // Profondeur « premium » : évite le noir plat sous le logo The Few.
  static const Gradient brandGlow = RadialGradient(
    center: Alignment.topLeft,
    radius: 1.1,
    colors: <Color>[Color(0x14CCB089), Color(0x00000000)],
  );

  // ---- Filet d'accent or (haut de carte) ----
  static const Gradient goldHairline = LinearGradient(
    colors: <Color>[Color(0x00CCB089), gold, Color(0x00CCB089)],
  );

  // ---- CTA principal (dégradé or) ----
  static const Gradient ctaGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[goldBright, gold],
  );

  // ---- Pastille prix ----
  static const Gradient pillGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0x0FCCB089), Color(0x00CCB089)],
  );

  // =========================================================
  //  TYPOGRAPHIE — 3 rôles, jamais plus.
  //   • display = Oswald (titres d'accent, sobriété TV)
  //   • ui      = Inter  (tout le reste)
  //   • mono    = JetBrains Mono (code d'activation / identifiants UNIQUEMENT)
  // =========================================================
  // MÉMOÏSATION (revue perf) : ces helpers sont appelés dans les builders
  // de focus, exécutés à CHAQUE cran de D-pad (tuiles du Modèle B, boutons
  // Channels, rails…). Chaque appel GoogleFonts.xxx() refait un lookup de
  // cache de police + alloue un TextStyle : on fige le résultat par
  // combinaison (taille/graisse/couleur/espacement) — bornée par le design
  // system (3 rôles × quelques tailles), donc sans dérive mémoire.
  // Clé RECORD (égalité par valeur) et non un hash : une collision de hash
  // aurait renvoyé silencieusement le mauvais style.
  static final Map<(int, double, FontWeight, Color, double), TextStyle>
      _styleMemo = <(int, double, FontWeight, Color, double), TextStyle>{};

  static TextStyle _memo(int font, double size, FontWeight weight, Color color,
      double spacing, TextStyle Function() build) {
    return _styleMemo[(font, size, weight, color, spacing)] ??= build();
  }

  static TextStyle display(double size,
          {FontWeight weight = FontWeight.w600,
          Color color = text,
          double spacing = 0}) =>
      _memo(
          0,
          size,
          weight,
          color,
          spacing,
          () => GoogleFonts.cormorantGaramond(
              fontSize: size,
              fontWeight: weight,
              color: color,
              letterSpacing: spacing));

  static TextStyle ui(double size,
          {FontWeight weight = FontWeight.w400,
          Color color = text,
          double spacing = 0}) =>
      _memo(
          1,
          size,
          weight,
          color,
          spacing,
          () => GoogleFonts.manrope(
              fontSize: size,
              fontWeight: weight,
              color: color,
              letterSpacing: spacing));

  static TextStyle mono(double size,
          {FontWeight weight = FontWeight.w600,
          Color color = goldBright,
          double spacing = 0}) =>
      _memo(
          2,
          size,
          weight,
          color,
          spacing,
          () => GoogleFonts.jetBrainsMono(
              fontSize: size,
              fontWeight: weight,
              color: color,
              letterSpacing: spacing));
}
